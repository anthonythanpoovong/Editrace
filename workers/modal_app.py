"""The Modal app for the analysis workers (#7, #320): each worker becomes a Modal function sized from its `compute`.

    modal deploy --env staging workers/modal_app.py                          # what deploy.yml runs (#302)
    modal run --env staging workers/modal_app.py --job-file job.json         # one job, e.g. to time it

A job is `{"job_id": ..., "video": <signed https URL>, "source": <the template's source section>}`; the function
returns `{"partial": ..., "cached": ...}`. The worker base (#53) does the fetching, caching, provenance, validation and
status. Results are cached on a Modal Volume per environment until the shared Postgres store (#301) replaces it.

Importing this file needs `modal` (the `deploy` extra) but no Modal account: nothing talks to Modal until a deploy or run.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path
from typing import Any

import modal

from workers.base import Compute, Job, Worker
from workers.cache import FileResultStore, ResultStore
from workers.common.log import get_logger
from workers.cuts.worker import CutsWorker
from workers.storage import Fetcher, HttpsFetcher

APP_NAME = "editrace-workers"
RESULTS_DIR = Path("/results")

# The same pins as pyproject.toml's extras, so the container runs what the tests and the golden set measured.
# test_modal_app.py fails if they drift apart.
CUTS_PACKAGES = ["scenedetect==0.7.2", "opencv-python==5.0.0.93"]
BASE_PACKAGES = ["pydantic>=2"]

app = modal.App(APP_NAME)
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libgl1", "libglib2.0-0")  # opencv-python links against them
    .pip_install(*BASE_PACKAGES, *CUTS_PACKAGES)
    .add_local_python_source("workers", "editrace_schema")
)
# Volumes belong to one Modal environment, so staging and prod keep separate caches.
results = modal.Volume.from_name("editrace-worker-results", create_if_missing=True)


def resources(compute: Compute) -> dict[str, Any]:
    """A worker's `compute`, as Modal function arguments."""
    out: dict[str, Any] = {
        "cpu": compute.cpu,
        "memory": compute.memory_mb,
        "timeout": compute.timeout_s,
    }
    if compute.gpu:
        out["gpu"] = compute.gpu
    return out


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


@app.function(
    image=image, volumes={str(RESULTS_DIR): results}, **resources(CutsWorker.compute)
)
def cuts(job: dict[str, Any]) -> dict[str, Any]:
    return run(
        CutsWorker, job, FileResultStore(RESULTS_DIR), HttpsFetcher(), results.commit
    )


@app.local_entrypoint()
def main(job_file: str) -> None:
    """`modal run workers/modal_app.py --job-file job.json`: run one cut job remotely and print the result."""
    result = cuts.remote(json.loads(Path(job_file).read_text()))
    print(json.dumps(result, indent=2))
