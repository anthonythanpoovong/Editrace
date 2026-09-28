# Workers

Python analysis pipeline running on Modal (serverless GPU).

## Stack

- **Runtime:** Modal (serverless GPU)
- **Language:** Python 3.11+
- **ML Frameworks:** TBD (PyTorch, librosa, OpenCV recommended)
- **Job Queue:** Trigger from web app via job queue

## Workers

### CV1 — Visual Timeline (calvinkafaiyuen)
- `cut_detection.py` — Detect cuts using TransNetV2 or PySceneDetect
- `motion_estimation.py` — Estimate zooms, pans, speed ramps

### CV2 — Signals & Scoring (sktchan)
- `captions.py` — Speech-to-text (Whisper)
- `ocr.py` — Text overlay detection (OCR)
- `beat_detection.py` — Beat tracking and sound fingerprinting

## Output

All workers write results to `schema`-valid template JSON format.

## Generated Code

Pydantic models are **generated from `schema/template.schema.json`**. Do not hand-write models — regenerate from schema.
