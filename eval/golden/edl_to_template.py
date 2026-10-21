"""Turns a DaVinci Resolve marker export (File → Export → Timeline Markers to EDL) into a golden-set label (LABELING.md).

Marker names carry the label:
- empty, "Marker N" or "cut": a hard cut at the marker's frame.
- "flash": a cut, and the frame is listed in the video's manifest `notes`.
- a transition type ("dissolve", "fade_black", "fade_white", "wipe", "push", "slide", "zoom", "whip", "glitch", or
  "other: <detail>"): a transition covering the marker's duration.
- a "?" anywhere in the name: the label is kept, and its frame is listed in the manifest's `ambiguous`.

Slots are derived from the labels: a slot boundary at every cut, and at the middle of any transition with no cut inside.
The label's `source` (written by ingest.py) is kept; cuts, transitions and slots are replaced on every run.

Usage: python3.11 edl_to_template.py [--start 01:00:00:00] VIDEO_ID MARKERS.edl
"""

from __future__ import annotations

import argparse
import itertools
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TRANSITION_TYPES = {
    "dissolve",
    "fade_black",
    "fade_white",
    "wipe",
    "push",
    "slide",
    "zoom",
    "whip",
    "glitch",
    "other",
}
MANUAL = {"confidence": 1, "provenance": {"detector": "manual", "version": "1"}}
EVENT = re.compile(r"^\d+\s+\S+\s+\S+\s+\S+\s+(\d\d:\d\d:\d\d:\d\d)\s")
DETAILS = re.compile(r"\|C:(?P<color>\S*)\s*\|M:(?P<name>.*?)\s*\|D:(?P<duration>\d+)")


def timecode_to_frames(tc: str, base: int) -> int:
    h, m, s, f = (int(x) for x in tc.split(":"))
    return ((h * 60 + m) * 60 + s) * base + f


def parse_markers(text: str, base: int, start: int) -> list[tuple[int, str, int]]:
    markers, frame = [], None
    for line in text.splitlines():
        if event := EVENT.match(line):
            frame = timecode_to_frames(event.group(1), base) - start
        elif (details := DETAILS.search(line)) and frame is not None:
            markers.append(
                (frame, details.group("name").strip(), int(details.group("duration")))
            )
            frame = None
    return markers


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--start",
        default="01:00:00:00",
        help="timeline start timecode in Resolve (default 01:00:00:00)",
    )
    parser.add_argument("video_id")
    parser.add_argument("edl", type=Path)
    args = parser.parse_args()

    label_path = ROOT / "labels" / f"{args.video_id}.json"
    label = json.loads(label_path.read_text())
    fps = label["source"]["fps"]
    duration = label["source"]["duration"]
    # Timecode counts whole frames at the rounded rate (non-drop frame), e.g. 30 for 30000/1001.
    base = round(fps["num"] / fps["den"])
    markers = parse_markers(
        args.edl.read_text(), base, timecode_to_frames(args.start, base)
    )
    if not markers:
        sys.exit(
            f"no markers found in {args.edl}; is it a Timeline Markers EDL, and is --start right?"
        )

    cuts: list[int] = []
    transitions: list[dict] = []
    notes: list[str] = []
    ambiguous: list[int] = []
    for frame, name, length in sorted(markers):
        if not 0 <= frame < duration:
            sys.exit(
                f"marker '{name}' at frame {frame} is outside the video (0–{duration - 1}); check --start"
            )
        if "?" in name:
            ambiguous.append(frame)
        kind, _, detail = name.replace("?", "").strip().partition(":")
        kind = kind.strip().lower()
        if kind in TRANSITION_TYPES:
            transition = {
                "type": kind,
                "range": {"start": frame, "duration": max(length, 1)},
            }
            if kind == "other":
                transition["type_detail"] = detail.strip() or "unspecified"
            transitions.append(transition)
            continue
        if frame == 0:
            sys.exit("a cut at frame 0 isn't a cut: the first shot starts there")
        if kind == "flash":
            notes.append(f"flash: cut at frame {frame}")
        cuts.append(frame)
    if len(set(cuts)) != len(cuts):
        sys.exit(
            f"duplicate cut frames: {sorted(f for f in set(cuts) if cuts.count(f) > 1)}"
        )

    boundaries = set(cuts)
    for t in transitions:
        start, end = t["range"]["start"], t["range"]["start"] + t["range"]["duration"]
        if not any(start <= c < end for c in cuts):
            boundaries.add(start + t["range"]["duration"] // 2)
    edges = [0, *sorted(b for b in boundaries if 0 < b < duration), duration]
    slots = [
        {"id": f"slot-{i + 1}", "range": {"start": a, "duration": b - a}, **MANUAL}
        for i, (a, b) in enumerate(itertools.pairwise(edges))
    ]

    def slot_at(frame: int) -> str:
        return next(
            s["id"]
            for s in slots
            if s["range"]["start"]
            <= frame
            < s["range"]["start"] + s["range"]["duration"]
        )

    track = label["tracks"][0]
    track["slots"] = slots
    track["cuts"] = [
        {"id": f"cut-{i + 1}", "frame": f, **MANUAL} for i, f in enumerate(sorted(cuts))
    ]
    track["transitions"] = [
        {
            "id": f"transition-{i + 1}",
            **t,
            "from_slot": slot_at(t["range"]["start"]),
            "to_slot": slot_at(
                min(t["range"]["start"] + t["range"]["duration"], duration - 1)
            ),
            **MANUAL,
        }
        for i, t in enumerate(transitions)
    ]
    label_path.write_text(json.dumps(label, indent=2) + "\n")

    manifest_path = ROOT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    entry = next(v for v in manifest["videos"] if v["id"] == args.video_id)
    entry["labeled"] = True
    entry["notes"] = [n for n in entry["notes"] if not n.startswith("flash:")] + notes
    entry["ambiguous"] = ambiguous
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        f"{args.video_id}: {len(cuts)} cuts, {len(transitions)} transitions, {len(slots)} slots, {len(ambiguous)} ambiguous"
    )


if __name__ == "__main__":
    main()
