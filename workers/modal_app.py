"""The Modal app for the analysis workers (#7, #320): each worker becomes a Modal function sized from its `compute`.

    modal deploy --env main workers/modal_app.py                             # what deploy.yml runs (#302)
    modal run --env main workers/modal_app.py --job-file job.json            # one job, e.g. to time it

Staging and prod are separate Modal workspaces, each deploying to its default `main` environment (ADR 0004, #337). The
token picks the workspace, so check `modal profile current` is the staging one before a run by hand.

A job is `{"job_id": ..., "video": <signed https URL>, "source": <the template's source section>}`; the function
returns `{"partial": ..., "cached": ...}`. The worker base (#53) does the fetching, caching, provenance, validation and
status. Results are cached on a Modal Volume per workspace until the shared Postgres store (#301) replaces it.

`modal deploy` loads this file on the deploy runner, where only `modal` is installed (#302). So nothing at the top level
may need the worker stack: the workers are imported inside `image.imports()` (in the container only), and each
function's resources are written out here. test_modal_app.py loads the file with the worker stack blocked, and checks
the resources still match each worker's `compute`.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING, Any

import modal

if TYPE_CHECKING:
    from workers.base import Worker
    from workers.cache import ResultStore
    from workers.storage import Fetcher

APP_NAME = "editrace-workers"
RESULTS_DIR = Path("/results")

# The container runs the versions the tests and the golden set measured: pydantic as pinned in uv.lock, the detector
# as pinned in pyproject.toml's `cuts` extra. test_modal_app.py fails if they drift apart.
BASE_PACKAGES = ["pydantic==2.14.1"]
CUTS_PACKAGES = ["scenedetect==0.7.2", "opencv-python==5.0.0.93"]

# Each worker's `compute`, as Modal function arguments (test_modal_app.py checks they match).
CUTS_RESOURCES: dict[str, Any] = {"cpu": 2.0, "memory": 4096, "timeout": 300}

app = modal.App(APP_NAME)
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libgl1", "libglib2.0-0")  # opencv-python links against them
    .pip_install(*BASE_PACKAGES, *CUTS_PACKAGES)
    .add_local_python_source("workers", "editrace_schema")
)
# Volumes belong to one workspace, so staging and prod keep separate caches.
results = modal.Volume.from_name("editrace-worker-results", create_if_missing=True)

# Imported in the container, and locally only when the worker stack is installed.
with image.imports():
    from workers.base import Job
    from workers.cache import FileResultStore
    from workers.common.log import get_logger
    from workers.cuts.worker import CutsWorker
    from workers.storage import HttpsFetcher


def run(
    worker_cls: type[Worker],
    job: dict[str, Any],
    store: ResultStore,
    fetcher: Fetcher,
    persist: Callable[[], None] = lambda: None,
) -> dict[str, Any]:
    """Run one job through a worker. Plain Python, so the tests cover it without Modal."""
    # The base logs status at INFO, which Python hides by default; this shows it, as JSON.
    get_logger("editrace.workers")
    worker = worker_cls(store, fetcher)
    result = worker.run(Job(job["job_id"], job["video"], job["source"]))
    if not result.cached:
        persist()  # make the new cache entry visible to other containers
    return {"partial": result.partial, "cached": result.cached}


@app.function(image=image, volumes={str(RESULTS_DIR): results}, **CUTS_RESOURCES)
def cuts(job: dict[str, Any]) -> dict[str, Any]:
    return run(
        CutsWorker, job, FileResultStore(RESULTS_DIR), HttpsFetcher(), results.commit
    )


@app.local_entrypoint()
def main(job_file: str) -> None:
    """`modal run workers/modal_app.py --job-file job.json`: run one cut job remotely and print the result."""
    result = cuts.remote(json.loads(Path(job_file).read_text()))
    print(json.dumps(result, indent=2))
