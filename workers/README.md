# Workers

Python analysis pipeline running on Modal (serverless GPU).

## Stack

- **Runtime:** Modal (serverless GPU)
- **Language:** Python 3.11+
- **ML frameworks:** chosen per worker (PyTorch, librosa and OpenCV are the likely ones)
- **Orchestration:** the orchestrator (#59) dispatches jobs from the jobs table (#58). Neither exists yet.

## The worker base (#53)

Every worker subclasses `workers.base.Worker` and implements `detect()`. The base does the rest: it looks the job up in the
result store, downloads the video and checks it against the job's content hash, runs `detect()`, stamps provenance on
every element, validates the partial template against the strict schema models, stores it and reports status.

```python
class CutsWorker(Worker):
    name = "cuts"  # the provenance detector
    version = "0.1.0"  # bump on any change that can change the output
    compute = Compute(gpu="T4", memory_mb=8192)

    def params(self):
        return {"threshold": 0.5}  # anything that changes the output

    def detect(self, video: Path, job: Job) -> Partial:
        return {"tracks": [...]}  # tracks, beats and sound_ref only
```

- **Cache.** The key is content hash, worker, version and a hash of `params()`. Re-running a job with the same inputs returns the stored result without fetching the video or calling `detect()`. Only successful runs are stored. Change `version` or a param and it is a miss.
- **Retries.** `TransientError`, timeouts, connection errors and 5xx/429 responses are retried with capped, jittered exponential backoff. Bugs, bad input and a missing file fail at once, because a retry on a GPU container is billed.
- **Fetching.** Workers get a short-lived signed https URL, never storage credentials, and the download must hash to the claimed `content_hash`.
- **Status.** Each run emits `running`, then `succeeded` (with `cached` and `duration_s`) or `failed`, as a JSON log line carrying `job_id`.
- **Modal.** The base doesn't import Modal. `compute` is data for the Modal wrapper that goes in with the first deployed worker (#7).

Try it without Modal or a database:

```sh
python -m workers.run workers.reference:ReferenceWorker clip.mp4 --source source.json
```

A second run prints `cache hit`. `workers/reference.py` is the smallest possible worker.

## Writing a worker

Subclass `Worker` as above. One worker per detector, each in its own module under `workers/`. `workers/reference.py` is the template to copy. The planned detectors are tracked as issues, not here.

## Output

All workers write results to `schema`-valid template JSON format.

## Generated Code

Pydantic models are **generated from `schema/template.schema.json`**. Do not hand-write models — regenerate from schema.
