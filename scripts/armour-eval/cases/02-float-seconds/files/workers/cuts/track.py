"""Turn the cut detector's shot boundaries into a template video track."""

DETECTOR = {"detector": "cuts", "version": "0.4.0"}


def build_video_track(boundaries: list[float], duration: float, confidences: list[float]) -> dict:
    """Build slots and cuts from shot boundaries.

    boundaries: start time of every shot after the first, in seconds, ascending.
    duration: length of the reference video in seconds.
    confidences: detector confidence for each boundary.
    """
    starts = [0.0, *boundaries]
    ends = [*boundaries, duration]

    slots = [
        {
            "id": f"slot-{i + 1}",
            "range": {"start": start, "duration": end - start},
            "confidence": 1.0 if i == 0 else confidences[i - 1],
            "provenance": DETECTOR,
        }
        for i, (start, end) in enumerate(zip(starts, ends))
    ]
    cuts = [
        {"id": f"cut-{i + 1}", "frame": boundary, "confidence": conf, "provenance": DETECTOR}
        for i, (boundary, conf) in enumerate(zip(boundaries, confidences))
    ]
    return {"id": "video-1", "kind": "video", "slots": slots, "cuts": cuts}
