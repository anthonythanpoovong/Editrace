"""words_to_label.py turns hand-placed word markers into the committed golden captions label, so a bug here corrupts
the answer key the captions worker (#12) is scored against."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest
import words_to_label as m

DURATION = 300


@pytest.fixture
def golden(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A throwaway eval/golden with one 300-frame, 30 fps video, v01, already cut-labeled."""
    (tmp_path / "labels").mkdir()
    label = {
        "schema_version": "0.1.0",
        "source": {"duration": DURATION, "fps": {"num": 30, "den": 1}},
        "tracks": [
            {"id": "video-1", "kind": "video", "slots": [], "cuts": [], "transitions": []}
        ],
    }
    (tmp_path / "labels" / "v01.json").write_text(json.dumps(label))
    entry = {
        "id": "v01",
        "labeled": True,
        "labeling_minutes": 4,
        "notes": ["kept"],
        "ambiguous": [9],
    }
    (tmp_path / "manifest.json").write_text(json.dumps({"videos": [entry]}))
    monkeypatch.setattr(m, "ROOT", tmp_path)
    return tmp_path


def run(monkeypatch: pytest.MonkeyPatch, *args: str) -> None:
    monkeypatch.setattr(sys, "argv", ["words_to_label.py", *args])
    m.main()


def saved(golden: Path, words: list[dict], **extra) -> Path:
    path = golden / "v01.words.json"
    path.write_text(
        json.dumps({"video_id": "v01", "frames": DURATION, "words": words, **extra})
    )
    return path


def word(frame: int, text: str = "hi", duration: int = 5, brk: str | None = None, ambiguous: bool = False) -> dict:
    return {"frame": frame, "duration": duration, "text": text, "break": brk, "ambiguous": ambiguous}


def captions_track(golden: Path) -> dict:
    tracks = json.loads((golden / "labels" / "v01.json").read_text())["tracks"]
    return next(t for t in tracks if t["kind"] == "captions")


def entry(golden: Path) -> dict:
    return json.loads((golden / "manifest.json").read_text())["videos"][0]


def test_words_become_one_block_one_line(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(monkeypatch, "v01", str(saved(golden, [word(10, "hey"), word(20, "there", 8)])))
    (caption,) = captions_track(golden)["captions"]
    assert caption["id"] == "caption-1"
    assert caption["range"] == {"start": 10, "duration": 18}
    assert caption["confidence"] == 1 and caption["provenance"]["detector"] == "manual"
    (line,) = caption["lines"]
    assert [w["text"] for w in line["words"]] == ["hey", "there"]
    assert line["words"][1]["range"] == {"start": 20, "duration": 8}


def test_block_break_starts_a_new_caption(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    words = [word(10, "hey"), word(100, "world", brk="block")]
    run(monkeypatch, "v01", str(saved(golden, words)))
    captions = captions_track(golden)["captions"]
    assert [c["id"] for c in captions] == ["caption-1", "caption-2"]
    assert captions[1]["range"] == {"start": 100, "duration": 5}


def test_line_break_stays_in_the_same_block(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    words = [word(10, "hey"), word(20, "world", brk="line")]
    run(monkeypatch, "v01", str(saved(golden, words)))
    (caption,) = captions_track(golden)["captions"]
    assert len(caption["lines"]) == 2
    assert [w["text"] for w in caption["lines"][1]["words"]] == ["world"]


def test_language_is_written_per_caption_when_given(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(monkeypatch, "v01", str(saved(golden, [word(10)], language="en")))
    (caption,) = captions_track(golden)["captions"]
    assert caption["language"] == "en"


def test_no_language_field_when_not_given(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(monkeypatch, "v01", str(saved(golden, [word(10)])))
    (caption,) = captions_track(golden)["captions"]
    assert "language" not in caption


def test_ambiguous_words_are_merged_not_overwritten(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # v01's manifest already has ambiguous frame 9 from cut-labeling; this run must not erase it.
    run(monkeypatch, "v01", str(saved(golden, [word(50, ambiguous=True)])))
    e = entry(golden)
    assert e["ambiguous"] == [9, 50]
    assert any(n.startswith("captions: 1 ambiguous") for n in e["notes"])
    assert "kept" in e["notes"]


def test_captions_minutes_get_their_own_field(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # v01 already has 4 minutes recorded from cut-labeling; captions time must not be folded into that total.
    run(monkeypatch, "v01", str(saved(golden, [word(10)], labeling_minutes=10)))
    e = entry(golden)
    assert e["labeling_minutes"] == 4
    assert e["captions_labeling_minutes"] == 10


def test_rerunning_with_the_same_minutes_does_not_double_count(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = saved(golden, [word(10)], labeling_minutes=10)
    run(monkeypatch, "v01", str(path))
    run(monkeypatch, "v01", str(path))
    assert entry(golden)["captions_labeling_minutes"] == 10


def test_captions_labeled_flag_is_set(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(monkeypatch, "v01", str(saved(golden, [word(10)])))
    assert entry(golden)["captions_labeled"] is True


def test_rerunning_gives_the_same_result(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    path = saved(golden, [word(10, "hey", ambiguous=True), word(100, "world", brk="block")])
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


def test_rerun_replaces_the_existing_captions_track(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(monkeypatch, "v01", str(saved(golden, [word(10, "old")])))
    run(monkeypatch, "v01", str(saved(golden, [word(20, "new")])))
    label = json.loads((golden / "labels" / "v01.json").read_text())
    tracks = [t for t in label["tracks"] if t["kind"] == "captions"]
    assert len(tracks) == 1
    assert tracks[0]["captions"][0]["lines"][0]["words"][0]["text"] == "new"


@pytest.mark.parametrize(
    ("words", "extra", "message"),
    [
        ([word(DURATION)], {}, "outside the video"),
        ([word(10, duration=400)], {}, "outside the video"),
        ([word(10, duration=0)], {}, "duration < 1"),
        ([word(10, text="  ")], {}, "has empty text"),
        ([word(10, duration=20), word(20)], {}, "overlaps the previous word ending at frame 29"),
        ([word(10, brk="paragraph")], {}, "unknown break 'paragraph'"),
        ([word(10)], {"frames": DURATION + 1}, "labeler saw 301 frames"),
        ([word(10)], {"video_id": "v02"}, "is for v02"),
        ([word(10)], {"language": "not-a-tag!"}, "isn't a valid BCP 47 language tag"),
    ],
)
def test_bad_words_are_rejected(
    golden: Path, monkeypatch: pytest.MonkeyPatch, words, extra, message
) -> None:
    before = (golden / "labels" / "v01.json").read_text()
    with pytest.raises(SystemExit, match=re.escape(message)):
        run(monkeypatch, "v01", str(saved(golden, words, **extra)))
    assert (golden / "labels" / "v01.json").read_text() == before


def test_no_speech_gives_an_empty_captions_track(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    run(monkeypatch, "v01", str(saved(golden, [], labeling_minutes=1)))
    assert captions_track(golden)["captions"] == []
    assert entry(golden)["captions_labeled"] is True
    assert entry(golden)["captions_labeling_minutes"] == 1


def test_words_list_is_required(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    path = golden / "v01.words.json"
    path.write_text(json.dumps({"video_id": "v01", "frames": DURATION}))
    with pytest.raises(SystemExit, match="has no 'words' list"):
        run(monkeypatch, "v01", str(path))


def test_missing_manifest_entry_writes_nothing(golden: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    (golden / "manifest.json").write_text(json.dumps({"videos": []}))
    before = (golden / "labels" / "v01.json").read_text()
    with pytest.raises(SystemExit, match="v01 isn't in"):
        run(monkeypatch, "v01", str(saved(golden, [word(10)])))
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
        run(monkeypatch, "v01", str(saved(golden, [word(10)])))


def test_build_captions_orders_lines_within_a_block() -> None:
    words = [
        {"frame": 0, "duration": 5, "text": "a", "break": None},
        {"frame": 10, "duration": 5, "text": "b", "break": "line"},
        {"frame": 20, "duration": 5, "text": "c", "break": "block"},
    ]
    captions = m.build_captions(words, "en")
    assert len(captions) == 2
    assert [l["words"][0]["text"] for l in captions[0]["lines"]] == ["a", "b"]
    assert captions[1]["range"] == {"start": 20, "duration": 5}
