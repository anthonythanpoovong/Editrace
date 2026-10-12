import io
import json
import unittest
import uuid
from datetime import UTC, datetime

from common.log import bind, get_logger


def make_logger():
    stream = io.StringIO()
    return get_logger(f"worker:test-{uuid.uuid4().hex[:8]}", stream), stream


def lines(stream: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in stream.getvalue().splitlines()]


class LogTest(unittest.TestCase):
    def test_standard_fields(self):
        log, stream = make_logger()
        log.info("job started", extra={"fields": {"frames": 12}})

        [entry] = lines(stream)
        self.assertEqual(entry["level"], "info")
        self.assertEqual(entry["msg"], "job started")
        self.assertTrue(entry["service"].startswith("worker:test-"))
        self.assertEqual(entry["frames"], 12)
        self.assertIn("env", entry)
        self.assertIn("ts", entry)

    def test_bind_adds_context_and_resets(self):
        log, stream = make_logger()
        with bind(job_id="j1", user_id="u1"), bind(template_id="t1"):
            log.warning("inside")
        log.info("outside")

        inside, outside = lines(stream)
        self.assertEqual(inside["level"], "warn")
        self.assertEqual(
            {k: inside[k] for k in ("job_id", "user_id", "template_id")},
            {"job_id": "j1", "user_id": "u1", "template_id": "t1"},
        )
        self.assertNotIn("job_id", outside)

    def test_redacts_sensitive_keys(self):
        log, stream = make_logger()
        log.info(
            "call",
            extra={
                "fields": {
                    "api_key": "sk-1",
                    "headers": {"Authorization": "x", "accept": "json"},
                }
            },
        )

        [entry] = lines(stream)
        self.assertEqual(entry["api_key"], "[redacted]")
        self.assertEqual(
            entry["headers"], {"Authorization": "[redacted]", "accept": "json"}
        )

    def test_truncates_past_depth_limit(self):
        log, stream = make_logger()
        deep = {"a": {"b": {"c": {"d": {"e": {"f": {"token": "x"}}}}}}}
        log.info("deep", extra={"fields": deep})

        raw = stream.getvalue()
        self.assertNotIn('"x"', raw)
        self.assertIn("[truncated]", raw)

    def test_circular_objects_do_not_break_logging(self):
        log, stream = make_logger()
        loop: dict = {"name": "loop"}
        loop["self"] = loop
        log.info("circular", extra={"fields": {"loop": loop}})

        [entry] = lines(stream)
        self.assertEqual(entry["msg"], "circular")

    def test_keeps_line_when_fields_not_serializable(self):
        log, stream = make_logger()
        with bind(job_id="j1"):
            log.error("job failed", extra={"fields": {"by_pair": {(1, 2): "x"}}})

        [entry] = lines(stream)
        self.assertEqual(entry["level"], "error")
        self.assertEqual(entry["msg"], "job failed")
        self.assertIn("fields not serializable", entry["log_error"])

    def test_dates_and_sets(self):
        log, stream = make_logger()
        started = datetime(2026, 10, 12, 19, 38, 35, tzinfo=UTC)
        log.info(
            "job started", extra={"fields": {"started_at": started, "tags": {"b", "a"}}}
        )

        [entry] = lines(stream)
        self.assertEqual(entry["started_at"], "2026-10-12T19:38:35+00:00")
        self.assertEqual(entry["tags"], ["a", "b"])

    def test_fields_cannot_overwrite_standard_fields(self):
        log, stream = make_logger()
        with bind(service="spoofed"):
            log.warning(
                "real message",
                extra={"fields": {"level": "debug", "msg": "fake", "ts": "yesterday"}},
            )

        [entry] = lines(stream)
        self.assertEqual(entry["level"], "warn")
        self.assertEqual(entry["msg"], "real message")
        self.assertTrue(entry["service"].startswith("worker:test-"))
        self.assertNotEqual(entry["ts"], "yesterday")

    def test_keeps_token_counts_but_redacts_tokens(self):
        log, stream = make_logger()
        log.info(
            "assistant reply",
            extra={
                "fields": {
                    "usage": {"input_tokens": 512, "cache_read_input_tokens": 64},
                    "max_tokens": 1024,
                    "token_count": 7,
                    "access_token": "abc",
                    "auth_tokens": ["abc", "def"],
                    "refresh_token": 12345,
                    "id_tokens": True,
                }
            },
        )

        [entry] = lines(stream)
        self.assertEqual(
            entry["usage"], {"input_tokens": 512, "cache_read_input_tokens": 64}
        )
        self.assertEqual(entry["max_tokens"], 1024)
        self.assertEqual(entry["token_count"], 7)
        for key in ("access_token", "auth_tokens", "refresh_token", "id_tokens"):
            self.assertEqual(entry[key], "[redacted]", key)

    def test_serializes_exceptions(self):
        log, stream = make_logger()
        try:
            raise ValueError("boom")
        except ValueError:
            log.exception("job failed")

        [entry] = lines(stream)
        self.assertEqual(entry["level"], "error")
        self.assertEqual(entry["err"]["name"], "ValueError")
        self.assertEqual(entry["err"]["message"], "boom")
        self.assertIn("boom", entry["err"]["stack"])


if __name__ == "__main__":
    unittest.main()
