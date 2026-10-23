"""Status reporting for a worker run (#53). The orchestrator (#59) turns these events into `jobs` sub-status (#58)."""

import json
import logging
from dataclasses import asdict, dataclass
from enum import StrEnum
from typing import Protocol

log = logging.getLogger("editrace.workers")


class State(StrEnum):
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


@dataclass(frozen=True)
class StatusEvent:
    job_id: str
    worker: str
    version: str
    state: State
    cached: bool = False  # succeeded from the result store: no GPU time was spent
    duration_s: float | None = (
        None  # wall time of the fetch and detect steps, for cost tracking (#50, #102)
    )
    error: str | None = None


class StatusReporter(Protocol):
    def report(self, event: StatusEvent) -> None: ...


class LoggingReporter:
    """One structured JSON line per event, carrying `job_id` so a failing job can be traced to its worker logs (#50)."""

    def report(self, event: StatusEvent) -> None:
        level = logging.ERROR if event.state is State.FAILED else logging.INFO
        log.log(level, json.dumps(asdict(event)))
