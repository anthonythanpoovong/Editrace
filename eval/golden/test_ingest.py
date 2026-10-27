"""ingest.py, with ffmpeg and ffprobe faked: which conform path a video takes, and what lands in the manifest and the
label skeleton. The real tools are exercised by running it on the golden videos, which never reach CI."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import ingest
import pytest

from editrace_schema import Template

REAL_WHICH = shutil.which


class FakeTools:
    """Stands in for subprocess.run. Originals report `original_pts`; anything ffmpeg writes is clean 30 fps CFR."""

    def __init__(self, original_pts: list[float], frames: int = 90) -> None:
        self.original_pts = original_pts
        self.frames = frames
        self.calls: list[list[str]] = []

    def __call__(self, cmd: list[str], **_kwargs) -> SimpleNamespace:
        self.calls.append(cmd)
        tool, path = Path(cmd[0]).stem, cmd[-1]  # stem: ffmpeg.exe on Windows
        if tool == "ffprobe" and "stream=width,height,r_frame_rate,nb_frames" in cmd:
            stream = {"width": 720, "height": 1280, "r_frame_rate": "30/1"}
            return SimpleNamespace(stdout=json.dumps({"streams": [stream]}))
        if tool == "ffprobe":
            pts = (
                [i / 30 for i in range(self.frames)]
                if path.endswith(".mp4")
                else self.original_pts
            )
            return SimpleNamespace(stdout="\n".join(f"{t:.6f}" for t in pts) + "\n")
        if cmd[1:] == ["-version"]:
            return SimpleNamespace(
                stdout="ffmpeg version 7.1 Copyright (c) the FFmpeg developers"
            )
        Path(path).write_bytes(
            b"conformed " + Path(cmd[cmd.index("-i") + 1]).read_bytes()
        )
        return SimpleNamespace(stdout="")

    def conform_cmds(self) -> list[list[str]]:
        return [c for c in self.calls if Path(c[0]).stem == "ffmpeg" and "-i" in c]


@pytest.fixture
def golden(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    root = tmp_path / "golden"
    root.mkdir()
    monkeypatch.setattr(ingest, "ROOT", root)
    monkeypatch.setattr(ingest, "MANIFEST", root / "manifest.json")
    monkeypatch.setattr(
        ingest.shutil, "which", lambda name, path=None: f"/usr/bin/{name}"
    )
    return root


def original(
    tmp_path: Path, name: str = "clip.mov", content: bytes = b"raw video"
) -> Path:
    path = tmp_path / name
    path.write_bytes(content)
    return path


def run(monkeypatch: pytest.MonkeyPatch, tools: FakeTools, *args: str) -> None:
    monkeypatch.setattr(subprocess, "run", tools)
    monkeypatch.setattr(sys, "argv", ["ingest.py", *args])
    ingest.main()


def manifest(golden: Path) -> dict:
    return json.loads((golden / "manifest.json").read_text())


def test_cfr_upload_is_remuxed_losslessly(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    tools = FakeTools([i / 30 for i in range(90)])
    src = original(tmp_path)
    run(monkeypatch, tools, str(src))

    (cmd,) = tools.conform_cmds()
    assert cmd[cmd.index("-c") + 1] == "copy" and "libx264" not in cmd
    out = golden / "videos" / "v01.mp4"
    content_hash = f"sha256:{hashlib.sha256(out.read_bytes()).hexdigest()}"

    (entry,) = manifest(golden)["videos"]
    assert entry["id"] == "v01"
    assert entry["original_sha256"] == hashlib.sha256(b"raw video").hexdigest()
    assert entry["content_hash"] == content_hash
    assert entry["frames"] == 90 and entry["fps"] == {"num": 30, "den": 1}
    assert entry["vfr"] is False and entry["labeled"] is False

    label = json.loads((golden / "labels" / "v01.json").read_text())
    assert label["schema_version"] == ingest.SCHEMA_VERSION
    assert label["source"] == {
        "duration": 90,
        "fps": {"num": 30, "den": 1},
        "resolution": {"width": 720, "height": 1280},
        "aspect_ratio": {"num": 9, "den": 16},
        "content_hash": content_hash,
    }
    assert label["tracks"][0]["cuts"] == [] and label["tracks"][0]["transitions"] == []
    Template.model_validate(label)


def test_vfr_upload_is_conformed_and_marked(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    jittery = [0.0, 0.033, 0.07, 0.1, 0.141, 0.166]
    tools = FakeTools(jittery)
    run(monkeypatch, tools, str(original(tmp_path)))

    (cmd,) = tools.conform_cmds()
    assert cmd[cmd.index("-r") + 1] == "30/1" and "libx264" in cmd
    (entry,) = manifest(golden)["videos"]
    assert entry["vfr"] is True
    source = json.loads((golden / "labels" / "v01.json").read_text())["source"]
    assert source["vfr"] is True
    assert source["original_fps"] == {"num": 30, "den": 1}
    assert source["conform"] == {"detector": "ffmpeg", "version": "7.1"}
    Template.model_validate(json.loads((golden / "labels" / "v01.json").read_text()))


def test_rerun_skips_known_originals_and_numbers_new_ones(
    golden: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    cfr = [i / 30 for i in range(90)]
    first = original(tmp_path, "a.mov", b"first")
    run(monkeypatch, FakeTools(cfr), str(first))
    run(
        monkeypatch,
        FakeTools(cfr),
        str(first),
        str(original(tmp_path, "b.mov", b"second")),
    )

    assert [v["id"] for v in manifest(golden)["videos"]] == ["v01", "v02"]
    assert "skip a.mov: already ingested" in capsys.readouterr().out


def fake_executables(folder: Path, *names: str) -> Path:
    folder.mkdir()
    for name in names:
        exe = folder / (name + (".exe" if os.name == "nt" else ""))
        exe.write_text("")
        exe.chmod(0o755)
    return folder


def test_ffmpeg_dir_is_used_when_given(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(ingest.shutil, "which", REAL_WHICH)
    tools_dir = fake_executables(tmp_path / "bin", "ffmpeg", "ffprobe")
    tools = FakeTools([i / 30 for i in range(90)])
    run(monkeypatch, tools, "--ffmpeg-dir", str(tools_dir), str(original(tmp_path)))
    assert {Path(c[0]).parent for c in tools.calls} == {tools_dir}


def test_wrong_ffmpeg_dir_stops(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A folder without the tools used to slip through and fail later inside subprocess.run.
    monkeypatch.setattr(ingest.shutil, "which", REAL_WHICH)
    wrong = fake_executables(tmp_path / "bin", "ffprobe")
    with pytest.raises(
        SystemExit, match=f"ffmpeg not found in {re.escape(str(wrong))}"
    ):
        run(
            monkeypatch,
            FakeTools([]),
            "--ffmpeg-dir",
            str(wrong),
            str(original(tmp_path)),
        )
    assert not (golden / "manifest.json").exists()


def test_missing_ffmpeg_stops(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(ingest.shutil, "which", lambda name, path=None: None)
    with pytest.raises(SystemExit, match="ffmpeg not found on PATH"):
        run(monkeypatch, FakeTools([]), str(original(tmp_path)))
    assert not (golden / "manifest.json").exists()


CFR = [i / 30 for i in range(90)]


def existing(golden: Path, *ids: str) -> None:
    videos = [{"id": i, "original_sha256": f"hash-of-{i}"} for i in ids]
    (golden / "manifest.json").write_text(json.dumps({"videos": videos}))


def ids(golden: Path) -> list[str]:
    return [v["id"] for v in manifest(golden)["videos"]]


def test_a_vnn_file_name_is_the_id(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    existing(golden, "v01", "v02")
    run(monkeypatch, FakeTools(CFR), str(original(tmp_path, "v13.mov")))
    assert ids(golden) == ["v01", "v02", "v13"]
    assert (golden / "videos" / "v13.mp4").exists() and (
        golden / "labels" / "v13.json"
    ).exists()


def test_other_names_get_one_more_than_the_highest_id(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # Counting entries would give v04 here, which is taken; the highest id is v08, so the next is v09.
    existing(golden, "v01", "v05", "v08")
    run(monkeypatch, FakeTools(CFR), str(original(tmp_path, "IMG_4821.mov")))
    assert ids(golden)[-1] == "v09"


def test_names_that_only_look_like_ids_are_numbered(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    run(
        monkeypatch,
        FakeTools(CFR),
        str(original(tmp_path, "v1.mov", b"a")),
        str(original(tmp_path, "clip2.mov", b"b")),
    )
    assert ids(golden) == ["v01", "v02"]


def test_a_batch_numbers_past_the_named_files_in_it(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    existing(golden, "v01")
    run(
        monkeypatch,
        FakeTools(CFR),
        str(original(tmp_path, "v13.mov", b"a")),
        str(original(tmp_path, "clip.mov", b"b")),
    )
    assert ids(golden) == ["v01", "v13", "v14"]


def test_a_taken_id_stops_the_run_before_anything_is_written(
    golden: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    existing(golden, "v13")
    before = (golden / "manifest.json").read_text()
    clean, taken = (
        original(tmp_path, "clip.mov", b"a"),
        original(tmp_path, "v13.mov", b"b"),
    )
    with pytest.raises(SystemExit, match="v13 is already in the manifest"):
        run(monkeypatch, FakeTools(CFR), str(clean), str(taken))
    assert (golden / "manifest.json").read_text() == before
    assert not (golden / "videos").exists() or not any((golden / "videos").iterdir())


def test_an_original_already_at_its_output_path_is_refused(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (golden / "videos").mkdir()
    inside = golden / "videos" / "v13.mp4"
    inside.write_bytes(b"the only copy")
    with pytest.raises(SystemExit, match="move it out of videos/"):
        run(monkeypatch, FakeTools(CFR), str(inside))
    assert inside.read_bytes() == b"the only copy"
