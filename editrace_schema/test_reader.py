"""Tests for read_template (#206): a template from a newer minor version loads, with unknown enum values reported."""

import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from editrace_schema import (
    Skipped,
    Template,
    UnsupportedVersionError,
    migrate_to_supported_version,
    read_template,
)
from editrace_schema.constants import KNOWN_TRACK_KINDS, SCHEMA_VERSION

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schema"
VECTOR = json.loads((SCHEMA_DIR / "test-vectors" / "forward-compat.json").read_text())[
    "document"
]
EXAMPLES = sorted((SCHEMA_DIR / "examples").glob("*.json"))
INVALID = sorted((SCHEMA_DIR / "examples" / "invalid").glob("*.json"))
VERSION_CASES = json.loads((SCHEMA_DIR / "test-vectors" / "versions.json").read_text())[
    "cases"
]


def dump(result) -> dict:
    return json.loads(result.template.model_dump_json(exclude_unset=True))


def test_forward_compat_vector_reports_the_unknown_transition_and_track_kind() -> None:
    # The vector has both: an unknown transition type and an unknown track kind (docs/schema.md skips both).
    result = read_template(VECTOR)
    assert result.skipped == [
        Skipped(path=("tracks", 0, "transitions", 1), field="type", value="hologram"),
        Skipped(path=("tracks", 1), field="kind", value="hologram"),
    ]


def test_known_track_kinds_come_from_the_schema() -> None:
    assert KNOWN_TRACK_KINDS == {"video", "text", "captions"}


def test_a_known_track_kind_is_never_reported() -> None:
    document = json.loads(EXAMPLES[0].read_text())
    assert {track["kind"] for track in document["tracks"]} <= KNOWN_TRACK_KINDS
    assert read_template(document).skipped == []


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
    skipped = read_template(document).skipped
    assert {s.value for s in skipped if s.field == "type"} == {"star-wipe", "hologram"}


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


# ---- versions (ADR 0002): the same cases schema/check-vectors.sh runs -----------------------------------------------


@pytest.mark.parametrize("case", VERSION_CASES, ids=lambda c: c["name"])
def test_version_rules_match_the_shared_vector(case: dict) -> None:
    document = {"schema_version": case["document"]}
    migrations = {
        major: lambda doc: {**doc, "migrated": True} for major in case["migrations"]
    }
    if case["expected"] == "reject":
        with pytest.raises(UnsupportedVersionError) as error:
            migrate_to_supported_version(case["reader"], document, migrations)
        assert all(version in str(error.value) for version in case["error_mentions"])
    elif case["expected"] == "accept_via_migration":
        assert (
            migrate_to_supported_version(case["reader"], document, migrations).get(
                "migrated"
            )
            is True
        )
    else:
        assert (
            migrate_to_supported_version(case["reader"], document, migrations)
            == document
        )


def test_a_higher_major_is_rejected_before_anything_else_is_read() -> None:
    # Its structure may not match these models, so no other error should hide the real reason.
    major = int(SCHEMA_VERSION.split(".")[0]) + 1
    document = {"schema_version": f"{major}.0.0", "tracks": "not even a list"}
    with pytest.raises(
        UnsupportedVersionError, match=rf"{major}\.0\.0.*{SCHEMA_VERSION}"
    ):
        read_template(document)


def test_a_higher_minor_loads() -> None:
    assert read_template(VECTOR).template.schema_version == VECTOR["schema_version"]


def test_a_missing_or_malformed_version_is_left_to_validation() -> None:
    for document in (
        {"source": {}},
        {"schema_version": "banana"},
        {"schema_version": 3},
    ):
        with pytest.raises(ValidationError):
            read_template(document)


def test_a_migration_upgrades_an_older_major() -> None:
    document = json.loads(EXAMPLES[0].read_text())
    older = {**document, "schema_version": "0.1.0"}
    # Pretend this reader is 1.x: a migration for major 0 produces a document it can read.
    migrated = migrate_to_supported_version(
        "1.0.0", older, {0: lambda doc: {**doc, "schema_version": "1.0.0"}}
    )
    assert migrated["schema_version"] == "1.0.0"


def test_the_vector_is_read_by_the_version_this_code_supports() -> None:
    reader = json.loads(
        (SCHEMA_DIR / "test-vectors" / "forward-compat.json").read_text()
    )["reader"]
    assert reader.split(".")[0] == SCHEMA_VERSION.split(".")[0]


def test_schema_version_file_matches_the_generated_constant_and_the_examples() -> None:
    assert (SCHEMA_DIR / "VERSION").read_text().strip() == SCHEMA_VERSION
    for path in EXAMPLES:
        # Examples are written against the current schema: same major, and never newer than the schema.
        written = tuple(
            int(x) for x in json.loads(path.read_text())["schema_version"].split(".")
        )
        current = tuple(int(x) for x in SCHEMA_VERSION.split("."))
        assert written[0] == current[0] and written <= current, (
            f"{path.name} is {written}, schema is {current}"
        )
