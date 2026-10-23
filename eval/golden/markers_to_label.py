"""Turns hand-placed markers into a golden-set label (LABELING.md). Two inputs are accepted:
- `vNN.markers.json` saved by labeler.html (the default workflow), or
- a DaVinci Resolve export (File → Export → Timeline Markers to EDL).

Marker names carry the label:
- empty, "Marker N" or "cut": a hard cut at the marker's frame.
- "flash": a cut, and the frame is listed in the video's manifest `notes`.
- a transition type ("dissolve", "fade_black", "fade_white", "wipe", "push", "slide", "zoom", "whip", "glitch", or
  "other: <detail>"): a transition covering the marker's duration.
- a "?" anywhere in the name: the label is kept, and its frame is listed in the manifest's `ambiguous`.
Names are case-insensitive and spaces or hyphens count as underscores ("Fade Black" is fade_black). Any other name,
a transition running past the last frame, or a malformed EDL row stops the run without writing anything.

Slots are derived from the labels: a slot boundary at every cut, and at the middle of any transition (or group of
overlapping transitions) with no cut inside, unless it touches the first or last frame (a fade in or out of the video).
The label's `source` (written by ingest.py) is kept; cuts, transitions and slots are replaced on every run.

Usage: python3.11 markers_to_label.py [--start 01:00:00:00] VIDEO_ID MARKERS.json|MARKERS.edl
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
    """Every event line must be followed by its marker details; anything else is a malformed export."""
    markers, frame, event_line = [], None, 0
    for n, line in enumerate(text.splitlines(), 1):
        if event := EVENT.match(line):
            if frame is not None:
                sys.exit(
                    f"EDL line {event_line}: event has no marker details (|C: |M: |D:)"
                )
            frame, event_line = timecode_to_frames(event.group(1), base) - start, n
        elif details := DETAILS.search(line):
            if frame is None:
                sys.exit(
                    f"EDL line {n}: marker details without an event line before them"
                )
            markers.append(
                (frame, details.group("name").strip(), int(details.group("duration")))
            )
            frame = None
        elif "|M:" in line:
            sys.exit(f"EDL line {n}: can't read the marker details: {line.strip()}")
    if frame is not None:
        sys.exit(f"EDL line {event_line}: event has no marker details (|C: |M: |D:)")
    return markers


def marker_kind(name: str) -> tuple[str, str]:
    """(kind, detail) from a marker name: lowercased, with spaces and hyphens as underscores ("Fade Black" ->
    "fade_black"). Unknown names stop the run instead of silently becoming cuts."""
    kind, _, detail = name.replace("?", "").strip().partition(":")
    kind = re.sub(r"[\s-]+", "_", kind.strip().lower())
    if kind in ("", "cut") or re.fullmatch(r"marker_\d+", kind):
        return "cut", ""
    if kind == "flash" or kind in TRANSITION_TYPES:
        return kind, detail
    sys.exit(
        f"unknown marker name '{name}': use cut, flash, a transition type ({', '.join(sorted(TRANSITION_TYPES))}) "
        "or 'other: <detail>'"
    )


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        sys.exit(f"{path} not found; run ingest.py for this video first")
    except json.JSONDecodeError as e:
        sys.exit(f"{path} isn't valid JSON: {e}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--start",
        default="01:00:00:00",
        help="EDL only: timeline start timecode in Resolve (default 01:00:00:00)",
    )
    parser.add_argument("video_id")
    parser.add_argument("markers", type=Path)
    args = parser.parse_args()

    # Read and check both files before writing either, so a bad run never leaves them out of step.
    label_path = ROOT / "labels" / f"{args.video_id}.json"
    label = read_json(label_path)
    manifest_path = ROOT / "manifest.json"
    manifest = read_json(manifest_path)
    entry = next((v for v in manifest["videos"] if v["id"] == args.video_id), None)
    if entry is None:
        sys.exit(
            f"{args.video_id} isn't in {manifest_path}; run ingest.py for it first"
        )
    fps = label["source"]["fps"]
    duration = label["source"]["duration"]
    labeling_minutes = None
    if args.markers.suffix == ".json":
        saved = json.loads(args.markers.read_text())
        if saved["video_id"] != args.video_id:
            sys.exit(f"{args.markers} is for {saved['video_id']}, not {args.video_id}")
        if saved["frames"] != duration:
            sys.exit(
                f"labeler saw {saved['frames']} frames but the label says {duration}; was the right file and fps used?"
            )
        markers = [(m["frame"], m["name"], m["duration"]) for m in saved["markers"]]
        labeling_minutes = saved.get("labeling_minutes")
    else:
        # Timecode counts whole frames at the rounded rate (non-drop frame), e.g. 30 for 30000/1001.
        base = round(fps["num"] / fps["den"])
        markers = parse_markers(
            args.markers.read_text(), base, timecode_to_frames(args.start, base)
        )
    if not markers:
        sys.exit(f"no markers found in {args.markers}")

    cuts: list[int] = []
    transitions: list[dict] = []
    notes: list[str] = []
    ambiguous: list[int] = []
    for frame, name, length in sorted(markers):
        if not 0 <= frame < duration:
            sys.exit(
                f"marker '{name}' at frame {frame} is outside the video (0–{duration - 1}); check --start (EDL) or the fps"
            )
        if "?" in name:
            ambiguous.append(frame)
        kind, detail = marker_kind(name)
        if kind in TRANSITION_TYPES:
            if frame + max(length, 1) > duration:
                sys.exit(
                    f"{kind} at frame {frame} runs {length} frames, past the last frame ({duration - 1})"
                )
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

    # Overlapping transitions (e.g. a zoom during a fade) are one shot change, so they share one boundary. A group
    # with a cut inside already has its boundary. A group touching the first or last frame is a fade in or out of
    # the video, not a change of shot, so it adds none.
    boundaries = set(cuts)
    groups: list[list[int]] = []
    for t in sorted(transitions, key=lambda t: t["range"]["start"]):
        start, end = t["range"]["start"], t["range"]["start"] + t["range"]["duration"]
        if groups and start < groups[-1][1]:
            groups[-1][1] = max(groups[-1][1], end)
        else:
            groups.append([start, end])
    for start, end in groups:
        if start > 0 and end < duration and not any(start <= c < end for c in cuts):
            boundaries.add((start + end) // 2)
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

    entry["labeled"] = True
    entry["notes"] = [n for n in entry["notes"] if not n.startswith("flash:")] + notes
    entry["ambiguous"] = ambiguous
    if labeling_minutes is not None:
        entry["labeling_minutes"] = labeling_minutes
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        f"{args.video_id}: {len(cuts)} cuts, {len(transitions)} transitions, {len(slots)} slots, {len(ambiguous)} ambiguous"
    )


if __name__ == "__main__":
    main()
