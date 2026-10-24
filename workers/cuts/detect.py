"""Cut detection core for the cut worker (#7): video in, cuts and slots out, as decided in ADR 0003.

PySceneDetect's AdaptiveDetector compares each frame's content change with the average change around it, so a cut
stands out even in footage that moves a lot. Every detected cut is kept; suspect ones are flagged for the user to
review, never deleted here.

This module doesn't depend on the shared worker base (#53). The worker's `detect()` calls `find_cuts()` and
`to_partial()`; the base adds provenance, validates the result and stores it.
"""

from __future__ import annotations

import itertools
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# ADR 0003. Any change here changes the output, so the worker reports these as its params (its cache key).
ADAPTIVE_THRESHOLD = 2.0
MIN_SCENE_LEN = 1  # frames; PySceneDetect's default of 15 drops fast cuts
# Flagging (#7). PROVISIONAL: chosen on the first 5 golden videos, where detections this close together were almost
# always a real cut plus a stray duplicate. Re-measure on #52's next 5 videos without re-tuning first, and again at
# 30. Watch flash cuts: they are two real cuts 1-3 frames apart and would be flagged.
FLAG_MAX_GAP = 8  # frames between neighbouring cuts for them to count as one burst (about 0.27 s at 30 fps)
FLAG_MIN_CUTS = 2  # cuts in a burst before it is flagged
# The convention while the flag lives in `confidence` (no schema field yet): below this means "needs review".
# Unflagged cuts score 0.5 or more; flagged ones are scaled into 0-0.4, so the most suspect still sort lowest.
REVIEW_BELOW = 0.5
FLAGGED_MAX = 0.4
PARAMS: dict[str, Any] = {
    "detector": "pyscenedetect.AdaptiveDetector",
    "adaptive_threshold": ADAPTIVE_THRESHOLD,
    "min_scene_len": MIN_SCENE_LEN,
    "flag_max_gap": FLAG_MAX_GAP,
    "flag_min_cuts": FLAG_MIN_CUTS,
    "review_below": REVIEW_BELOW,
}


@dataclass(frozen=True)
class Cut:
    frame: int  # the first frame of the new shot, as `cuts[].frame` in the schema
    score: float  # PySceneDetect's adaptive ratio at that frame: how far it stands out from its neighbours


@dataclass(frozen=True)
class Detection:
    cuts: list[Cut]
    frames: int  # frames decoded, so slots can run to the end of the video


def find_cuts(video: Path) -> Detection:
    """Run AdaptiveDetector over every frame of `video`."""
    from scenedetect import AdaptiveDetector, SceneManager, StatsManager, open_video

    stream = open_video(str(video))
    detector = AdaptiveDetector(
        adaptive_threshold=ADAPTIVE_THRESHOLD, min_scene_len=MIN_SCENE_LEN
    )
    stats = StatsManager()
    manager = SceneManager(stats_manager=stats)
    manager.add_detector(detector)
    manager.detect_scenes(stream)
    ratio_key = next(
        k for k in detector.get_metrics() if k.startswith("adaptive_ratio")
    )

    scenes = manager.get_scene_list(start_in_scene=True)
    frames = scenes[-1][1].frame_num if scenes else stream.frame_number
    cuts = []
    for start, _ in scenes[1:]:
        (ratio,) = stats.get_metrics(start.frame_num, [ratio_key])
        cuts.append(
            Cut(start.frame_num, float(ratio) if ratio is not None else math.inf)
        )
    return Detection(cuts, frames)


def confidence(score: float) -> float:
    """Map an adaptive ratio to 0-1: 0.5 at the threshold, rising towards 1 as the cut stands out more (0.75 at twice
    the threshold, 0.9 at five times). It never saturates, because real cuts on the golden set score 3 to 92.

    It measures how strongly a cut stands out, not whether it's real: on the golden set, split-screen false cuts score
    up to 28 and a picture-in-picture one 87, while some real cuts score 3. So it can't be the flag on its own (ADR 0003);
    `flagged()` decides that, and `to_partial()` combines the two.
    """
    if math.isnan(score) or score <= 0:
        return 0.0
    return min(1.0, max(0.0, 1 - ADAPTIVE_THRESHOLD / (2 * score)))


def flagged(cuts: list[Cut]) -> set[int]:
    """Frames of cuts in a burst: at least FLAG_MIN_CUTS cuts, each within FLAG_MAX_GAP frames of the next.

    Real short-form edits cut fast too (montages 10 frames apart), so the gap is kept tight: on the golden set, wider
    rules mostly flagged fast real editing rather than mistakes.
    """
    frames = sorted(c.frame for c in cuts)
    out: set[int] = set()
    burst: list[int] = []
    for f in [*frames, None]:
        if burst and (f is None or f - burst[-1] > FLAG_MAX_GAP):
            if len(burst) >= FLAG_MIN_CUTS:
                out.update(burst)
            burst = []
        if f is not None:
            burst.append(f)
    return out


def cut_confidence(cut: Cut, is_flagged: bool) -> float:
    """Strength from `confidence()`, kept at REVIEW_BELOW or more when unflagged, scaled into 0-FLAGGED_MAX when
    flagged."""
    strength = confidence(cut.score)
    if is_flagged:
        return round(FLAGGED_MAX * strength, 4)
    return round(max(REVIEW_BELOW, strength), 4)


def to_partial(detection: Detection) -> dict:
    """One video track with the cuts and the slots between them, for the worker base to stamp and validate.

    Slots tile the video: a boundary at every cut. A slot is only as certain as its least certain boundary cut, so the
    sliver between two near-duplicate cuts is flagged too; a video with no cuts is one slot, as certain as can be.
    Confidence below REVIEW_BELOW means "needs review".
    """
    cuts = sorted(detection.cuts, key=lambda c: c.frame)
    suspect = flagged(cuts)
    conf = {c.frame: cut_confidence(c, c.frame in suspect) for c in cuts}
    edges = [0, *(c.frame for c in cuts), detection.frames]
    slots = []
    for i, (a, b) in enumerate(itertools.pairwise(edges)):
        bounds = [conf[f] for f in (a, b) if f in conf]
        slots.append(
            {
                "id": f"slot-{i + 1}",
                "range": {"start": a, "duration": b - a},
                "confidence": min(bounds, default=1.0),
            }
        )
    return {
        "tracks": [
            {
                "id": "video-1",
                "kind": "video",
                "slots": slots,
                "cuts": [
                    {
                        "id": f"cut-{i + 1}",
                        "frame": c.frame,
                        "confidence": conf[c.frame],
                    }
                    for i, c in enumerate(cuts)
                ],
            }
        ]
    }
