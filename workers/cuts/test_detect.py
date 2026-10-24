"""The cut detection core, on synthetic videos with cuts at known frames, so it runs without the private golden set."""

from __future__ import annotations

import math
from pathlib import Path

import pytest

from editrace_schema import Template
from workers.cuts.detect import (
    ADAPTIVE_THRESHOLD,
    FLAG_MAX_GAP,
    FLAGGED_MAX,
    REVIEW_BELOW,
    Cut,
    Detection,
    confidence,
    cut_confidence,
    find_cuts,
    flagged,
    to_partial,
)

cv2 = pytest.importorskip("cv2")
np = pytest.importorskip("numpy")
pytest.importorskip("scenedetect")

COLORS = [(40, 40, 200), (200, 60, 40), (40, 180, 60), (220, 220, 40), (150, 40, 160)]


def make_video(
    path: Path, frames: int, cuts: list[int], size: tuple[int, int] = (96, 64)
) -> Path:
    """Solid-color shots with a little moving texture, changing color at each cut frame."""
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 30, size)
    rng = np.random.default_rng(7)
    shot = 0
    for i in range(frames):
        if i in cuts:
            shot += 1
        frame = np.full((size[1], size[0], 3), COLORS[shot % len(COLORS)], np.uint8)
        noise = rng.integers(0, 6, frame.shape, dtype=np.uint8)
        writer.write(cv2.add(frame, noise))
    writer.release()
    return path


def validate(partial: dict, frames: int) -> None:
    """Stamp provenance as the worker base does, wrap in a template, and check it against the schema models."""
    for track in partial["tracks"]:
        for element in track["slots"] + track["cuts"]:
            element["provenance"] = {"detector": "cuts", "version": "0.1.0"}
    Template.model_validate(
        {
            "schema_version": "0.1.0",
            "source": {
                "duration": frames,
                "fps": {"num": 30, "den": 1},
                "resolution": {"width": 96, "height": 64},
                "aspect_ratio": {"num": 3, "den": 2},
                "content_hash": "sha256:" + "0" * 64,
            },
            **partial,
        }
    )


def test_cuts_land_on_the_first_frame_of_each_new_shot(tmp_path: Path) -> None:
    video = make_video(tmp_path / "three_cuts.mp4", 100, [20, 45, 70])
    detection = find_cuts(video)
    assert detection.frames == 100
    assert [c.frame for c in detection.cuts] == [20, 45, 70]


def test_partial_has_slots_tiling_the_video_and_validates(tmp_path: Path) -> None:
    video = make_video(tmp_path / "three_cuts.mp4", 100, [20, 45, 70])
    partial = to_partial(find_cuts(video))
    (track,) = partial["tracks"]
    assert [s["range"] for s in track["slots"]] == [
        {"start": 0, "duration": 20},
        {"start": 20, "duration": 25},
        {"start": 45, "duration": 25},
        {"start": 70, "duration": 30},
    ]
    assert [c["id"] for c in track["cuts"]] == ["cut-1", "cut-2", "cut-3"]
    assert all(0 <= e["confidence"] <= 1 for e in track["slots"] + track["cuts"])
    validate(partial, 100)


def test_a_video_without_cuts_is_one_certain_slot(tmp_path: Path) -> None:
    video = make_video(tmp_path / "one_shot.mp4", 60, [])
    partial = to_partial(find_cuts(video))
    (track,) = partial["tracks"]
    assert track["cuts"] == []
    assert track["slots"] == [
        {"id": "slot-1", "range": {"start": 0, "duration": 60}, "confidence": 1.0}
    ]
    validate(partial, 60)


def test_a_slot_is_as_certain_as_its_weakest_boundary() -> None:
    weak, strong = ADAPTIVE_THRESHOLD, 5 * ADAPTIVE_THRESHOLD
    partial = to_partial(
        Detection([Cut(40, strong), Cut(10, weak)], 60)
    )  # out of order on purpose
    slots = partial["tracks"][0]["slots"]
    assert [s["confidence"] for s in slots] == [0.5, 0.5, 0.9]
    assert [c["frame"] for c in partial["tracks"][0]["cuts"]] == [10, 40]


@pytest.mark.parametrize(
    ("score", "expected"),
    [
        (ADAPTIVE_THRESHOLD, 0.5),
        (2 * ADAPTIVE_THRESHOLD, 0.75),
        (5 * ADAPTIVE_THRESHOLD, 0.9),
        (math.inf, 1.0),
        (math.nan, 0.0),
        (0.0, 0.0),
    ],
)
def test_confidence(score: float, expected: float) -> None:
    assert confidence(score) == pytest.approx(expected)


@pytest.mark.parametrize(
    ("frames", "expected"),
    [
        (
            [100, 100 + FLAG_MAX_GAP],
            {100, 100 + FLAG_MAX_GAP},
        ),  # right at the gap: a burst
        ([100, 101 + FLAG_MAX_GAP], set()),  # one frame further: two separate cuts
        ([10, 12, 17, 60], {10, 12, 17}),  # a burst of three, then a lone cut
        ([30], set()),
        ([], set()),
        (
            [371, 381, 391, 403, 413],
            set(),
        ),  # v03's real montage, 10-12 frames apart: not flagged
    ],
)
def test_flagged_bursts(frames: list[int], expected: set[int]) -> None:
    assert flagged([Cut(f, 3 * ADAPTIVE_THRESHOLD) for f in frames]) == expected


def test_flagged_cuts_and_their_sliver_sit_below_the_review_line() -> None:
    lone, a, b = Cut(30, 10.0), Cut(100, 10.0), Cut(105, 10.0)
    track = to_partial(Detection([lone, a, b], 200))["tracks"][0]
    conf = {c["frame"]: c["confidence"] for c in track["cuts"]}
    assert conf[30] >= REVIEW_BELOW
    assert conf[100] < REVIEW_BELOW and conf[105] < REVIEW_BELOW
    assert max(conf[100], conf[105]) <= FLAGGED_MAX
    slots = {s["range"]["start"]: s["confidence"] for s in track["slots"]}
    assert slots[100] < REVIEW_BELOW  # the 5-frame sliver between the two flagged cuts
    assert slots[0] >= REVIEW_BELOW


def test_unflagged_cuts_never_fall_below_the_line() -> None:
    weak = Cut(50, math.nan)  # a missing ratio maps to strength 0
    assert cut_confidence(weak, is_flagged=False) == REVIEW_BELOW
    assert cut_confidence(Cut(50, math.inf), is_flagged=True) == FLAGGED_MAX
