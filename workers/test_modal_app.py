"""The Modal app (#7, #320), checked without a Modal account: it loads where deploy.yml loads it, its container pins
and resources match what was tested, and a job runs end to end through `run()` on a synthetic video."""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import textwrap
import tomllib
from pathlib import Path

import pytest

modal = pytest.importorskip("modal")
pytest.importorskip("scenedetect")

from workers import modal_app
from workers.cache import FileResultStore
from workers.cuts.test_detect import make_video
from workers.cuts.worker import CutsWorker
from workers.storage import LocalFetcher

REPO = Path(__file__).resolve().parents[1]


def test_it_loads_with_only_modal_installed() -> None:
    """deploy.yml (#302) runs `modal deploy workers/modal_app.py` with nothing but `modal` installed. Block the worker
    stack and load the file the way the Modal CLI does."""
    script = textwrap.dedent(
        """
        import importlib.abc, sys
        BLOCKED = {"pydantic", "scenedetect", "cv2", "numpy", "editrace_schema"}
        class Block(importlib.abc.MetaPathFinder):
            def find_spec(self, name, path, target=None):
                if name.split(".")[0] in BLOCKED:
                    raise ModuleNotFoundError(f"No module named {name!r} (blocked)")
        sys.meta_path.insert(0, Block())
        import modal.cli.import_refs as refs
        refs.import_file_or_module(refs.parse_import_ref("workers/modal_app.py"), base_cmd="modal deploy")
        print("loaded")
        """
    )
    done = subprocess.run(
        [sys.executable, "-c", script],
        check=False,
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    assert done.returncode == 0, done.stderr[-2000:]
    assert "loaded" in done.stdout


def test_the_container_pins_match_what_was_tested() -> None:
    project = tomllib.loads((REPO / "pyproject.toml").read_text())["project"]
    assert modal_app.CUTS_PACKAGES == project["optional-dependencies"]["cuts"]
    assert project["optional-dependencies"]["deploy"] == [f"modal=={modal.__version__}"]
    locked = re.search(
        r'^name = "pydantic"\nversion = "([^"]+)"',
        (REPO / "uv.lock").read_text(),
        re.MULTILINE,
    )
    assert locked and modal_app.BASE_PACKAGES == [f"pydantic=={locked.group(1)}"]


def test_the_function_resources_match_the_workers_compute() -> None:
    compute = CutsWorker.compute
    expected = {
        "cpu": compute.cpu,
        "memory": compute.memory_mb,
        "timeout": compute.timeout_s,
    }
    if compute.gpu:
        expected["gpu"] = compute.gpu
    assert modal_app.CUTS_RESOURCES == expected
    assert isinstance(modal_app.cuts, modal.Function)
    assert modal_app.app.name == modal_app.APP_NAME


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
