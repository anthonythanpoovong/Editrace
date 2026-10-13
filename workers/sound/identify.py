"""Identify the sound used in a reference video and build its sound_ref."""

import subprocess
from pathlib import Path

DETECTOR = {"detector": "sound-id", "version": "0.1.0"}


def extract_audio(video_path: Path, out_dir: Path) -> Path:
    audio_path = out_dir / f"{video_path.stem}.m4a"
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(video_path), "-vn", "-acodec", "copy", str(audio_path)],
        check=True,
        capture_output=True,
    )
    return audio_path


def identify_sound(video_path: Path, template_id: str, storage, fingerprint, out_dir: Path) -> dict | None:
    audio_path = extract_audio(video_path, out_dir)

    # Keep the track so we can re-run matching when the fingerprint provider improves.
    with audio_path.open("rb") as f:
        storage.from_("sounds").upload(f"{template_id}/{audio_path.name}", f)

    match = fingerprint(audio_path)
    if match is None:
        return None
    return {
        "id": match.id,
        "title": match.title,
        "artist": match.artist,
        "link": match.link,
        "confidence": match.score,
        "provenance": DETECTOR,
    }
