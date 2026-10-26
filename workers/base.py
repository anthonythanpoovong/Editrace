"""The base every analysis worker builds on (#53): fetch the video, run the detector, stamp provenance, validate, store
the result, report status. A worker implements `detect()` and declares its name, version and compute, and nothing else.

Modal is deliberately not imported here. The base is plain Python so the local runner and the tests exercise the same
code the GPU container does; `compute` is data a Modal wrapper reads when the first real worker deploys (#7).
"""

import json
import random
import tempfile
import time
import urllib.error
from abc import ABC, abstractmethod
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ClassVar, TypeVar

from editrace_schema import Template
from editrace_schema.constants import SCHEMA_VERSION
from workers.cache import CacheKey, Partial, ResultStore, params_hash
from workers.status import LoggingReporter, State, StatusEvent, StatusReporter
from workers.storage import Fetcher, download

T = TypeVar("T")

PARTIAL_SECTIONS = {
    "tracks",
    "beats",
    "sound_ref",
}  # `source` and `schema_version` belong to the orchestrator


class TransientError(Exception):
    """Raise from `detect()` for a failure worth retrying, such as a model-server timeout. Anything else fails the run."""


def is_transient(exc: BaseException) -> bool:
    """Retry only what a second attempt can fix. A bug, a bad parameter or a missing file would fail the same way again,
    and a retry on a GPU container is billed."""
    if isinstance(exc, TransientError | TimeoutError | ConnectionError):
        return True
    if isinstance(exc, urllib.error.HTTPError):
        return exc.code in (408, 429) or exc.code >= 500
    if isinstance(exc, FileNotFoundError | PermissionError | IsADirectoryError):
        return False
    return isinstance(exc, OSError)


@dataclass(frozen=True)
class RetryPolicy:
    """Capped attempts with exponential backoff and full jitter. Footage match (#102) reuses this policy."""

    max_attempts: int = 3
    base_delay_s: float = 1.0
    max_delay_s: float = 30.0

    def call(
        self,
        fn: Callable[[], T],
        sleep: Callable[[float], None] = time.sleep,
        rand: Callable[[], float] = random.random,
    ) -> T:
        for attempt in range(1, self.max_attempts + 1):
            try:
                return fn()
            except Exception as exc:
                if attempt == self.max_attempts or not is_transient(exc):
                    raise
                sleep(
                    rand()
                    * min(self.max_delay_s, self.base_delay_s * 2 ** (attempt - 1))
                )
        raise AssertionError(
            "unreachable"
        )  # the loop returns or raises; this keeps the type checker honest


@dataclass(frozen=True)
class Compute:
    """What a worker needs to run. A Modal wrapper turns this into a function's resources."""

    gpu: str | None = None  # e.g. "T4"; None runs on CPU
    cpu: float = 1.0
    memory_mb: int = 2048
    timeout_s: int = 600


@dataclass(frozen=True)
class Job:
    job_id: str
    video: str  # where the Fetcher finds the video: a signed https URL in production
    source: Mapping[
        str, Any
    ]  # the template's `source` section; its `content_hash` keys the cache


@dataclass(frozen=True)
class RunResult:
    partial: Partial
    cached: bool
    key: CacheKey


class Worker(ABC):
    name: ClassVar[str]  # the provenance `detector`, e.g. "cuts"
    version: ClassVar[
        str
    ]  # bump on any change that can change the output; it is part of the cache key
    compute: ClassVar[Compute] = Compute()

    def __init__(
        self,
        store: ResultStore,
        fetcher: Fetcher,
        reporter: StatusReporter | None = None,
        retry: RetryPolicy | None = None,
    ) -> None:
        self.store = store
        self.fetcher = fetcher
        self.reporter = reporter or LoggingReporter()
        self.retry = retry or RetryPolicy()

    def params(self) -> Mapping[str, Any]:
        """Settings that change the output (thresholds, model name). JSON-serializable. They are part of the cache key."""
        return {}

    @abstractmethod
    def detect(self, video: Path, job: Job) -> Partial:
        """Analyze `video` and return the sections you found: `tracks`, `beats` and `sound_ref`. Every element needs a
        `confidence`; `provenance` is stamped for you. Raise `TransientError` for a failure worth retrying."""

    def key_for(self, job: Job) -> CacheKey:
        return CacheKey(
            job.source["content_hash"],
            self.name,
            self.version,
            params_hash(self.params()),
        )

    def run(self, job: Job) -> RunResult:
        key = self.key_for(job)
        hit = self.store.get(key)
        if hit is not None:
            self._report(job, State.SUCCEEDED, cached=True)
            return RunResult(hit, cached=True, key=key)

        self._report(job, State.RUNNING)
        started = time.monotonic()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                video = Path(tmp) / "video"
                self.retry.call(
                    lambda: download(self.fetcher, job.video, video, key.content_hash)
                )
                raw = self.retry.call(lambda: self.detect(video, job))
            partial = self._finish(raw, job)
            self.store.put(key, partial)
        except Exception as exc:
            self._report(
                job,
                State.FAILED,
                duration_s=time.monotonic() - started,
                error=f"{type(exc).__name__}: {exc}"[:500],
            )
            raise
        self._report(job, State.SUCCEEDED, duration_s=time.monotonic() - started)
        return RunResult(partial, cached=False, key=key)

    def _finish(self, raw: Partial, job: Job) -> Partial:
        unknown = set(raw) - PARTIAL_SECTIONS
        if unknown:
            raise ValueError(
                f"{self.name} returned sections a worker doesn't own: {sorted(unknown)}"
            )
        partial = json.loads(
            json.dumps(raw)
        )  # fails on a value that can't be stored, such as a numpy float
        self._stamp(partial)
        Template.model_validate(
            {
                "schema_version": SCHEMA_VERSION,
                "source": job.source,
                "tracks": [],
                **partial,
            }
        )
        return partial

    def _stamp(self, node: Any) -> None:
        """Set `provenance` on every detected element. An element that names another detector or version is a bug: the
        cache key says this worker version made it."""
        if isinstance(node, dict):
            if "confidence" in node:
                stamp = {"detector": self.name, "version": self.version}
                if node.setdefault("provenance", stamp) != stamp:
                    raise ValueError(
                        f"{self.name} {self.version} emitted an element with provenance {node['provenance']}"
                    )
            for child in node.values():
                self._stamp(child)
        elif isinstance(node, list):
            for child in node:
                self._stamp(child)

    def _report(self, job: Job, state: State, **fields: Any) -> None:
        self.reporter.report(
            StatusEvent(job.job_id, self.name, self.version, state, **fields)
        )
