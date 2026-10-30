"""Scores predicted caption word timing against the golden labels (#12, #52): how many labeled words the worker found,
and for those, how many start and end within a tolerance of the label (the captions worker's ±100ms bar).

- Words are paired by aligning the two spoken-order word lists on their text (case and punctuation ignored), so a
  word the worker missed or invented never shifts the pairing of the words around it. Only paired words are timed;
  a labeled word with no pair counts against recall, a predicted word with no pair is an extra.
- Frames inside a video's `exclude` ranges in the manifest are left out on both sides, as in `score.py`.
- A video is scored only if its captions are hand-labeled (`captions_labeled` in the manifest) and a prediction for
  it exists. A video with no speech scores zero labeled words; any word predicted for it is an extra.
- A prediction that carries a `source` must have been made from the labeled video (content_hash). The worker's
  partial output has no `source` and is accepted as it is.

Usage: python3.11 eval/golden/score_captions.py PREDICTIONS_DIR [--tolerance-ms 100] [--json]
PREDICTIONS_DIR holds one template per video, named like the labels (`v01.json`, ...).
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import statistics
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

from score import excluded

ROOT = Path(__file__).resolve().parent
DEFAULT_TOLERANCE_MS = 100


@dataclass
class Word:
    text: str
    start: int  # frames
    end: int  # frames, exclusive


@dataclass
class WordCounts:
    labeled: int = 0
    predicted: int = 0
    matched: int = 0
    start_ok: int = 0
    end_ok: int = 0
    both_ok: int = 0
    abs_errors_ms: list[float] = field(
        default_factory=list
    )  # every paired start and end error, for the median

    def add(self, other: WordCounts) -> None:
        self.labeled += other.labeled
        self.predicted += other.predicted
        self.matched += other.matched
        self.start_ok += other.start_ok
        self.end_ok += other.end_ok
        self.both_ok += other.both_ok
        self.abs_errors_ms += other.abs_errors_ms

    @property
    def extra(self) -> int:
        return self.predicted - self.matched

    @property
    def found(self) -> float:
        return self.matched / self.labeled if self.labeled else 0.0

    @property
    def start_rate(self) -> float:
        return self.start_ok / self.matched if self.matched else 0.0

    @property
    def end_rate(self) -> float:
        return self.end_ok / self.matched if self.matched else 0.0

    @property
    def both_rate(self) -> float:
        return self.both_ok / self.matched if self.matched else 0.0

    @property
    def median_error_ms(self) -> float:
        return statistics.median(self.abs_errors_ms) if self.abs_errors_ms else 0.0


def normalize(text: str) -> str:
    return re.sub(r"[^\w']", "", text.lower())


def caption_words(template: dict, exclude: list[dict]) -> list[Word]:
    words = [
        Word(
            w["text"], w["range"]["start"], w["range"]["start"] + w["range"]["duration"]
        )
        for track in template.get("tracks", [])
        if track.get("kind") == "captions"
        for caption in track.get("captions", [])
        for line in caption["lines"]
        for w in line["words"]
    ]
    return sorted(
        (w for w in words if not excluded(w.start, exclude)), key=lambda w: w.start
    )


def pair_words(predicted: list[Word], labeled: list[Word]) -> list[tuple[Word, Word]]:
    aligner = difflib.SequenceMatcher(
        None,
        [normalize(w.text) for w in labeled],
        [normalize(w.text) for w in predicted],
        autojunk=False,
    )
    return [
        (predicted[b + k], labeled[a + k])
        for a, b, size in aligner.get_matching_blocks()
        for k in range(size)
    ]


def score_words(
    predicted: dict, labeled: dict, fps: dict, exclude: list[dict], tolerance_ms: float
) -> WordCounts:
    pred = caption_words(predicted, exclude)
    truth = caption_words(labeled, exclude)
    ms_per_frame = 1000 * fps["den"] / fps["num"]
    counts = WordCounts(labeled=len(truth), predicted=len(pred))
    for p, t in pair_words(pred, truth):
        start_ms, end_ms = (
            abs(p.start - t.start) * ms_per_frame,
            abs(p.end - t.end) * ms_per_frame,
        )
        counts.matched += 1
        counts.start_ok += start_ms <= tolerance_ms
        counts.end_ok += end_ms <= tolerance_ms
        counts.both_ok += start_ms <= tolerance_ms and end_ms <= tolerance_ms
        counts.abs_errors_ms += [start_ms, end_ms]
    return counts


def score_dir(
    predictions: Path, tolerance_ms: float
) -> tuple[dict[str, WordCounts], list[str], list[str]]:
    """Per-video word counts for every captions-labeled video with a prediction, the labeled ids with no prediction,
    and the ids whose captions aren't labeled yet (never scored, whether or not a prediction exists)."""
    manifest = json.loads((ROOT / "manifest.json").read_text())
    scored, missing, unlabeled = {}, [], []
    for video in manifest["videos"]:
        if video.get("captions_labeled") is not True:
            unlabeled.append(video["id"])
            continue
        pred_path = predictions / f"{video['id']}.json"
        if not pred_path.exists():
            missing.append(video["id"])
            continue
        predicted = json.loads(pred_path.read_text())
        labeled = json.loads((ROOT / "labels" / f"{video['id']}.json").read_text())
        source = predicted.get("source")
        if source and source["content_hash"] != labeled["source"]["content_hash"]:
            sys.exit(
                f"{pred_path} was made from a different video than labels/{video['id']}.json (content_hash)"
            )
        scored[video["id"]] = score_words(
            predicted, labeled, video["fps"], video.get("exclude", []), tolerance_ms
        )
    return scored, missing, unlabeled


def row(counts: WordCounts) -> dict:
    return {
        **{k: v for k, v in asdict(counts).items() if k != "abs_errors_ms"},
        "extra": counts.extra,
        "found": counts.found,
        "start_rate": counts.start_rate,
        "end_rate": counts.end_rate,
        "both_rate": counts.both_rate,
        "median_error_ms": counts.median_error_ms,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("predictions", type=Path)
    parser.add_argument(
        "--tolerance-ms",
        type=float,
        default=DEFAULT_TOLERANCE_MS,
        help="milliseconds (default 100)",
    )
    parser.add_argument(
        "--json", action="store_true", help="print machine-readable results"
    )
    args = parser.parse_args()

    scored, missing, unlabeled = score_dir(args.predictions, args.tolerance_ms)
    if not scored:
        sys.exit(f"no predictions for any labeled golden video in {args.predictions}")
    total = WordCounts()
    for counts in scored.values():
        total.add(counts)

    if args.json:
        print(
            json.dumps(
                {
                    "element": "caption_words",
                    "tolerance_ms": args.tolerance_ms,
                    "missing": missing,
                    "unlabeled": unlabeled,
                    "videos": {vid: row(c) for vid, c in scored.items()},
                    "total": row(total),
                },
                indent=2,
            )
        )
        return
    print(
        f"caption words · ±{args.tolerance_ms:g} ms · {len(scored)} videos"
        + (f" · no prediction: {', '.join(missing)}" if missing else "")
        + (f" · captions not labeled yet: {', '.join(unlabeled)}" if unlabeled else "")
    )
    print(
        f"{'video':<8}{'words':>6}{'found':>7}{'extra':>6}{'start':>7}{'end':>7}{'both':>7}{'med ms':>8}"
    )
    for vid, c in [*scored.items(), ("total", total)]:
        print(
            f"{vid:<8}{c.labeled:6d}{c.found:7.0%}{c.extra:6d}{c.start_rate:7.0%}{c.end_rate:7.0%}{c.both_rate:7.0%}{c.median_error_ms:8.0f}"
        )


if __name__ == "__main__":
    main()
