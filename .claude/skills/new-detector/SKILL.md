---
name: new-detector
description: Scaffold a new Sequa analysis worker/detector on Modal (cuts, transitions, motion, OCR, captions, beats, color, shot descriptors, footage match, etc.) using the shared worker base, with confidence/provenance, idempotency, downsampling, cost logging and a golden-set test. Use when someone says "add a detector", "new worker for X", or picks up a #41 story that adds analysis.
---

# New detector / worker

Every detector writes a **partial template** (schema-valid) that the orchestrator merges. They all share the worker base from #53, so none of them duplicates I/O, retries or status code.

## 0. Preflight: stop if the foundations aren't there
- **Worker base (#53):** find it in `workers/`. If there's no shared base yet, stop. Building a detector without it duplicates I/O code, which #53's acceptance criteria forbid. Offer to help with #53, or build it as a spike (`/spike`).
- **Generated Pydantic models (#2):** they must exist. Never hand-write models.
- **The schema has somewhere to put the output.** If the detector outputs a new field or section, run `/schema-change` first.
- **Golden set (#52):** check whether labels exist for this element type. If not, note that the detector can't be evaluated yet, and add the labeling need to #52.

Read how the existing workers are laid out (file naming, registration, config) and **copy that pattern**. `workers/README.md` lists the planned files (e.g. `cut_detection.py`).

## 1. Define the contract (confirm with the author)
- **Input:** which video or audio, and at what resolution and fps. Default to downsampled input (e.g. 2 fps / 720p for framing and lighting; full frame rate only where timing precision needs it, like cuts).
- **Output:** exactly which template elements or fields it fills.
- **Confidence:** how it's computed (model score, agreement, heuristic).
- **GPU or CPU,** and the expected seconds per minute of video.
- **Owner:** CV 1 (visual) or CV 2 (signals).

## 2. Scaffold
Following the worker base's pattern:
- A detector module that implements the base interface: load input → run → return partial template elements.
- Stamp **`provenance`** (detector name + version) and **`confidence`** on every element.
- **Time as integer frames + rational fps.** Convert once, at the boundary. No float seconds in the output.
- **Idempotency:** the base keys caching by content hash + worker version. Bump the version whenever output could change.
- **Cost:** log GPU/CPU seconds per run through the observability hooks (#50). Respect any caps (e.g. #102 for footage match).
- **Audio:** never persist or return audio. Only features, markers and sound IDs (Key Decision).
- **Partial failure:** on error, return a structured failure the orchestrator can tolerate. The template must still be usable (#41 principle).

## 3. Test
- Unit tests on a tiny fixture video (shared fixtures from #53/#52).
- Validate the output against the schema, using the generated Pydantic models.
- A golden-set run via `/golden-eval` if labels exist.
- Local run through the base's local runner on a sample video.
- `uv run ruff check . && uv run ruff format --check . && uv run pytest` (what CI runs).

## 4. PR
Link the story. Include: the contract (input, output, confidence), cost per minute of video, golden-eval table (or "no labels yet, tracked in #52"), and sample output.

## Rules
- No hand-written types, no float-seconds time, no stored audio, no bespoke I/O outside the base.
- After merge: `/sync-docs` updates the wiki `Video-Analysis-Pipeline` detectors table.
