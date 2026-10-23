"""The result store: a re-run with the same inputs returns the stored partial template instead of spending GPU time (#53).

The key is the video's content hash, the worker, the worker's version and a hash of its parameters. The parameters are
in the key because a changed threshold must not return a result made with the old one. Only successful runs are
stored, so a failure is always retried.

`ResultStore` is the seam: `FileResultStore` serves the local runner and the tests. A shared store in Postgres
belongs with the orchestrator and `jobs` table (#58, #59), and plugs in here without touching the base worker. Whether a
hit may cross users is decided with that store, since the key has no user in it.
"""

import hashlib
import json
import os
import re
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from editrace_schema.constants import SCHEMA_VERSION

Partial = dict[
    str, Any
]  # the sections of a template one worker produced: tracks, beats and sound_ref

_SAFE = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._+-]*$"
)  # worker and version become directory names
CONTENT_HASH = re.compile(r"^sha256:[0-9a-f]{64}$")


def params_hash(params: Mapping[str, Any]) -> str:
    canonical = json.dumps(params, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


@dataclass(frozen=True)
class CacheKey:
    content_hash: str
    worker: str
    version: str
    params_hash: str

    def __post_init__(self) -> None:
        if not CONTENT_HASH.match(self.content_hash):
            raise ValueError(
                f"content_hash must be sha256: plus 64 hex characters, got {self.content_hash!r}"
            )
        for field, value in (("worker", self.worker), ("version", self.version)):
            if not _SAFE.match(value):
                raise ValueError(
                    f"{field} {value!r} must be letters, digits, '.', '_', '+' or '-'"
                )

    @property
    def digest(self) -> str:
        joined = (
            f"{self.content_hash}\0{self.worker}\0{self.version}\0{self.params_hash}"
        )
        return hashlib.sha256(joined.encode()).hexdigest()


class ResultStore(Protocol):
    def get(self, key: CacheKey) -> Partial | None: ...

    def put(self, key: CacheKey, partial: Partial) -> None: ...


class FileResultStore:
    """One JSON file per result under `root/<worker>/<version>/`. Writes are atomic, so two runs racing on the same key
    leave one complete file, and an unreadable or stale file is a miss, never an error."""

    def __init__(self, root: Path) -> None:
        self.root = root

    def _path(self, key: CacheKey) -> Path:
        return self.root / key.worker / key.version / f"{key.digest}.json"

    def get(self, key: CacheKey) -> Partial | None:
        try:
            envelope = json.loads(self._path(key).read_text())
        except (OSError, ValueError):
            return None
        # A result validated against another schema version may no longer validate: treat it as a miss.
        if (
            not isinstance(envelope, dict)
            or envelope.get("key") != key.digest
            or envelope.get("schema_version") != SCHEMA_VERSION
        ):
            return None
        partial = envelope.get("partial")
        return partial if isinstance(partial, dict) else None

    def put(self, key: CacheKey, partial: Partial) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        envelope = {
            "key": key.digest,
            "schema_version": SCHEMA_VERSION,
            "partial": partial,
        }
        fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(envelope, f)
            os.replace(tmp, path)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
