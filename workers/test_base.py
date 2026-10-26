"""The worker base (#53): a re-run is a cache hit, the key changes with version and params, provenance is stamped, failures
are reported and never cached, and retries stop at the limit and skip errors that can't fix themselves."""

import copy
import hashlib
import io
import json
import logging
import urllib.error
from pathlib import Path
from typing import Any, ClassVar, TypeVar

import pytest

from editrace_schema.constants import SCHEMA_VERSION
from workers import run as runner
from workers.base import Job, RetryPolicy, TransientError, Worker, is_transient
from workers.cache import CacheKey, FileResultStore, Partial, params_hash
from workers.reference import ReferenceWorker
from workers.status import LoggingReporter, State, StatusEvent
from workers.storage import HashMismatchError, HttpsFetcher, LocalFetcher

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schema"
VIDEO_BYTES = b"not really a video, but the base only needs bytes"
CONTENT_HASH = "sha256:" + hashlib.sha256(VIDEO_BYTES).hexdigest()


W = TypeVar("W", bound=Worker)


class Recorder:
    def __init__(self) -> None:
        self.events: list[StatusEvent] = []

    def report(self, event: StatusEvent) -> None:
        self.events.append(event)

    @property
    def states(self) -> list[State]:
        return [e.state for e in self.events]


@pytest.fixture
def source() -> dict[str, Any]:
    example = json.loads(
        (SCHEMA_DIR / "examples" / "01-simple-reel-30fps.json").read_text()
    )
    return {**example["source"], "content_hash": CONTENT_HASH}


@pytest.fixture
def video(tmp_path: Path) -> Path:
    path = tmp_path / "clip.mp4"
    path.write_bytes(VIDEO_BYTES)
    return path


@pytest.fixture
def job(source: dict[str, Any], video: Path) -> Job:
    return Job("job-1", str(video), source)


@pytest.fixture
def store(tmp_path: Path) -> FileResultStore:
    return FileResultStore(tmp_path / "cache")


def no_sleep(_: float) -> None:
    pass


class CountingWorker(ReferenceWorker):
    """The reference worker that counts how often the detector (the GPU step) actually ran."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.detect_calls = 0

    def detect(self, video: Path, job: Job) -> Partial:
        self.detect_calls += 1
        return super().detect(video, job)


def make(
    worker_cls: type[W],
    store: FileResultStore,
    reporter: Recorder | None = None,
    **kw: Any,
) -> W:
    return worker_cls(store, LocalFetcher(), reporter or Recorder(), **kw)


# --- the cache ---------------------------------------------------------------------------------------------------------


def test_same_inputs_are_a_cache_hit_that_skips_detect(
    store: FileResultStore, job: Job
) -> None:
    first = make(CountingWorker, store)
    second = make(
        CountingWorker, store
    )  # a fresh worker: the hit comes from the store, not from memory
    a = first.run(job)
    b = second.run(job)
    assert (a.cached, b.cached) == (False, True)
    assert b.partial == a.partial
    assert (first.detect_calls, second.detect_calls) == (1, 0)


def test_a_hit_does_not_fetch_the_video(store: FileResultStore, job: Job) -> None:
    make(ReferenceWorker, store).run(job)
    missing = Job(job.job_id, "/does/not/exist.mp4", job.source)
    assert make(ReferenceWorker, store).run(missing).cached


def test_changed_version_or_params_is_a_miss(store: FileResultStore, job: Job) -> None:
    make(CountingWorker, store).run(job)

    class V2(CountingWorker):
        version: ClassVar[str] = "0.2.0"

    class Wider(CountingWorker):
        interval = 60

    for cls in (V2, Wider):
        worker = make(cls, store)
        assert not worker.run(job).cached
        assert worker.detect_calls == 1


def test_a_different_video_is_a_miss(
    store: FileResultStore, job: Job, tmp_path: Path, source: dict[str, Any]
) -> None:
    make(ReferenceWorker, store).run(job)
    other = tmp_path / "other.mp4"
    other.write_bytes(b"different bytes")
    other_job = Job(
        "job-2",
        str(other),
        {
            **source,
            "content_hash": "sha256:" + hashlib.sha256(b"different bytes").hexdigest(),
        },
    )
    assert not make(ReferenceWorker, store).run(other_job).cached


def test_the_result_is_stored_on_disk_so_a_new_store_object_hits(
    tmp_path: Path, job: Job
) -> None:
    make(ReferenceWorker, FileResultStore(tmp_path / "c")).run(job)
    assert make(ReferenceWorker, FileResultStore(tmp_path / "c")).run(job).cached


def test_a_failed_run_is_not_cached(store: FileResultStore, job: Job) -> None:
    class Boom(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            raise RuntimeError("model crashed")

    with pytest.raises(RuntimeError):
        make(Boom, store).run(job)
    assert store.get(make(Boom, store).key_for(job)) is None


def test_a_corrupt_or_foreign_cache_file_is_a_miss(
    store: FileResultStore, job: Job
) -> None:
    worker = make(ReferenceWorker, store)
    key = worker.key_for(job)
    worker.run(job)
    path = store.root / key.worker / key.version / f"{key.digest}.json"

    path.write_text("{not json")
    assert store.get(key) is None
    path.write_text(
        json.dumps(
            {"key": "someone-elses", "schema_version": SCHEMA_VERSION, "partial": {}}
        )
    )
    assert store.get(key) is None
    path.write_text(
        json.dumps({"key": key.digest, "schema_version": "0.0.0-old", "partial": {}})
    )
    assert store.get(key) is None
    path.write_text(
        json.dumps(
            {"key": key.digest, "schema_version": SCHEMA_VERSION, "partial": "nope"}
        )
    )
    assert store.get(key) is None
    path.write_text("[]")
    assert store.get(key) is None
    assert not make(ReferenceWorker, store).run(job).cached  # and the run repairs it
    assert store.get(key) is not None


def test_put_leaves_no_temp_file_when_the_write_fails(store: FileResultStore) -> None:
    key = CacheKey(CONTENT_HASH, "w", "1", params_hash({}))
    with pytest.raises(TypeError):
        store.put(key, {"bad": object()})
    assert list((store.root / "w" / "1").glob("*")) == []


def test_cache_key_rejects_a_bad_hash_and_unsafe_names() -> None:
    ok = params_hash({})
    for args in (
        ("md5:abc", "w", "1"),
        (CONTENT_HASH, "../evil", "1"),
        (CONTENT_HASH, "w", "a/b"),
    ):
        with pytest.raises(ValueError):
            CacheKey(*args, ok)


def test_params_hash_ignores_key_order() -> None:
    assert params_hash({"a": 1, "b": 2}) == params_hash({"b": 2, "a": 1})
    assert params_hash({"a": 1}) != params_hash({"a": 2})


# --- running a worker --------------------------------------------------------------------------------------------------


def test_provenance_is_stamped_on_every_element(
    store: FileResultStore, job: Job
) -> None:
    partial = make(ReferenceWorker, store).run(job).partial
    track = partial["tracks"][0]
    stamp = {"detector": "reference-cuts", "version": "0.1.0"}
    assert track["slots"] and track["cuts"]
    assert all(e["provenance"] == stamp for e in track["slots"] + track["cuts"])


def test_the_partial_covers_the_whole_source(store: FileResultStore, job: Job) -> None:
    track = make(ReferenceWorker, store).run(job).partial["tracks"][0]
    assert sum(s["range"]["duration"] for s in track["slots"]) == job.source["duration"]


def test_an_element_with_another_detectors_provenance_is_rejected(
    store: FileResultStore, job: Job
) -> None:
    class Liar(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            partial = super().detect(video, job)
            partial["tracks"][0]["cuts"][0]["provenance"] = {
                "detector": "ocr",
                "version": "9",
            }
            return partial

    with pytest.raises(ValueError, match="provenance"):
        make(Liar, store).run(job)


def test_a_worker_may_state_its_own_provenance(
    store: FileResultStore, job: Job
) -> None:
    class Explicit(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            partial = super().detect(video, job)
            partial["tracks"][0]["cuts"][0]["provenance"] = {
                "detector": self.name,
                "version": self.version,
            }
            return partial

    make(Explicit, store).run(job)


def test_sections_a_worker_does_not_own_are_rejected(
    store: FileResultStore, job: Job
) -> None:
    class Greedy(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            return {"source": {}}

    with pytest.raises(ValueError, match="source"):
        make(Greedy, store).run(job)


def test_output_that_breaks_the_schema_is_rejected_and_not_cached(
    store: FileResultStore, job: Job
) -> None:
    class Bad(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            partial = super().detect(video, job)
            partial["tracks"][0]["cuts"][0]["confidence"] = 7  # confidence is 0 to 1
            return partial

    worker = make(Bad, store)
    with pytest.raises(ValueError):
        worker.run(job)
    assert store.get(worker.key_for(job)) is None


def test_output_that_is_not_json_is_rejected(store: FileResultStore, job: Job) -> None:
    class Opaque(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            return {"tracks": [object()]}

    with pytest.raises(TypeError):
        make(Opaque, store).run(job)


def test_the_run_does_not_mutate_the_job_source(
    store: FileResultStore, job: Job
) -> None:
    before = copy.deepcopy(dict(job.source))
    make(ReferenceWorker, store).run(job)
    assert dict(job.source) == before


# --- the downloaded video ----------------------------------------------------------------------------------------------


def test_a_video_that_does_not_match_the_hash_fails_and_is_not_retried(
    store: FileResultStore, job: Job, tmp_path: Path
) -> None:
    wrong = tmp_path / "wrong.mp4"
    wrong.write_bytes(b"someone else's bytes")
    worker = make(CountingWorker, store)
    with pytest.raises(HashMismatchError):
        worker.run(Job(job.job_id, str(wrong), job.source))
    assert worker.detect_calls == 0


def test_the_worker_sees_the_verified_video(store: FileResultStore, job: Job) -> None:
    seen: list[bytes] = []

    class Peek(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            seen.append(video.read_bytes())
            return super().detect(video, job)

    make(Peek, store).run(job)
    assert seen == [VIDEO_BYTES]


def test_https_fetcher_only_opens_https_urls() -> None:
    for location in ("http://example.test/v.mp4", "file:///etc/passwd", "/etc/passwd"):
        with pytest.raises(ValueError, match="https"):
            HttpsFetcher().open(location)


def test_https_fetcher_opens_an_https_url(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[tuple[str, float]] = []

    def fake_urlopen(url: str, timeout: float) -> io.BytesIO:
        calls.append((url, timeout))
        return io.BytesIO(VIDEO_BYTES)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    assert (
        HttpsFetcher(timeout_s=5).open("https://signed.example.test/v.mp4?sig=x").read()
        == VIDEO_BYTES
    )
    assert calls == [("https://signed.example.test/v.mp4?sig=x", 5)]


# --- retries -----------------------------------------------------------------------------------------------------------


def test_a_transient_failure_is_retried_until_it_works(
    store: FileResultStore, job: Job
) -> None:
    attempts = []

    class Flaky(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            attempts.append(1)
            if len(attempts) < 3:
                raise TransientError("model server busy")
            return super().detect(video, job)

    make(Flaky, store, retry=RetryPolicy(base_delay_s=0)).run(job)
    assert len(attempts) == 3


def test_retries_stop_at_the_attempt_limit(store: FileResultStore, job: Job) -> None:
    attempts = []

    class Down(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            attempts.append(1)
            raise TransientError("still down")

    with pytest.raises(TransientError):
        make(Down, store, retry=RetryPolicy(max_attempts=4, base_delay_s=0)).run(job)
    assert len(attempts) == 4


def test_a_bug_is_not_retried(store: FileResultStore, job: Job) -> None:
    attempts = []

    class Buggy(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            attempts.append(1)
            raise KeyError("oops")

    with pytest.raises(KeyError):
        make(Buggy, store).run(job)
    assert len(attempts) == 1


def test_backoff_grows_and_is_capped_and_jittered() -> None:
    sleeps: list[float] = []
    policy = RetryPolicy(max_attempts=6, base_delay_s=1, max_delay_s=5)

    def fail() -> None:
        raise TransientError

    with pytest.raises(TransientError):
        policy.call(fail, sleep=sleeps.append, rand=lambda: 1.0)
    assert sleeps == [1, 2, 4, 5, 5]
    sleeps.clear()
    with pytest.raises(TransientError):
        policy.call(fail, sleep=sleeps.append, rand=lambda: 0.5)
    assert sleeps == [0.5, 1, 2, 2.5, 2.5]


def test_what_counts_as_transient() -> None:
    def http(code: int) -> urllib.error.HTTPError:
        return urllib.error.HTTPError("https://x.test", code, "msg", {}, None)  # type: ignore[arg-type]

    assert is_transient(TransientError())
    assert is_transient(TimeoutError())
    assert is_transient(ConnectionResetError())
    assert is_transient(OSError("disk hiccup"))
    assert all(is_transient(http(c)) for c in (408, 429, 500, 503))
    assert not any(
        is_transient(http(c)) for c in (400, 403, 404)
    )  # an expired signed URL stays expired
    assert not is_transient(FileNotFoundError())
    assert not is_transient(PermissionError())
    assert not is_transient(ValueError())


# --- status ------------------------------------------------------------------------------------------------------------


def test_status_events_for_a_miss_then_a_hit(store: FileResultStore, job: Job) -> None:
    miss, hit = Recorder(), Recorder()
    make(ReferenceWorker, store, miss).run(job)
    make(ReferenceWorker, store, hit).run(job)
    assert miss.states == [State.RUNNING, State.SUCCEEDED]
    assert miss.events[-1].cached is False and miss.events[-1].duration_s is not None
    assert hit.states == [State.SUCCEEDED]
    assert hit.events[0].cached is True
    assert {e.job_id for e in miss.events + hit.events} == {"job-1"}
    assert {(e.worker, e.version) for e in miss.events} == {("reference-cuts", "0.1.0")}


def test_a_failure_is_reported_with_the_error(store: FileResultStore, job: Job) -> None:
    class Boom(ReferenceWorker):
        def detect(self, video: Path, job: Job) -> Partial:
            raise RuntimeError("model crashed")

    recorder = Recorder()
    with pytest.raises(RuntimeError):
        make(Boom, store, recorder).run(job)
    assert recorder.states == [State.RUNNING, State.FAILED]
    assert recorder.events[-1].error == "RuntimeError: model crashed"


def test_the_default_reporter_logs_json_with_the_job_id(
    store: FileResultStore, job: Job, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level(logging.INFO, logger="editrace.workers"):
        ReferenceWorker(store, LocalFetcher()).run(job)
    lines = [json.loads(r.getMessage()) for r in caplog.records]
    assert [line["state"] for line in lines] == ["running", "succeeded"]
    assert all(line["job_id"] == "job-1" for line in lines)


def test_a_failure_is_logged_as_an_error(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.INFO, logger="editrace.workers"):
        LoggingReporter().report(StatusEvent("j", "w", "1", State.FAILED, error="x"))
    assert caplog.records[0].levelno == logging.ERROR


# --- the local runner --------------------------------------------------------------------------------------------------


def test_local_runner_misses_then_hits(
    tmp_path: Path,
    video: Path,
    source: dict[str, Any],
    capsys: pytest.CaptureFixture[str],
) -> None:
    source_file = tmp_path / "source.json"
    source_file.write_text(
        json.dumps({**source, "content_hash": "sha256:" + "0" * 64})
    )  # replaced by the real hash
    args = [
        "workers.reference:ReferenceWorker",
        str(video),
        "--source",
        str(source_file),
        "--cache-dir",
        str(tmp_path / "c"),
    ]
    assert runner.main(args) == 0
    first = capsys.readouterr()
    assert runner.main(args) == 0
    second = capsys.readouterr()
    assert "cache miss" in first.err and "cache hit" in second.err
    assert json.loads(first.out) == json.loads(second.out)


def test_local_runner_rejects_something_that_is_not_a_worker() -> None:
    with pytest.raises(SystemExit):
        runner.load_worker_class("workers.base:Job")
