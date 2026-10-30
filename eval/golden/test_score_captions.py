"""score_captions.py is the ruler the captions worker's ±100ms bar (#12) is measured with, so its pairing and counting
are pinned here case by case."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
import score_captions as m

HASH = "sha256:" + "0" * 64
FPS30 = {"num": 30, "den": 1}  # one frame is 33.3 ms


def template(words: list[tuple[str, int, int]], **extra) -> dict:
    """One caption block holding `words` as (text, start frame, duration frames)."""
    block = {
        "id": "caption-1",
        "lines": [
            {
                "words": [
                    {"text": t, "range": {"start": s, "duration": d}}
                    for t, s, d in words
                ]
            }
        ],
    }
    return {
        "tracks": [
            {"id": "video-1", "kind": "video", "cuts": []},
            {
                "id": "captions-1",
                "kind": "captions",
                "captions": [block] if words else [],
            },
        ],
        **extra,
    }


def score(pred, truth, tolerance_ms: float = 100, exclude=None) -> m.WordCounts:
    return m.score_words(
        template(pred), template(truth), FPS30, exclude or [], tolerance_ms
    )


def test_words_within_the_tolerance_count_on_start_and_end() -> None:
    c = score(
        [("hello", 12, 10), ("world", 30, 10)], [("hello", 10, 10), ("world", 30, 10)]
    )
    # hello starts 2 frames (67 ms) late and ends 2 frames late: still inside 100 ms.
    assert (c.labeled, c.predicted, c.matched) == (2, 2, 2)
    assert (c.start_ok, c.end_ok, c.both_ok) == (2, 2, 2)


def test_start_and_end_are_judged_separately() -> None:
    # 4 frames (133 ms) early on the start, exact on the end.
    c = score([("hello", 6, 14)], [("hello", 10, 10)])
    assert (c.start_ok, c.end_ok, c.both_ok) == (0, 1, 0)


def test_the_tolerance_is_in_milliseconds_not_frames() -> None:
    # 3 frames is exactly 100 ms: inside; 4 frames (133 ms) is out.
    assert score([("a", 13, 5)], [("a", 10, 5)]).start_ok == 1
    assert score([("a", 14, 5)], [("a", 10, 5)]).start_ok == 0
    assert score([("a", 14, 5)], [("a", 10, 5)], tolerance_ms=140).start_ok == 1


def test_the_tolerance_follows_the_video_frame_rate() -> None:
    # At 24 fps a frame is 41.7 ms, so 3 frames is 125 ms: outside 100 ms.
    c = m.score_words(
        template([("a", 13, 5)]),
        template([("a", 10, 5)]),
        {"num": 24, "den": 1},
        [],
        100,
    )
    assert c.start_ok == 0


def test_case_and_punctuation_do_not_stop_words_pairing() -> None:
    c = score(
        [("Winners,", 10, 5), ("quit.", 20, 5)], [("winners", 10, 5), ("quit", 20, 5)]
    )
    assert c.matched == 2


def test_non_english_letters_are_kept_when_pairing() -> None:
    c = score([("olá", 10, 5), ("você", 20, 5)], [("OLÁ", 10, 5), ("você", 20, 5)])
    assert c.matched == 2


def test_a_missed_word_does_not_shift_the_pairing_of_its_neighbours() -> None:
    c = score(
        [("one", 10, 5), ("three", 30, 5)],
        [("one", 10, 5), ("two", 20, 5), ("three", 30, 5)],
    )
    assert (c.labeled, c.matched, c.extra, c.both_ok) == (3, 2, 0, 2)
    assert c.found == pytest.approx(2 / 3)


def test_an_invented_word_is_an_extra_and_is_not_timed() -> None:
    c = score(
        [("one", 10, 5), ("uh", 18, 2), ("two", 20, 5)],
        [("one", 10, 5), ("two", 20, 5)],
    )
    assert (c.matched, c.extra, c.both_ok) == (2, 1, 2)


def test_words_in_an_excluded_range_are_dropped_on_both_sides() -> None:
    exclude = [{"start": 90, "duration": 10, "reason": "platform end card"}]
    c = score(
        [("hi", 10, 5), ("card", 92, 5)],
        [("hi", 10, 5), ("music", 95, 5)],
        exclude=exclude,
    )
    assert (c.labeled, c.predicted, c.matched) == (1, 1, 1)


def test_median_error_covers_every_paired_start_and_end() -> None:
    # Start errors 0 and 3 frames, end errors 0 and 0 frames -> [0, 100, 0, 0] ms -> median 0.
    c = score([("a", 10, 5), ("b", 33, 5)], [("a", 10, 5), ("b", 30, 8)])
    assert c.median_error_ms == pytest.approx(0)
    c = score([("a", 13, 2)], [("a", 10, 5)])  # start 100 ms off, end 0 ms off
    assert c.median_error_ms == pytest.approx(50)


def test_a_video_with_no_speech_scores_no_words_and_flags_any_extras() -> None:
    quiet = score([], [])
    assert (quiet.labeled, quiet.found, quiet.both_rate, quiet.extra) == (
        0,
        0.0,
        0.0,
        0,
    )
    assert score([("ghost", 10, 5)], []).extra == 1


def test_a_prediction_with_no_tracks_scores_as_no_words() -> None:
    # The worker returns {} for a video with no speech.
    c = m.score_words({}, template([("hi", 10, 5)]), FPS30, [], 100)
    assert (c.labeled, c.predicted, c.matched) == (1, 0, 0)


@pytest.fixture
def golden(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    (tmp_path / "labels").mkdir()
    (tmp_path / "labels" / "v01.json").write_text(
        json.dumps(
            template([("hi", 10, 5), ("there", 20, 5)], source={"content_hash": HASH})
        )
    )
    (tmp_path / "labels" / "v02.json").write_text(
        json.dumps(template([], source={"content_hash": HASH}))
    )
    (tmp_path / "labels" / "v03.json").write_text(
        json.dumps(template([], source={"content_hash": HASH}))
    )
    videos = [
        {"id": "v01", "fps": FPS30, "captions_labeled": True},
        {"id": "v02", "fps": FPS30, "captions_labeled": True},
        # Ingested but its captions aren't labeled yet.
        {"id": "v03", "fps": FPS30, "labeled": True},
    ]
    (tmp_path / "manifest.json").write_text(json.dumps({"videos": videos}))
    monkeypatch.setattr(m, "ROOT", tmp_path)
    preds = tmp_path / "preds"
    preds.mkdir()
    return preds


def run(monkeypatch: pytest.MonkeyPatch, *args: str) -> None:
    monkeypatch.setattr(sys, "argv", ["score_captions.py", *args])
    m.main()


def test_cli_totals_missing_and_unlabeled_videos(
    golden: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # A partial template from the worker has no `source`; that is accepted.
    (golden / "v01.json").write_text(
        json.dumps(template([("hi", 12, 5), ("there", 40, 5)]))
    )
    run(monkeypatch, str(golden), "--json")
    out = json.loads(capsys.readouterr().out)
    assert out["missing"] == ["v02"] and out["unlabeled"] == ["v03"]
    assert out["total"]["labeled"] == 2 and out["total"]["both_ok"] == 1
    assert out["tolerance_ms"] == m.DEFAULT_TOLERANCE_MS

    run(monkeypatch, str(golden), "--tolerance-ms", "50")
    text = capsys.readouterr().out
    assert "±50 ms" in text and "no prediction: v02" in text


def test_cli_refuses_a_prediction_from_another_video(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    other = "sha256:" + "1" * 64
    (golden / "v01.json").write_text(
        json.dumps(template([("hi", 10, 5)], source={"content_hash": other}))
    )
    with pytest.raises(SystemExit, match="different video"):
        run(monkeypatch, str(golden))


def test_cli_with_no_predictions_stops(
    golden: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    with pytest.raises(SystemExit, match="no predictions"):
        run(monkeypatch, str(golden))
