"""Brings raw golden-set videos into eval/golden: one constant-frame-rate file per video, a manifest entry and a label skeleton.

- A video that is already constant frame rate is remuxed losslessly (stream copy), so labels and detectors see the exact
  frames of the upload. A variable-frame-rate video is conformed to its nominal rate with ffmpeg and marked `vfr`
  (ADR 0002); the conform is lossy and recorded in the label's `source`.
- Outputs are `videos/vNN.mp4` (never committed), a `manifest.json` entry and `labels/vNN.json`, a schema template with
  `source` filled in and empty `cuts` and `transitions` for the labeler (LABELING.md).
- Re-running skips any original whose sha256 is already in the manifest, so ids stay stable.
- Ids come from the file name: `v13.mp4` is ingested as v13, so labelers can split numbers between them. Any other
  name gets one more than the highest id in the manifest (and in this run). An id that's already taken, or an original
  that already sits where its output would go, stops the run before anything is written.

Usage: python3.11 ingest.py [--ffmpeg-dir DIR] ORIGINAL.mp4 [...]
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import re
import shutil
import subprocess
import sys
from fractions import Fraction
from math import gcd
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "manifest.json"
SCHEMA_VERSION = (ROOT.parent.parent / "schema" / "VERSION").read_text().strip()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def probe(ffprobe: str, path: Path) -> dict:
    out = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate,nb_frames",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    stream = json.loads(out)["streams"][0]
    pts = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "packet=pts_time",
            "-of",
            "csv=p=0",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    times = sorted(float(t) for t in pts if t)
    deltas = {round(b - a, 4) for a, b in itertools.pairwise(times)}
    fps = Fraction(stream["r_frame_rate"])
    return {
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "fps": fps,
        "frames": len(times),
        # Constant frame rate when every frame is one frame period after the previous one.
        "cfr": deltas <= {round(float(1 / fps), 4)},
    }


def manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"videos": []}


VIDEO_ID = re.compile(r"v\d{2,}")


def plan_ids(
    originals: list[Path], hashes: list[str], videos: list[dict]
) -> list[str | None]:
    """The id each original gets, or None for one that's already ingested. Checked for the whole run up front, so a bad
    name never leaves a half-written manifest."""
    taken = {v["id"] for v in videos}
    known = {v["original_sha256"] for v in videos}
    named = [o.stem for o in originals if VIDEO_ID.fullmatch(o.stem)]
    numbers = [int(i[1:]) for i in taken | set(named) if VIDEO_ID.fullmatch(i)]
    highest = max(numbers, default=0)
    ids: list[str | None] = []
    for original, digest in zip(originals, hashes, strict=True):
        if digest in known:
            ids.append(None)
            continue
        if VIDEO_ID.fullmatch(original.stem):
            vid = original.stem
        else:
            highest += 1
            vid = f"v{highest:02d}"
        if vid in taken:
            sys.exit(
                f"{original.name}: {vid} is already in the manifest; rename the file to a free id"
            )
        if (ROOT / "videos" / f"{vid}.mp4").resolve() == original.resolve():
            sys.exit(
                f"{original} is where {vid}'s output goes; move it out of videos/ first (e.g. into videos/originals/)"
            )
        taken.add(vid)
        known.add(digest)
        ids.append(vid)
    return ids


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--ffmpeg-dir",
        help="directory holding ffmpeg and ffprobe, if they aren't on PATH",
    )
    parser.add_argument("originals", nargs="+", type=Path)
    args = parser.parse_args()

    def tool(name: str) -> str:
        # which() with path= checks the file exists and is executable, and adds .exe on Windows.
        found = shutil.which(name, path=args.ffmpeg_dir)
        if not found:
            where = f"in {args.ffmpeg_dir}" if args.ffmpeg_dir else "on PATH"
            sys.exit(f"{name} not found {where}; install ffmpeg or pass --ffmpeg-dir")
        return found

    ffmpeg, ffprobe = tool("ffmpeg"), tool("ffprobe")
    data = manifest()
    hashes = [sha256(o) for o in args.originals]
    ids = plan_ids(args.originals, hashes, data["videos"])
    (ROOT / "videos").mkdir(exist_ok=True)
    (ROOT / "labels").mkdir(exist_ok=True)

    for original, original_hash, vid in zip(args.originals, hashes, ids, strict=True):
        if vid is None:
            print(f"skip {original.name}: already ingested")
            continue
        out = ROOT / "videos" / f"{vid}.mp4"
        info = probe(ffprobe, original)
        if info["cfr"]:
            cmd = [
                ffmpeg,
                "-v",
                "error",
                "-y",
                "-i",
                str(original),
                "-map",
                "0",
                "-c",
                "copy",
                "-movflags",
                "+faststart",
                str(out),
            ]
        else:
            rate = f"{info['fps'].numerator}/{info['fps'].denominator}"
            cmd = [
                ffmpeg,
                "-v",
                "error",
                "-y",
                "-i",
                str(original),
                "-fps_mode",
                "cfr",
                "-r",
                rate,
                "-c:v",
                "libx264",
                "-crf",
                "16",
                "-preset",
                "slow",
                "-c:a",
                "copy",
                str(out),
            ]
        subprocess.run(cmd, check=True)
        conformed = probe(ffprobe, out)
        content_hash = f"sha256:{sha256(out)}"
        w, h = conformed["width"], conformed["height"]
        fps = {"num": conformed["fps"].numerator, "den": conformed["fps"].denominator}

        source: dict = {
            "duration": conformed["frames"],
            "fps": fps,
            "resolution": {"width": w, "height": h},
            "aspect_ratio": {"num": w // gcd(w, h), "den": h // gcd(w, h)},
            "content_hash": content_hash,
        }
        if not info["cfr"]:
            version = subprocess.run(
                [ffmpeg, "-version"], check=True, capture_output=True, text=True
            ).stdout.split()[2]
            source |= {
                "vfr": True,
                "original_fps": fps,
                "conform": {"detector": "ffmpeg", "version": version},
            }
        label = {
            "schema_version": SCHEMA_VERSION,
            "source": source,
            "tracks": [
                {
                    "id": "video-1",
                    "kind": "video",
                    "slots": [],
                    "cuts": [],
                    "transitions": [],
                }
            ],
        }
        (ROOT / "labels" / f"{vid}.json").write_text(json.dumps(label, indent=2) + "\n")

        data["videos"].append(
            {
                "id": vid,
                "content_hash": content_hash,
                "original_sha256": original_hash,
                "fps": fps,
                "frames": conformed["frames"],
                "resolution": {"width": w, "height": h},
                "vfr": not info["cfr"],
                "rights": "",
                "edit_styles": [],
                "music": None,
                "labeled": False,
                "labeling_minutes": None,
                "notes": [],
                "ambiguous": [],
                "exclude": [],
            }
        )
        print(
            f"{original.name} -> {vid}.mp4 ({'remuxed, CFR' if info['cfr'] else 'conformed from VFR'}, {conformed['frames']} frames)"
        )

    MANIFEST.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
