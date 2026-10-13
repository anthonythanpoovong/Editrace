"""Tests for read_template (#206): a template from a newer minor version loads, with unknown enum values reported."""

import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from editrace_schema import Skipped, Template, read_template

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schema"
VECTOR = json.loads((SCHEMA_DIR / "test-vectors" / "forward-compat.json").read_text())[
    "document"
]
EXAMPLES = sorted((SCHEMA_DIR / "examples").glob("*.json"))
INVALID = sorted((SCHEMA_DIR / "examples" / "invalid").glob("*.json"))


def dump(result) -> dict:
    return json.loads(result.template.model_dump_json(exclude_unset=True))


def test_forward_compat_vector_loads_and_reports_the_unknown_transition() -> None:
    result = read_template(VECTOR)
    assert result.skipped == [
        Skipped(path=("tracks", 0, "transitions", 1), field="type", value="hologram")
    ]


def test_unknown_values_and_fields_survive_a_rewrite() -> None:
    assert dump(read_template(VECTOR)) == VECTOR


def test_strict_model_still_rejects_the_vector() -> None:
    # Writers stay strict: a worker must not be able to save an unknown enum value.
    with pytest.raises(ValidationError):
        Template.model_validate(VECTOR)


@pytest.mark.parametrize("path", EXAMPLES, ids=lambda p: p.name)
def test_valid_example_reports_nothing_skipped(path: Path) -> None:
    document = json.loads(path.read_text())
    result = read_template(document)
    assert result.skipped == []
    assert dump(result) == document


def test_every_unknown_enum_value_is_reported() -> None:
    document = copy.deepcopy(VECTOR)
    document["tracks"][0]["transitions"][0]["type"] = "star-wipe"
    assert {s.value for s in read_template(document).skipped} == {
        "star-wipe",
        "hologram",
    }


def test_another_problem_next_to_an_unknown_value_still_raises() -> None:
    document = copy.deepcopy(VECTOR)
    document["tracks"][0]["transitions"][0]["confidence"] = 7  # above the maximum of 1
    with pytest.raises(ValidationError):
        read_template(document)


@pytest.mark.parametrize("path", INVALID, ids=lambda p: p.name)
def test_invalid_fixture_is_not_skipped_as_unknown_enum(path: Path) -> None:
    """Relaxing enums must not let the invalid fixtures through for other reasons. The one fixture whose only defect is
    an unknown enum value (unknown-transition-type) is exactly what a reader tolerates."""
    document = json.loads(path.read_text())
    if path.name == "unknown-transition-type.json":
        assert [s.value for s in read_template(document).skipped] == ["sparkle"]
        return
    from editrace_schema.test_models import KNOWN_GAPS

    if (
        path.name in KNOWN_GAPS
    ):  # not catchable by generated types at all, strict or reader
        read_template(document)
    else:
        with pytest.raises(ValidationError):
            read_template(document)
