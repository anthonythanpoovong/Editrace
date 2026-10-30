"""Turns hand-placed word markers into a golden-set captions label (LABELING.md). Input is `vNN.words.json` saved by
word_labeler.html: a flat, time-ordered list of words, each with a frame, a duration, its text, an optional "break"
("line" or "block", marking that this word starts a new caption line or a new caption block) and whether it's
ambiguous.

Blocks and lines are derived from the words: the first word starts the first block and its first line. A later word
with break "block" starts a new block (and a new first line in it); break "line" starts a new line in the current
block; no break continues the current line. A block's `range` spans its first word's start to its last word's end.

Usage: python3.11 words_to_label.py VIDEO_ID WORDS.json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LANGUAGE_PATTERN = re.compile(r"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$")
MANUAL = {"confidence": 1, "provenance": {"detector": "manual", "version": "1"}}


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        sys.exit(f"{path} not found; run ingest.py for this video first")
    except json.JSONDecodeError as e:
        sys.exit(f"{path} isn't valid JSON: {e}")


def build_captions(words: list[dict], language: str | None) -> list[dict]:
    """Group sorted, non-overlapping words into caption blocks and lines, per the module docstring."""
    blocks: list[dict] = []
    for word in words:
        brk = word.get("break")
        if not blocks or brk == "block":
            blocks.append({"lines": [[]]})
        elif brk == "line":
            blocks[-1]["lines"].append([])
        blocks[-1]["lines"][-1].append(word)

    captions = []
    for i, block in enumerate(blocks):
        block_words = [w for line in block["lines"] for w in line]
        start = block_words[0]["frame"]
        end = max(w["frame"] + w["duration"] for w in block_words)
        caption = {
            "id": f"caption-{i + 1}",
            "range": {"start": start, "duration": end - start},
            "lines": [
                {
                    "words": [
                        {
                            "text": w["text"],
                            "range": {"start": w["frame"], "duration": w["duration"]},
                        }
                        for w in line
                    ]
                }
                for line in block["lines"]
            ],
            **MANUAL,
        }
        if language:
            caption["language"] = language
        captions.append(caption)
    return captions


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: words_to_label.py VIDEO_ID WORDS.json")
    video_id, words_path = sys.argv[1], Path(sys.argv[2])

    label_path = ROOT / "labels" / f"{video_id}.json"
    label = read_json(label_path)
    manifest_path = ROOT / "manifest.json"
    manifest = read_json(manifest_path)
    entry = next((v for v in manifest["videos"] if v["id"] == video_id), None)
    if entry is None:
        sys.exit(f"{video_id} isn't in {manifest_path}; run ingest.py for it first")
    duration = label["source"]["duration"]

    saved = read_json(words_path)
    if saved.get("video_id") != video_id:
        sys.exit(f"{words_path} is for {saved.get('video_id')}, not {video_id}")
    if saved.get("frames") != duration:
        sys.exit(
            f"labeler saw {saved.get('frames')} frames but the label says {duration}; was the right file and fps used?"
        )
    words = saved.get("words") or []
    if not words:
        sys.exit(f"no words found in {words_path}")
    language = saved.get("language")
    if language and not LANGUAGE_PATTERN.fullmatch(language):
        sys.exit(f"'{language}' isn't a valid BCP 47 language tag (e.g. 'en', 'pt-BR')")

    words = sorted(words, key=lambda w: w["frame"])
    prev_end = 0
    for w in words:
        if not w.get("text", "").strip():
            sys.exit(f"word at frame {w['frame']} has empty text")
        if w["duration"] < 1:
            sys.exit(f"word '{w['text']}' at frame {w['frame']} has duration < 1")
        if not 0 <= w["frame"] < duration or w["frame"] + w["duration"] > duration:
            sys.exit(
                f"word '{w['text']}' at frame {w['frame']} is outside the video (0–{duration - 1})"
            )
        if w["frame"] < prev_end:
            sys.exit(
                f"word '{w['text']}' at frame {w['frame']} overlaps the previous word ending at frame {prev_end - 1}"
            )
        if w.get("break") not in (None, "line", "block"):
            sys.exit(f"word '{w['text']}' has an unknown break '{w['break']}'")
        prev_end = w["frame"] + w["duration"]

    captions = build_captions(words, language)
    tracks = label["tracks"]
    existing = next((t for t in tracks if t.get("kind") == "captions"), None)
    if existing is not None:
        existing["captions"] = captions
    else:
        tracks.append({"id": "captions-1", "kind": "captions", "captions": captions})
    label_path.write_text(json.dumps(label, indent=2) + "\n")

    ambiguous_words = sorted({w["frame"] for w in words if w.get("ambiguous")})
    entry["captions_labeled"] = True
    entry["notes"] = [n for n in entry.get("notes", []) if not n.startswith("captions:")]
    if ambiguous_words:
        entry["notes"].append(f"captions: {len(ambiguous_words)} ambiguous word(s) at frames {ambiguous_words}")
    # ambiguous is a union, not a replace: cuts labeling (markers_to_label.py) may already have ambiguous frames
    # recorded for this video, and overwriting the list here would erase that session's record.
    entry["ambiguous"] = sorted(set(entry.get("ambiguous") or []) | set(ambiguous_words))
    # Captions time gets its own field rather than adding into the shared `labeling_minutes`: that field is cuts'
    # cumulative total (markers_to_label.py overwrites it from the resumable labeler session), and adding into it
    # here would double-count every time this script re-runs on the same words.json.
    minutes = saved.get("labeling_minutes")
    if minutes is not None:
        entry["captions_labeling_minutes"] = minutes
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    n_blocks = len(captions)
    n_lines = sum(len(c["lines"]) for c in captions)
    print(
        f"{video_id}: {len(words)} words, {n_blocks} caption block(s), {n_lines} line(s), {len(ambiguous_words)} ambiguous"
    )


if __name__ == "__main__":
    main()
