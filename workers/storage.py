"""Fetching the video for a worker (#53). The orchestrator hands a worker a location, in production a short-lived signed
https URL, so no storage credentials reach the GPU container. The download is hashed as it streams and must match the
content hash the job claims, which stops a wrong or truncated file from being analyzed and cached under that hash."""

import hashlib
import urllib.request
from pathlib import Path
from typing import IO, Protocol
from urllib.parse import urlparse


class Fetcher(Protocol):
    def open(self, location: str) -> IO[bytes]: ...


class HashMismatchError(ValueError):
    """The downloaded bytes don't hash to the job's content hash. Not retried: fetching again returns the same bytes."""


class HttpsFetcher:
    def __init__(self, timeout_s: float = 60) -> None:
        self.timeout_s = timeout_s

    def open(self, location: str) -> IO[bytes]:
        if urlparse(location).scheme != "https":
            raise ValueError("a video location must be an https URL")
        return urllib.request.urlopen(location, timeout=self.timeout_s)


class LocalFetcher:
    """For the local runner and tests: the location is a file path. Never used with a location from a job."""

    def open(self, location: str) -> IO[bytes]:
        return Path(location).open("rb")


def download(fetcher: Fetcher, location: str, dest: Path, content_hash: str) -> None:
    digest = hashlib.sha256()
    with fetcher.open(location) as src, dest.open("wb") as out:
        while chunk := src.read(1 << 20):
            digest.update(chunk)
            out.write(chunk)
    actual = f"sha256:{digest.hexdigest()}"
    if actual != content_hash:
        raise HashMismatchError(
            f"downloaded video hashes to {actual}, expected {content_hash}"
        )
