"""A minimal worker that shows the contract and exercises the base in the tests and the local runner (#53). It places a
cut every `interval` frames. It is not a detector: real workers (cuts #7, captions #12) subclass `Worker` the same way."""

from collections.abc import Mapping
from pathlib import Path
from typing import Any, ClassVar

from workers.base import Compute, Job, Worker
from workers.cache import Partial


class ReferenceWorker(Worker):
    name: ClassVar[str] = "reference-cuts"
    version: ClassVar[str] = "0.1.0"
    compute: ClassVar[Compute] = Compute(cpu=0.25, memory_mb=512, timeout_s=60)

    interval = 30

    def params(self) -> Mapping[str, Any]:
        return {"interval": self.interval}

    def detect(self, video: Path, job: Job) -> Partial:
        duration = job.source["duration"]
        starts = list(range(0, duration, self.interval))
        slots = [
            {
                "id": f"slot-{i + 1}",
                "range": {"start": s, "duration": min(self.interval, duration - s)},
                "confidence": 1.0,
            }
            for i, s in enumerate(starts)
        ]
        cuts = [
            {"id": f"cut-{i}", "frame": s, "confidence": 1.0}
            for i, s in enumerate(starts)
            if i > 0
        ]
        return {
            "tracks": [{"id": "video-1", "kind": "video", "slots": slots, "cuts": cuts}]
        }
