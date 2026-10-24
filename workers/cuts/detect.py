"""Cut detection core for the cut worker (#7): video in, cuts and slots out, as decided in ADR 0003.

PySceneDetect's AdaptiveDetector compares each frame's content change with the average change around it, so a cut
stands out even in footage that moves a lot. Every detected cut is kept; suspect ones are flagged for the user later
(#7's flagging step), never deleted here.

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
PARAMS: dict[str, Any] = {
    "detector": "pyscenedetect.AdaptiveDetector",
    "adaptive_threshold": ADAPTIVE_THRESHOLD,
    "min_scene_len": MIN_SCENE_LEN,
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
    #7's flagging step adds other signals.
    """
    if math.isnan(score) or score <= 0:
        return 0.0
    return min(1.0, max(0.0, 1 - ADAPTIVE_THRESHOLD / (2 * score)))


def to_partial(detection: Detection) -> dict:
    """One video track with the cuts and the slots between them, for the worker base to stamp and validate.

    Slots tile the video: a boundary at every cut. A slot is only as certain as its least certain boundary cut; a
    video with no cuts is one slot, as certain as can be.
    """
    cuts = sorted(detection.cuts, key=lambda c: c.frame)
    conf = {c.frame: round(confidence(c.score), 4) for c in cuts}
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
