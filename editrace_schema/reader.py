"""Reading a template that may come from a newer minor version (#206).

`Template` (editrace_schema.models) is strict, for writers: an unknown enum value is an error, so a worker can't save
one. Readers can't do that. docs/schema.md says an unknown enum value is "unsupported; the adapter reports the element
as skipped and never fails the whole template". `read_template` does that: it loads the document with the reader
models, where enum fields are plain strings, and reports each element holding a value the strict schema doesn't know.
A track `kind` we don't know is reported the same way. `kind` is a free string, so it never fails validation and
would otherwise be missed.
Every other problem (a bad range, a missing field, a malformed pattern) still raises, and unknown fields and values
survive a `model_dump`.

It also applies the version rules from the same table: a template with a higher major version than this code supports is
rejected, naming both versions, before anything else is read, because its structure may not match these models.
"""

import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

from pydantic import ValidationError

from editrace_schema.constants import KNOWN_TRACK_KINDS, SCHEMA_VERSION
from editrace_schema.models import EditraceTemplate as Template
from editrace_schema.reader_models import EditraceTemplate as ReaderTemplate

# A migration takes a template document from an older major version and returns it in the reader's major version.
Migration = Callable[[Mapping[str, Any]], Mapping[str, Any]]

_SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


class UnsupportedVersionError(ValueError):
    """The template's major version isn't one this reader supports. The message names both versions."""


@dataclass(frozen=True)
class Skipped:
    """An element holding an enum value this version of the schema doesn't know."""

    path: tuple[
        str | int, ...
    ]  # where the element is, e.g. ("tracks", 0, "transitions", 1)
    field: str  # the field with the unknown value, e.g. "type"
    value: object  # the value, e.g. "hologram"


@dataclass(frozen=True)
class ReadResult:
    template: ReaderTemplate
    skipped: list[Skipped]


def migrate_to_supported_version(
    reader: str,
    document: Mapping[str, Any],
    migrations: Mapping[int, Migration] | None = None,
) -> Mapping[str, Any]:
    """Apply the version rules to `document` for a reader that supports `reader` (docs/schema.md):

    - same major (any minor or patch, higher or lower): returned as is;
    - higher major: raises UnsupportedVersionError;
    - lower major: raises unless `migrations` has one for that major, which is applied.

    A document without a well-formed `schema_version` is returned as is, so validation reports it."""
    version = document.get("schema_version")
    if not isinstance(version, str) or not _SEMVER.match(version):
        return document
    reader_major, document_major = int(reader.split(".")[0]), int(version.split(".")[0])
    if document_major > reader_major:
        raise UnsupportedVersionError(
            f"template is {version}, reader supports {reader}"
        )
    if document_major < reader_major:
        migration = (migrations or {}).get(document_major)
        if migration is None:
            raise UnsupportedVersionError(
                f"template is {version}, reader is {reader} and has no migration"
            )
        return migration(document)
    return document


def read_template(
    document: Mapping[str, Any], *, migrations: Mapping[int, Migration] | None = None
) -> ReadResult:
    """Load `document`, reporting elements with an unknown enum value, and tracks of an unknown kind, as skipped. A template from a higher major
    version raises `UnsupportedVersionError`, and from a lower one unless `migrations` can upgrade it. Anything else
    invalid raises `pydantic.ValidationError`. Validates twice (strict, then reader), which is fine for a template's
    size."""
    document = migrate_to_supported_version(SCHEMA_VERSION, document, migrations)
    skipped: list[Skipped] = []
    try:
        Template.model_validate(document)
    except ValidationError as error:
        problems = error.errors()
        # The strict model's own enum errors name exactly the unknown values, so no enum list lives in this file.
        if any(problem["type"] != "enum" for problem in problems):
            raise
        skipped = [
            Skipped(
                path=tuple(problem["loc"][:-1]),
                field=str(problem["loc"][-1]),
                value=problem["input"],
            )
            for problem in problems
        ]
    template = ReaderTemplate.model_validate(document)
    # An unknown track kind passes validation (it is a free string), so look for it here. Listed after the enum values.
    skipped += [
        Skipped(path=("tracks", index), field="kind", value=track.kind)
        for index, track in enumerate(template.tracks)
        if track.kind not in KNOWN_TRACK_KINDS
    ]
    return ReadResult(template=template, skipped=skipped)
