import io
import json
import unittest
import uuid

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
