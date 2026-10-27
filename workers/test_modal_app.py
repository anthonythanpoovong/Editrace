"""The Modal app (#7, #320), checked without a Modal account: the function wiring, the container's pins, and a job run
end to end through `run()` on a synthetic video."""

from __future__ import annotations

import hashlib
import tomllib
from pathlib import Path

import pytest

modal = pytest.importorskip("modal")
pytest.importorskip("scenedetect")

from workers import modal_app
from workers.base import Compute
from workers.cache import FileResultStore
from workers.cuts.test_detect import make_video
from workers.cuts.worker import CutsWorker
from workers.storage import LocalFetcher

PYPROJECT = Path(__file__).resolve().parents[1] / "pyproject.toml"


def test_the_container_pins_match_pyproject() -> None:
    """The container must run the versions the tests and the golden set measured."""
    project = tomllib.loads(PYPROJECT.read_text())["project"]
    assert modal_app.CUTS_PACKAGES == project["optional-dependencies"]["cuts"]
    assert modal_app.BASE_PACKAGES == project["dependencies"]
    deploy = project["optional-dependencies"]["deploy"]
    assert deploy == [f"modal=={modal.__version__}"]


def test_the_cut_worker_is_a_function_sized_from_its_compute() -> None:
    assert modal_app.app.name == modal_app.APP_NAME
    assert isinstance(modal_app.cuts, modal.Function)
    assert modal_app.resources(CutsWorker.compute) == {
        "cpu": CutsWorker.compute.cpu,
        "memory": CutsWorker.compute.memory_mb,
        "timeout": CutsWorker.compute.timeout_s,
    }


def test_a_gpu_is_only_requested_when_the_worker_asks() -> None:
    assert "gpu" not in modal_app.resources(Compute())
    assert modal_app.resources(Compute(gpu="T4"))["gpu"] == "T4"


def test_a_job_runs_through_the_worker_and_persists_only_new_results(
    tmp_path: Path,
) -> None:
    video = make_video(tmp_path / "clip.mp4", 60, [30])
    job = {
        "job_id": "job-1",
        "video": str(video),
        "source": {
            "duration": 60,
            "fps": {"num": 30, "den": 1},
            "resolution": {"width": 96, "height": 64},
            "aspect_ratio": {"num": 3, "den": 2},
            "content_hash": "sha256:" + hashlib.sha256(video.read_bytes()).hexdigest(),
        },
    }
    store, commits = FileResultStore(tmp_path / "results"), []

    first = modal_app.run(
        CutsWorker, job, store, LocalFetcher(), lambda: commits.append(1)
    )
    second = modal_app.run(
        CutsWorker, job, store, LocalFetcher(), lambda: commits.append(1)
    )

    assert not first["cached"] and second["cached"]
    assert [c["frame"] for c in first["partial"]["tracks"][0]["cuts"]] == [30]
    assert second["partial"] == first["partial"]
    assert commits == [1]  # only the new result is committed to the volume
