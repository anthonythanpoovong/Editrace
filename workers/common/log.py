"""Structured JSON logging for workers. Field names and rules: docs/observability.md

Usage:
    from common.log import bind, get_logger

    log = get_logger("worker:cuts")
    with bind(job_id=job_id, user_id=user_id, template_id=template_id, request_id=request_id):
        log.info("job started", extra={"fields": {"frames": 1200}})

Standard library only, so it works before the workers have a pyproject (#2).
"""

from __future__ import annotations

import json
import logging
import os
import re
import sys
import traceback
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

_context: ContextVar[dict[str, Any]] = ContextVar("log_context", default={})  # noqa: B039

SENSITIVE = re.compile(
    r"token|authorization|password|secret|api_?key|cookie|email", re.IGNORECASE
)
_LEVELS = {"WARNING": "warn", "CRITICAL": "error"}


def _clean(value: Any, depth: int = 0) -> Any:
    if isinstance(value, BaseException):
        return _serialize_error(value)
    if depth > 5:
        return value
    if isinstance(value, dict):
        return {
            k: "[redacted]" if SENSITIVE.search(str(k)) else _clean(v, depth + 1)
            for k, v in value.items()
        }
    if isinstance(value, list | tuple):
        return [_clean(v, depth + 1) for v in value]
    return value


def _serialize_error(err: BaseException) -> dict[str, Any]:
    return {
        "name": type(err).__name__,
        "message": str(err),
        "stack": "".join(traceback.format_exception(type(err), err, err.__traceback__)),
    }


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str) -> None:
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        fields: dict[str, Any] = {**_context.get(), **getattr(record, "fields", {})}
        if record.exc_info and record.exc_info[1] is not None:
            fields.setdefault("err", record.exc_info[1])
        entry = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(
                timespec="milliseconds"
            ),
            "level": _LEVELS.get(record.levelname, record.levelname.lower()),
            "service": self.service,
            "env": os.environ.get("APP_ENV", "dev"),
            "msg": record.getMessage(),
            **_clean(fields),
        }
        return json.dumps(entry, default=str)


def get_logger(service: str, stream: Any = None) -> logging.Logger:
    """Return a logger that writes one JSON object per line to stdout (or `stream`)."""
    logger = logging.getLogger(f"editrace.{service}")
    if not logger.handlers:
        handler = logging.StreamHandler(stream or sys.stdout)
        handler.setFormatter(JsonFormatter(service))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False
    return logger


@contextmanager
def bind(**fields: Any) -> Iterator[None]:
    """Add fields (job_id, user_id, ...) to every log line written inside the block."""
    token = _context.set({**_context.get(), **fields})
    try:
        yield
    finally:
        _context.reset(token)
