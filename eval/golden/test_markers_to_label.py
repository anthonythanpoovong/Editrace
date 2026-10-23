"""markers_to_label.py turns labeler/Resolve markers into the committed golden labels, so a bug here corrupts the
answer key every detector is scored against."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import markers_to_label as m
import pytest

DURATION = 300


@pytest.fixture
def golden(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A throwaway eval/golden with one 300-frame, 30 fps video, v01."""
    (tmp_path / "labels").mkdir()
    label = {
        "schema_version": "0.1.0",
        "source": {"duration": DURATION, "fps": {"num": 30, "den": 1}},
        "tracks": [
            {
                "id": "video-1",
                "kind": "video",
                "slots": [],
                "cuts": [],
                "transitions": [],
            }
        ],
    }
    (tmp_path / "labels" / "v01.json").write_text(json.dumps(label))
    entry = {
        "id": "v01",
        "labeled": False,
        "labeling_minutes": None,
        "notes": ["kept", "flash: cut at frame 9"],
        "ambiguous": [9],
    }
    (tmp_path / "manifest.json").write_text(json.dumps({"videos": [entry]}))
    monkeypatch.setattr(m, "ROOT", tmp_path)
    return tmp_path


def run(monkeypatch: pytest.MonkeyPatch, *args: str) -> None:
    monkeypatch.setattr(sys, "argv", ["markers_to_label.py", *args])
    m.main()


def saved(golden: Path, markers: list[dict], **extra) -> Path:
    path = golden / "v01.markers.json"
    path.write_text(
        json.dumps({"video_id": "v01", "frames": DURATION, "markers": markers, **extra})
    )
    return path


def marker(frame: int, name: str = "cut", duration: int = 1) -> dict:
    return {"frame": frame, "name": name, "duration": duration}


def track(golden: Path) -> dict:
    return json.loads((golden / "labels" / "v01.json").read_text())["tracks"][0]


def entry(golden: Path) -> dict:
    return json.loads((golden / "manifest.json").read_text())["videos"][0]


def test_cuts_become_slot_boundaries(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    run(
        monkeypatch,
        "v01",
        str(saved(golden, [marker(200), marker(100)], labeling_minutes=7)),
    )
    t = track(golden)
    assert [c["frame"] for c in t["cuts"]] == [100, 200]
    assert [c["id"] for c in t["cuts"]] == ["cut-1", "cut-2"]
    assert (
        t["cuts"][0]["confidence"] == 1
        and t["cuts"][0]["provenance"]["detector"] == "manual"
    )
    assert [(s["range"]["start"], s["range"]["duration"]) for s in t["slots"]] == [
        (0, 100),
        (100, 100),
        (200, 100),
    ]
    assert t["transitions"] == []
    e = entry(golden)
    assert e["labeled"] is True and e["labeling_minutes"] == 7


def test_flash_and_ambiguous_go_to_the_manifest(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    run(
        monkeypatch,
        "v01",
        str(saved(golden, [marker(50, "flash"), marker(51), marker(120, "cut?")])),
    )
    assert [c["frame"] for c in track(golden)["cuts"]] == [50, 51, 120]
    e = entry(golden)
    # Old flash notes are replaced, other notes are kept; ambiguous is rewritten from scratch.
    assert e["notes"] == ["kept", "flash: cut at frame 50"]
    assert e["ambiguous"] == [120]
    assert e["labeling_minutes"] is None


def test_transition_without_a_cut_splits_at_its_middle(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    run(monkeypatch, "v01", str(saved(golden, [marker(100, "dissolve", 20)])))
    t = track(golden)
    assert t["cuts"] == []
    assert [s["range"]["start"] for s in t["slots"]] == [0, 110]
    (dissolve,) = t["transitions"]
    assert dissolve["type"] == "dissolve" and dissolve["range"] == {
        "start": 100,
        "duration": 20,
    }
    assert (dissolve["from_slot"], dissolve["to_slot"]) == ("slot-1", "slot-2")


def test_whip_with_a_cut_inside_adds_no_extra_boundary(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    run(monkeypatch, "v01", str(saved(golden, [marker(100, "whip", 10), marker(104)])))
    assert [s["range"]["start"] for s in track(golden)["slots"]] == [0, 104]


def test_overlapping_transitions_share_one_boundary(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    markers = [marker(100, "fade_black", 20), marker(110, "zoom", 20)]
    run(monkeypatch, "v01", str(saved(golden, markers)))
    # One group, frames 100-130, split at its middle.
    assert [s["range"]["start"] for s in track(golden)["slots"]] == [0, 115]


def test_fades_at_the_ends_add_no_boundary(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    markers = [marker(0, "fade_black", 15), marker(DURATION - 10, "fade_white", 10)]
    run(monkeypatch, "v01", str(saved(golden, markers)))
    t = track(golden)
    assert len(t["slots"]) == 1 and len(t["transitions"]) == 2
    # The fade out runs to the last frame; its to_slot is clamped onto the video.
    assert t["transitions"][1]["to_slot"] == "slot-1"


def test_other_keeps_its_detail(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(
        monkeypatch,
        "v01",
        str(saved(golden, [marker(100, "other: spin", 5), marker(200, "Other", 5)])),
    )
    first, second = track(golden)["transitions"]
    assert first["type"] == "other" and first["type_detail"] == "spin"
    assert second["type_detail"] == "unspecified"


@pytest.mark.parametrize(
    ("markers", "extra", "message"),
    [
        ([marker(0)], {}, "frame 0"),
        ([marker(DURATION)], {}, "outside the video"),
        ([marker(10), marker(10)], {}, "duplicate cut frames: [10]"),
        ([], {}, "no markers"),
        ([marker(10)], {"frames": DURATION + 1}, "labeler saw 301 frames"),
        ([marker(10)], {"video_id": "v02"}, "is for v02"),
        ([marker(10, "Fade")], {}, "unknown marker name 'Fade'"),
        ([marker(DURATION - 5, "fade_black", 10)], {}, "past the last frame (299)"),
    ],
)
def test_bad_markers_are_rejected(
    golden: Path, monkeypatch: pytest.MonkeyPatch, markers, extra, message
) -> None:
    before = (golden / "labels" / "v01.json").read_text()
    with pytest.raises(SystemExit, match=re.escape(message)):
        run(monkeypatch, "v01", str(saved(golden, markers, **extra)))
    assert (golden / "labels" / "v01.json").read_text() == before


def test_names_are_normalized(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    markers = [
        marker(50, "Fade Black", 10),
        marker(100, "fade-white", 10),
        marker(200, "Marker 3"),
    ]
    run(monkeypatch, "v01", str(saved(golden, markers)))
    t = track(golden)
    assert [x["type"] for x in t["transitions"]] == ["fade_black", "fade_white"]
    assert [c["frame"] for c in t["cuts"]] == [200]


def test_missing_manifest_entry_writes_nothing(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (golden / "manifest.json").write_text(json.dumps({"videos": []}))
    before = (golden / "labels" / "v01.json").read_text()
    with pytest.raises(SystemExit, match="v01 isn't in"):
        run(monkeypatch, "v01", str(saved(golden, [marker(10)])))
    assert (golden / "labels" / "v01.json").read_text() == before


@pytest.mark.parametrize(
    ("broken", "message"),
    [("missing", "not found; run ingest.py"), ("corrupt", "isn't valid JSON")],
)
def test_unreadable_label_file(
    golden: Path, monkeypatch: pytest.MonkeyPatch, broken: str, message: str
) -> None:
    label = golden / "labels" / "v01.json"
    label.unlink() if broken == "missing" else label.write_text("{not json")
    with pytest.raises(SystemExit, match=re.escape(message)):
        run(monkeypatch, "v01", str(saved(golden, [marker(10)])))


def test_rerunning_gives_the_same_result(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = saved(
        golden, [marker(50, "flash"), marker(51), marker(100, "dissolve?", 20)]
    )
    run(monkeypatch, "v01", str(path))
    first = (
        (golden / "labels" / "v01.json").read_text(),
        (golden / "manifest.json").read_text(),
    )
    run(monkeypatch, "v01", str(path))
    assert (
        (golden / "labels" / "v01.json").read_text(),
        (golden / "manifest.json").read_text(),
    ) == first


def test_touching_transitions_are_two_shot_changes(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # Ranges are half-open: 100-120 and 120-140 touch but don't overlap, so each gets its own boundary.
    markers = [marker(100, "dissolve", 20), marker(120, "dissolve", 20)]
    run(monkeypatch, "v01", str(saved(golden, markers)))
    assert [s["range"]["start"] for s in track(golden)["slots"]] == [0, 110, 130]


def test_cut_on_a_transitions_edges(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A cut on the first frame is inside the transition (no extra boundary). The range ends before frame 120,
    # so a cut there is outside it and the transition still gets its own middle boundary.
    run(monkeypatch, "v01", str(saved(golden, [marker(100, "zoom", 20), marker(100)])))
    assert [s["range"]["start"] for s in track(golden)["slots"]] == [0, 100]
    run(monkeypatch, "v01", str(saved(golden, [marker(100, "zoom", 20), marker(120)])))
    assert [s["range"]["start"] for s in track(golden)["slots"]] == [0, 110, 120]


EDL = """TITLE: Timeline 1
FCM: NON-DROP FRAME

001  001      V     C        01:00:03:10 01:00:03:11 01:00:03:10 01:00:03:11
 |C:ResolveColorBlue |M:Marker 1 |D:1

002  001      V     C        01:00:05:00 01:00:05:01 01:00:05:00 01:00:05:01
 |C:ResolveColorBlue |M:dissolve? |D:12
"""


def test_resolve_edl(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    path = golden / "markers.edl"
    path.write_text(EDL)
    run(monkeypatch, "v01", str(path))
    t = track(golden)
    assert [c["frame"] for c in t["cuts"]] == [100]  # 3 s 10 frames at 30 fps
    assert t["transitions"][0]["range"] == {"start": 150, "duration": 12}
    assert entry(golden)["ambiguous"] == [150]


def test_edl_with_another_start_timecode(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = golden / "markers.edl"
    path.write_text(EDL.replace("01:00:0", "00:00:0"))
    run(monkeypatch, "--start", "00:00:00:00", "v01", str(path))
    assert [c["frame"] for c in track(golden)["cuts"]] == [100]


def test_edl_at_25_fps(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    label = golden / "labels" / "v01.json"
    data = json.loads(label.read_text())
    data["source"]["fps"] = {"num": 25, "den": 1}
    label.write_text(json.dumps(data))
    path = golden / "markers.edl"
    path.write_text(EDL)
    run(monkeypatch, "v01", str(path))
    t = track(golden)
    assert [c["frame"] for c in t["cuts"]] == [85]  # 3 s 10 frames at 25 fps
    assert t["transitions"][0]["range"]["start"] == 125


@pytest.mark.parametrize(
    ("edl", "message"),
    [
        (
            EDL.replace(" |C:ResolveColorBlue |M:Marker 1 |D:1\n", ""),
            "EDL line 4: event has no marker details",
        ),
        (
            EDL.replace("|D:12", "|D:twelve"),
            "EDL line 8: can't read the marker details",
        ),
        (EDL.rsplit("\n", 2)[0] + "\n", "EDL line 7: event has no marker details"),
        (
            "TITLE: x\n |C:Blue |M:cut |D:1\n",
            "EDL line 2: marker details without an event line",
        ),
    ],
)
def test_malformed_edl_is_rejected(
    golden: Path, monkeypatch: pytest.MonkeyPatch, edl: str, message: str
) -> None:
    path = golden / "markers.edl"
    path.write_text(edl)
    with pytest.raises(SystemExit, match=re.escape(message)):
        run(monkeypatch, "v01", str(path))


def test_timecode_to_frames() -> None:
    assert m.timecode_to_frames("01:00:00:00", 30) == 108000
    assert m.timecode_to_frames("00:00:01:05", 25) == 30
