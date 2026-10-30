"""Whisper-based captions worker (#12): word-level transcription, grouped into caption lines and mapped onto the
template's `captions` track. Builds on the worker base (#53); see `workers/reference.py` for the base contract.

Audio is extracted to a temporary file and handed to Whisper; it is never persisted or returned (Key Decision). The
seam between this module and the model is `Transcriber.transcribe()`, so tests inject a fake and never load a real
model or run ffmpeg.
"""

import shutil
import subprocess
import tempfile
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ClassVar, Protocol

from workers.base import Compute, Job, Worker
from workers.cache import Partial


@dataclass(frozen=True)
class TranscribedWord:
    text: str
    start_s: float
    end_s: float
    probability: float  # 0 to 1, as faster-whisper reports it


@dataclass(frozen=True)
class Transcription:
    language: str  # BCP 47-ish code, e.g. "en" -- whisper's own detected or forced code
    words: Sequence[TranscribedWord]  # spoken order; empty for silence/no speech


class Transcriber(Protocol):
    def transcribe(self, video: Path, language: str | None) -> Transcription: ...


def _extract_audio(video: Path, audio: Path, ffmpeg_dir: str | None = None) -> None:
    """16kHz mono PCM, what Whisper expects. Raises RuntimeError (not retried: a bad video fails the same way twice)
    if ffmpeg is missing or the input can't be decoded."""
    ffmpeg = shutil.which("ffmpeg", path=ffmpeg_dir)
    if ffmpeg is None:
        where = f"in {ffmpeg_dir}" if ffmpeg_dir else "on PATH"
        raise RuntimeError(
            f"ffmpeg not found {where}; install ffmpeg to run the captions worker"
        )
    result = subprocess.run(
        [ffmpeg, "-y", "-i", str(video), "-vn", "-ac", "1", "-ar", "16000", str(audio)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed to extract audio: {result.stderr[-2000:]}")


class WhisperTranscriber:
    """The real transcriber: faster-whisper (CTranslate2), lazily loaded so constructing a worker never downloads a
    model. Optional dependency -- see pyproject.toml's `captions` extra."""

    def __init__(
        self,
        model_size: str = "small",
        device: str = "auto",
        compute_type: str = "default",
        vad_filter: bool = True,
        ffmpeg_dir: str | None = None,
    ) -> None:
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self.vad_filter = vad_filter
        self.ffmpeg_dir = ffmpeg_dir
        self._model: Any = None

    def _load(self) -> Any:
        if self._model is None:
            from faster_whisper import (  # heavy import: deferred past construction
                WhisperModel,
            )

            self._model = WhisperModel(
                self.model_size, device=self.device, compute_type=self.compute_type
            )
        return self._model

    def transcribe(self, video: Path, language: str | None) -> Transcription:
        with tempfile.TemporaryDirectory() as tmp:
            audio = Path(tmp) / "audio.wav"
            _extract_audio(video, audio, self.ffmpeg_dir)
            segments, info = self._load().transcribe(
                str(audio),
                language=language,
                word_timestamps=True,
                vad_filter=self.vad_filter,
            )
            words = [
                TranscribedWord(w.word.strip(), w.start, w.end, w.probability)
                for segment in segments
                for w in segment.words or []
                if w.word.strip()
            ]
        return Transcription(info.language, words)


def _group_into_lines(
    words: Sequence[TranscribedWord],
    max_words: int,
    max_chars: int,
    pause_s: float,
) -> list[list[TranscribedWord]]:
    """One line per caption block (the common short-form style): split on a silent pause, a word count cap, or a
    character-count cap, whichever comes first. A single word longer than `max_chars` still gets its own line rather
    than being dropped."""
    lines: list[list[TranscribedWord]] = []
    current: list[TranscribedWord] = []
    for word in words:
        if current:
            gap = word.start_s - current[-1].end_s
            projected_chars = (
                sum(len(w.text) for w in current) + len(current) + len(word.text)
            )
            if (
                gap > pause_s
                or len(current) >= max_words
                or projected_chars > max_chars
            ):
                lines.append(current)
                current = []
        current.append(word)
    if current:
        lines.append(current)
    return lines


def _to_frame(seconds: float, fps: Mapping[str, Any]) -> int:
    return max(0, round(seconds * fps["num"] / fps["den"]))


def _line_to_caption(
    caption_id: str,
    words: Sequence[TranscribedWord],
    language: str,
    fps: Mapping[str, Any],
) -> dict[str, Any]:
    word_entries = []
    for w in words:
        start = _to_frame(w.start_s, fps)
        end = max(start + 1, _to_frame(w.end_s, fps))
        word_entries.append(
            {"text": w.text, "range": {"start": start, "duration": end - start}}
        )
    block_start = word_entries[0]["range"]["start"]
    block_end = max(e["range"]["start"] + e["range"]["duration"] for e in word_entries)
    confidence = min(1.0, max(0.0, sum(w.probability for w in words) / len(words)))
    return {
        "id": caption_id,
        "range": {"start": block_start, "duration": max(1, block_end - block_start)},
        "language": language,
        "lines": [{"words": word_entries}],
        "confidence": confidence,
    }


class CaptionsWorker(Worker):
    name: ClassVar[str] = "captions"
    version: ClassVar[str] = "0.1.0"
    # Modal wrapper data only (#7); the base never imports Modal. T4 is the modest default for Whisper small/medium.
    compute: ClassVar[Compute] = Compute(gpu="T4", memory_mb=8192, timeout_s=900)

    def __init__(
        self,
        *args: Any,
        transcriber: Transcriber | None = None,
        model_size: str = "small",
        language: str | None = None,
        max_words_per_line: int = 6,
        max_chars_per_line: int = 24,
        pause_s: float = 0.6,
        vad_filter: bool = True,
        **kwargs: Any,
    ) -> None:
        super().__init__(*args, **kwargs)
        self.model_size = model_size
        self.language = language  # None: let Whisper detect it
        self.max_words_per_line = max_words_per_line
        self.max_chars_per_line = max_chars_per_line
        self.pause_s = pause_s
        self.vad_filter = vad_filter
        self.transcriber = transcriber or WhisperTranscriber(
            model_size=model_size, vad_filter=vad_filter
        )

    def params(self) -> Mapping[str, Any]:
        return {
            "model_size": self.model_size,
            "language": self.language,
            "max_words_per_line": self.max_words_per_line,
            "max_chars_per_line": self.max_chars_per_line,
            "pause_s": self.pause_s,
            "vad_filter": self.vad_filter,
        }

    def detect(self, video: Path, job: Job) -> Partial:
        transcription = self.transcriber.transcribe(video, self.language)
        if not transcription.words:
            return {}
        fps = job.source["fps"]
        lines = _group_into_lines(
            transcription.words,
            self.max_words_per_line,
            self.max_chars_per_line,
            self.pause_s,
        )
        captions = [
            _line_to_caption(f"caption-{i + 1}", line, transcription.language, fps)
            for i, line in enumerate(lines)
        ]
        return {
            "tracks": [{"id": "captions-1", "kind": "captions", "captions": captions}]
        }
