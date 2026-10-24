"""Regression test for the cut worker (#7) on the golden set (#52): the floor from ADR 0003.

The golden videos are private and never committed, so this runs only where all of them are present (in
`eval/golden/videos/`) and is skipped elsewhere, including CI. It scores with the golden set's own scorer, so the
numbers match `/golden-eval` and ADR 0003. #7 is signed off on #52's 10-video set; until then it covers the labeled
videos there are.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import pytest

from workers.cuts.detect import find_cuts, to_partial

pytest.importorskip("scenedetect")

GOLDEN = Path(__file__).resolve().parents[2] / "eval" / "golden"
RECALL_FLOOR = 0.95
PRECISION_FLOOR = 0.75
TOLERANCE = 2


def _scorer():
    spec = importlib.util.spec_from_file_location("golden_score", GOLDEN / "score.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = (
        module  # dataclasses look their module up while it's being defined
    )
    spec.loader.exec_module(module)
    return module


def _labeled_videos() -> list[str]:
    manifest = json.loads((GOLDEN / "manifest.json").read_text())
    return [v["id"] for v in manifest["videos"] if v.get("labeled") is True]


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return f"sha256:{h.hexdigest()}"


def test_cuts_meet_the_floor_on_the_golden_set(tmp_path: Path) -> None:
    labeled = _labeled_videos()
    absent = [vid for vid in labeled if not (GOLDEN / "videos" / f"{vid}.mp4").exists()]
    if absent:
        # Scoring a subset would report numbers nobody else can compare, so it's all labeled videos or nothing.
        pytest.skip(f"golden videos not on this machine: {', '.join(absent)}")

    for vid in labeled:
        video = GOLDEN / "videos" / f"{vid}.mp4"
        label = json.loads((GOLDEN / "labels" / f"{vid}.json").read_text())
        predicted = {
            "source": {**label["source"], "content_hash": _sha256(video)},
            **to_partial(find_cuts(video)),
        }
        (tmp_path / f"{vid}.json").write_text(json.dumps(predicted))

    score = _scorer()
    per_video, missing, _unlabeled = score.score_dir(tmp_path, TOLERANCE)
    assert missing == [] and sorted(per_video) == sorted(labeled)
    total = score.Counts()
    for counts in per_video.values():
        total.add(counts)

    report = (
        " · ".join(
            f"{vid} P {c.precision:.3f} R {c.recall:.3f}"
            for vid, c in per_video.items()
        )
        + f" · total P {total.precision:.3f} R {total.recall:.3f} (TP {total.true_positives}, FP {total.false_positives}, FN {total.false_negatives})"
    )
    print(f"\n{len(per_video)} videos · ±{TOLERANCE} frames · {report}")
    assert total.recall >= RECALL_FLOOR, f"recall below the floor: {report}"
    assert total.precision >= PRECISION_FLOOR, f"precision below the floor: {report}"
