"""Recall-tuning experiment for the cut worker (#7): can AdaptiveDetector's settings close the recall gap?

Decodes each labeled golden video once with the worker's settings and caches every frame's `content_val`. It then
replays AdaptiveDetector's rule (scenedetect 0.7.2) offline, which is checked to reproduce the worker's cuts exactly,
so a settings sweep costs no decoding. Reports:
- a sweep of the threshold, window and `min_content_val`, an absolute content threshold OR'ed in, and a variant
  that compares a frame with the quieter side of its window
- leave-one-video-out: settings chosen on the other videos (best recall at precision >= 0.85), scored on the one left
  out, which shows whether a gain carries to videos it wasn't fitted on

Results and conclusions are in README.md. Scoring uses the golden set's own scorer (Â±2 frames, `exclude` ranges).

Usage: python eval/cuts_tuning/run.py [--golden eval/golden] [--cache DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import itertools
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from workers.cuts.detect import ADAPTIVE_THRESHOLD, MIN_SCENE_LEN, find_cuts

LOVO_MIN_PRECISION = 0.85


def load_scorer(golden: Path):
    spec = importlib.util.spec_from_file_location("golden_score", golden / "score.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = (
        module  # dataclasses look their module up while it's being defined
    )
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def content_vals(video: Path, cache: Path) -> dict:
    """Per-frame content_val and the worker's own cuts, cached by the video's content hash."""
    digest = sha256(video)
    path = cache / f"{video.stem}.json"
    if path.exists() and (cached := json.loads(path.read_text()))["sha256"] == digest:
        return cached
    from scenedetect import AdaptiveDetector, SceneManager, StatsManager, open_video

    stream = open_video(str(video))
    stats = StatsManager()
    manager = SceneManager(stats_manager=stats)
    manager.add_detector(
        AdaptiveDetector(
            adaptive_threshold=ADAPTIVE_THRESHOLD, min_scene_len=MIN_SCENE_LEN
        )
    )
    manager.detect_scenes(stream)
    frames = [
        f for f in range(stream.frame_number) if stats.metrics_exist(f, ["content_val"])
    ]
    data = {
        "sha256": digest,
        "frames": frames,
        "cv": [stats.get_metrics(f, ["content_val"])[0] for f in frames],
        "cuts": [c.frame for c in find_cuts(video).cuts],
    }
    path.write_text(json.dumps(data))
    return data


def adaptive(
    frames: list[int],
    cv: list[float],
    t: float = ADAPTIVE_THRESHOLD,
    w: int = 2,
    m: float = 15.0,
    abs_t: float | None = None,
    quieter_side: bool = False,
) -> list[int]:
    """AdaptiveDetector's rule with min_scene_len 1: a frame is a cut when its content_val is at least `t` times the
    mean of the `w` frames on each side, and at least `m`. Variants: `abs_t` also accepts any frame with content_val
    at least `abs_t`; `quieter_side` divides by the lower of the two sides' means instead of both together."""
    out = []
    for i in range(w, len(cv) - w):
        left, right = cv[i - w : i], cv[i + 1 : i + w + 1]
        base = (
            min(sum(left), sum(right)) / w
            if quieter_side
            else (sum(left) + sum(right)) / (2.0 * w)
        )
        if abs(base) < 1e-5:
            ratio = 255.0 if cv[i] >= m else 0.0
        else:
            ratio = min(cv[i] / base, 255.0)
        if (ratio >= t and cv[i] >= m) or (abs_t is not None and cv[i] >= abs_t):
            out.append(frames[i])
    return out


def configs() -> dict[str, dict]:
    out: dict[str, dict] = {}
    for t, w, m in itertools.product(
        [1.5, 1.6, 1.7, 1.8, 1.9, 2.0, 2.2], [1, 2, 3, 4], [10.0, 15.0, 20.0]
    ):
        out[f"t={t} w={w} m={m:g}"] = {"t": t, "w": w, "m": m}
    for a in [40, 50, 60, 70, 80]:
        out[f"t=2.0 w=2, or content >= {a}"] = {"abs_t": a}
    for t, w in itertools.product([2.0, 2.5, 3.0, 3.5, 4.0], [2, 3]):
        out[f"quieter side t={t} w={w}"] = {"t": t, "w": w, "quieter_side": True}
    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Recall-tuning experiment for the cut worker (#7)"
    )
    parser.add_argument("--golden", type=Path, default=ROOT / "eval" / "golden")
    parser.add_argument(
        "--cache",
        type=Path,
        default=Path(tempfile.gettempdir()) / "editrace-cuts-tuning",
    )
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    score = load_scorer(args.golden)

    manifest = json.loads((args.golden / "manifest.json").read_text())["videos"]
    data, skipped = {}, []
    for v in manifest:
        video = args.golden / "videos" / f"{v['id']}.mp4"
        if v.get("labeled") is not True or not video.exists():
            skipped.append(v["id"])
            continue
        d = content_vals(video, args.cache)
        replay = adaptive(d["frames"], d["cv"])
        assert replay == d["cuts"], (
            f"{v['id']}: replay differs from the worker: {sorted(set(replay) ^ set(d['cuts']))}"
        )
        d["label"] = json.loads(
            (args.golden / "labels" / f"{v['id']}.json").read_text()
        )
        d["exclude"] = v.get("exclude", [])
        data[v["id"]] = d
    print(
        f"{len(data)} videos ({', '.join(data)}); skipped, unlabeled or not on this machine: {', '.join(skipped)}"
    )
    print("replay reproduces the worker's cuts on every video\n")

    def per_video(cfg: dict) -> dict:
        return {
            vid: score.score_cuts(
                {
                    "tracks": [
                        {
                            "cuts": [
                                {"frame": f}
                                for f in adaptive(d["frames"], d["cv"], **cfg)
                            ]
                        }
                    ]
                },
                d["label"],
                d["exclude"],
                score.DEFAULT_TOLERANCE,
            )
            for vid, d in data.items()
        }

    def total(counts):
        t = score.Counts()
        for c in counts:
            t.add(c)
        return t

    def row(name: str, t) -> str:
        return f"{name:34} P {t.precision:.3f}  R {t.recall:.3f}  TP {t.true_positives:4}  FP {t.false_positives:4}  FN {t.false_negatives:4}"

    results = {name: per_video(cfg) for name, cfg in configs().items()}
    baseline = per_video({})
    print(row("baseline (the worker)", total(baseline.values())))
    print("\nsweep, best recall first:")
    ranked = sorted(
        results.items(),
        key=lambda kv: (
            -total(kv[1].values()).recall,
            -total(kv[1].values()).precision,
        ),
    )
    for name, counts in ranked[:25]:
        print(row(name, total(counts.values())))

    picks, held_out = {}, []
    for out in data:

        def fit(name: str, out: str = out) -> tuple[float, float]:
            t = total(c for vid, c in results[name].items() if vid != out)
            return (
                (t.recall, t.precision)
                if t.precision >= LOVO_MIN_PRECISION
                else (-1.0, -1.0)
            )

        picks[out] = max(results, key=fit)
        held_out.append(results[picks[out]][out])
    print(
        f"\nleave-one-video-out (best recall at precision >= {LOVO_MIN_PRECISION} on the rest):"
    )
    for vid, name in picks.items():
        print(f"  {vid}: {name}")
    print(row("held-out score", total(held_out)))
    print(row("baseline, same videos", total(baseline.values())))


if __name__ == "__main__":
    main()
