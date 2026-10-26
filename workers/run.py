"""Run a worker on a local video, with no Modal and no database (#53):

    python -m workers.run workers.reference:ReferenceWorker clip.mp4 --source source.json

`source.json` is a template `source` section (see schema/examples). Its `content_hash` is replaced with the video's real
hash, so you can reuse one source file across clips. Results are cached under `--cache-dir`, so a second run says "hit".
"""

import argparse
import hashlib
import importlib
import json
import sys
from pathlib import Path

from workers.base import Job, Worker
from workers.cache import FileResultStore
from workers.storage import LocalFetcher


def load_worker_class(spec: str) -> type[Worker]:
    module, _, name = spec.partition(":")
    cls = getattr(importlib.import_module(module), name)
    if not (isinstance(cls, type) and issubclass(cls, Worker)):
        raise SystemExit(f"{spec} is not a Worker subclass")
    return cls


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "worker", help="module:Class, e.g. workers.reference:ReferenceWorker"
    )
    parser.add_argument("video", type=Path)
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="JSON file with the template's source section",
    )
    parser.add_argument("--cache-dir", type=Path, default=Path(".worker-cache"))
    args = parser.parse_args(argv)

    source = json.loads(args.source.read_text())
    source["content_hash"] = (
        "sha256:" + hashlib.sha256(args.video.read_bytes()).hexdigest()
    )
    worker = load_worker_class(args.worker)(
        FileResultStore(args.cache_dir), LocalFetcher()
    )
    result = worker.run(Job("local", str(args.video), source))
    print("cache hit" if result.cached else "cache miss", file=sys.stderr)
    print(json.dumps(result.partial, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
