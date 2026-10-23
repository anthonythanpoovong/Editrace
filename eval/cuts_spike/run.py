"""Spike #4: run PySceneDetect and TransNetV2 on the golden videos and score them against the hand labels.

Throwaway spike code, not merged. Usage (Python 3.10+, with scenedetect, opencv-python and transnetv2-pytorch):

    python eval/cuts_spike/run.py detect   # caches predictions in eval/cuts_spike/predictions/
    python eval/cuts_spike/run.py score    # precision/recall tables from the cache

A predicted cut is the first frame of the new shot, like the labels. Matching is one-to-one within a frame
tolerance. Frames inside a `platform end card: frames a-b` note (LABELING.md rule 12) are excluded from scoring.
"""

from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "golden"
OUT = Path(__file__).resolve().parent / "predictions"

CONTENT_THRESHOLDS = [12, 15, 18, 21, 24, 27, 30, 35, 40, 50]
ADAPTIVE_THRESHOLDS = [1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0]
TRANSNET_THRESHOLDS = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
MIN_SCENE_LENS = [1, 2]
TOLERANCES = [1, 2]
END_CARD = re.compile(r"platform end card: frames (\d+)-(\d+)")


def video_path(video_id: str) -> Path | None:
    """The conformed vNN.mp4, else an unverified copy in videos/originals/ (same frames, different file hash)."""
    for path in (
        ROOT / "videos" / f"{video_id}.mp4",
        ROOT / "videos" / "originals" / f"{video_id}.mov",
    ):
        if path.exists():
            return path
    return None


def videos(cached: bool = False) -> list[dict]:
    """Manifest entries with a video on disk, or with cached predictions (scoring needs no video)."""
    manifest = json.loads((ROOT / "manifest.json").read_text())
    if cached:
        return [v for v in manifest["videos"] if (OUT / f"{v['id']}.json").exists()]
    return [v for v in manifest["videos"] if video_path(v["id"])]


def excluded_ranges(video: dict) -> list[tuple[int, int]]:
    return [(int(a), int(b)) for n in video["notes"] for a, b in END_CARD.findall(n)]


def outside(frames: list[int], ranges: list[tuple[int, int]]) -> list[int]:
    return [f for f in frames if not any(a <= f <= b for a, b in ranges)]


def label_cuts(video_id: str) -> list[int]:
    label = json.loads((ROOT / "labels" / f"{video_id}.json").read_text())
    return sorted(c["frame"] for track in label["tracks"] for c in track["cuts"])


# --- detection -------------------------------------------------------------------------------------------


def run_pyscenedetect(path: Path) -> dict:
    from scenedetect import AdaptiveDetector, ContentDetector, detect

    runs = {}
    for msl in MIN_SCENE_LENS:
        for t in CONTENT_THRESHOLDS:
            start = time.perf_counter()
            scenes = detect(str(path), ContentDetector(threshold=t, min_scene_len=msl))
            runs[f"content t={t} msl={msl}"] = {
                "cuts": [s[0].frame_num for s in scenes[1:]],
                "seconds": time.perf_counter() - start,
            }
        for t in ADAPTIVE_THRESHOLDS:
            start = time.perf_counter()
            scenes = detect(
                str(path), AdaptiveDetector(adaptive_threshold=t, min_scene_len=msl)
            )
            runs[f"adaptive t={t} msl={msl}"] = {
                "cuts": [s[0].frame_num for s in scenes[1:]],
                "seconds": time.perf_counter() - start,
            }
    return runs


def decode_small(path: Path):
    """All frames as RGB uint8 at TransNetV2's 48x27 input size."""
    import cv2
    import numpy as np

    cap = cv2.VideoCapture(str(path))
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        small = cv2.resize(frame, (48, 27), interpolation=cv2.INTER_AREA)
        frames.append(cv2.cvtColor(small, cv2.COLOR_BGR2RGB))
    cap.release()
    return np.stack(frames)


def run_transnet(path: Path, model) -> dict:
    import torch

    start = time.perf_counter()
    frames = decode_small(path)
    decoded = time.perf_counter()
    single, _ = model.predict_frames(
        torch.from_numpy(frames).to(model.device), quiet=True
    )
    inferred = time.perf_counter()
    return {
        "frames": len(frames),
        "probs": [round(float(p), 4) for p in single],
        "decode_seconds": decoded - start,
        "inference_seconds": inferred - decoded,
    }


def transnet_cuts(probs: list[float], threshold: float) -> list[int]:
    """First frame of each new shot: where the boundary probability drops back below the threshold."""
    cuts, inside = [], False
    for i, p in enumerate(probs):
        if p > threshold:
            inside = True
        elif inside:
            cuts.append(i)
            inside = False
    return cuts


def detect_all(only: list[str] | None) -> None:
    from transnetv2_pytorch import TransNetV2

    OUT.mkdir(exist_ok=True)
    model = TransNetV2(device="cpu")
    for video in videos():
        if only and video["id"] not in only:
            continue
        path = video_path(video["id"])
        print(f"{video['id']}: PySceneDetect...", flush=True)
        psd = run_pyscenedetect(path)
        print(f"{video['id']}: TransNetV2...", flush=True)
        tn = run_transnet(path, model)
        if tn["frames"] != video["frames"]:
            raise SystemExit(
                f"{video['id']}: decoded {tn['frames']} frames, manifest says {video['frames']}"
            )
        (OUT / f"{video['id']}.json").write_text(
            json.dumps(
                {"source": path.name, "pyscenedetect": psd, "transnetv2": tn}, indent=1
            )
        )


# --- scoring ---------------------------------------------------------------------------------------------


def match(
    pred: list[int], truth: list[int], tol: int
) -> tuple[int, list[int], list[int]]:
    """One-to-one matching, closest pairs first. Returns (true positives, unmatched preds, unmatched truth)."""
    pairs = sorted(
        (abs(p - t), i, j)
        for i, p in enumerate(pred)
        for j, t in enumerate(truth)
        if abs(p - t) <= tol
    )
    used_p, used_t = set(), set()
    for _, i, j in pairs:
        if i not in used_p and j not in used_t:
            used_p.add(i)
            used_t.add(j)
    return (
        len(used_p),
        [p for i, p in enumerate(pred) if i not in used_p],
        [t for j, t in enumerate(truth) if j not in used_t],
    )


def predictions(cache: dict) -> dict[str, list[int]]:
    runs = {f"pyscenedetect {k}": v["cuts"] for k, v in cache["pyscenedetect"].items()}
    for t in TRANSNET_THRESHOLDS:
        runs[f"transnetv2 t={t}"] = transnet_cuts(cache["transnetv2"]["probs"], t)
    return runs


def score_all(show_misses: str | None) -> None:
    per_run: dict[str, dict[int, list[int]]] = {}  # run -> tol -> [tp, fp, fn]
    misses: dict[str, list[str]] = {}
    vids = videos(cached=True)
    for video in vids:
        cache = json.loads((OUT / f"{video['id']}.json").read_text())
        ranges = excluded_ranges(video)
        truth = outside(label_cuts(video["id"]), ranges)
        for run, pred in predictions(cache).items():
            pred = outside(pred, ranges)
            for tol in TOLERANCES:
                tp, fps, fns = match(pred, truth, tol)
                totals = per_run.setdefault(run, {}).setdefault(tol, [0, 0, 0])
                totals[0] += tp
                totals[1] += len(fps)
                totals[2] += len(fns)
                if run == show_misses and tol == 2:
                    misses.setdefault(run, []).append(
                        f"{video['id']}: false {fps} missed {fns}"
                    )

    print(f"videos: {', '.join(v['id'] for v in vids)}  (end-card frames excluded)\n")
    print(
        f"{'run':<34} {'P@1':>6} {'R@1':>6} {'P@2':>6} {'R@2':>6} {'F1@2':>6} {'FP@2':>5} {'FN@2':>5}"
    )
    rows = []
    for run, by_tol in per_run.items():
        cells = []
        for tol in TOLERANCES:
            tp, fp, fn = by_tol[tol]
            p = tp / (tp + fp) if tp + fp else 0.0
            r = tp / (tp + fn) if tp + fn else 0.0
            cells.append((p, r, 2 * p * r / (p + r) if p + r else 0.0, fp, fn))
        rows.append((run, cells))
    for run, cells in sorted(rows, key=lambda x: -x[1][1][2]):
        (p1, r1, _, _, _), (p2, r2, f2, fp2, fn2) = cells
        flag = "  <- passes" if r2 >= 0.95 and p2 >= 0.90 else ""
        print(
            f"{run:<34} {p1:6.3f} {r1:6.3f} {p2:6.3f} {r2:6.3f} {f2:6.3f} {fp2:5d} {fn2:5d}{flag}"
        )
    for run, lines in misses.items():
        print(f"\n{run} at +/-2 frames:")
        print("\n".join(f"  {line}" for line in lines))


def combine(base: str = "pyscenedetect adaptive t=2.0 msl=1") -> None:
    """Can TransNetV2 help Adaptive? Cuts it recovers, its confidence on Adaptive's cuts, and gated scores."""
    recovered, peaks = 0, {"false": [], "real": []}
    gated: dict[float, list[int]] = {g: [0, 0, 0] for g in (0.02, 0.05, 0.1, 0.2, 0.3)}
    for video in videos(cached=True):
        cache = json.loads((OUT / f"{video['id']}.json").read_text())
        probs = cache["transnetv2"]["probs"]
        ranges = excluded_ranges(video)
        truth = outside(label_cuts(video["id"]), ranges)
        pred = outside(predictions(cache)[base], ranges)
        _, false, missed = match(pred, truth, 2)
        _, _, tn_missed = match(outside(transnet_cuts(probs, 0.5), ranges), truth, 2)
        recovered += len(set(missed) - set(tn_missed))
        # TransNetV2 peaks on the last frame of the old shot, one before our cut frame.
        peak = {f: max(probs[max(0, f - 3) : f + 2]) for f in pred}
        for f in pred:
            peaks["false" if f in false else "real"].append(
                f"{video['id']}:{f}={peak[f]:.2f}"
            )
        for gate, totals in gated.items():
            tp, fps, fns = match([f for f in pred if peak[f] >= gate], truth, 2)
            totals[0] += tp
            totals[1] += len(fps)
            totals[2] += len(fns)
    print(f"base: {base}")
    print(f"cuts it misses that TransNetV2 t=0.5 finds: {recovered}")
    for kind, values in peaks.items():
        print(f"TransNetV2 peak on its {kind} cuts: {' '.join(sorted(values))}")
    for gate, (tp, fp, fn) in gated.items():
        print(
            f"keep if TransNetV2 >= {gate}: P {tp / (tp + fp):.3f} R {tp / (tp + fn):.3f}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["detect", "score", "combine"])
    parser.add_argument(
        "--misses", help="list false/missed cuts per video for this run name"
    )
    parser.add_argument("--only", nargs="+", help="detect: only these video ids")
    args = parser.parse_args()
    if args.command == "detect":
        detect_all(args.only)
    elif args.command == "score":
        score_all(args.misses)
    else:
        combine()


if __name__ == "__main__":
    main()
