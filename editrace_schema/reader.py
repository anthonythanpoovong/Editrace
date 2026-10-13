"""Reading a template that may come from a newer minor version (#206).

`Template` (editrace_schema.models) is strict, for writers: an unknown enum value is an error, so a worker can't save
one. Readers can't do that. docs/schema.md says an unknown enum value is "unsupported; the adapter reports the element
as skipped and never fails the whole template". `read_template` does that: it loads the document with the reader
models, where enum fields are plain strings, and reports each element holding a value the strict schema doesn't know.
Every other problem (a bad range, a missing field, a malformed pattern) still raises, and unknown fields and values
survive a `model_dump`.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from pydantic import ValidationError

from editrace_schema.models import EditraceTemplate as Template
from editrace_schema.reader_models import EditraceTemplate as ReaderTemplate


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


def read_template(document: Mapping[str, Any]) -> ReadResult:
    """Load `document`, reporting elements with an unknown enum value as skipped. Anything else invalid raises
    `pydantic.ValidationError`. Validates twice (strict, then reader), which is fine for a template's size."""
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
    return ReadResult(template=ReaderTemplate.model_validate(document), skipped=skipped)
