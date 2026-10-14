"""Round-trip tests for the generated models (#2): the examples load and dump back identical, unknown fields survive
(docs/schema.md), and the invalid fixtures are rejected except for the gaps listed below."""

import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from editrace_schema import Template

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schema"
EXAMPLES = sorted((SCHEMA_DIR / "examples").glob("*.json"))
INVALID = sorted((SCHEMA_DIR / "examples" / "invalid").glob("*.json"))

# Constraints that generated types can't express. The JSON Schema validator (schema/check-invalid.sh) still rejects
# all of these, so the schema stays the gate for writers. Don't add to this list to make a test pass: fix the schema
# or the generator settings. A fixture that Pydantic starts rejecting must come off the list (the test below fails).
KNOWN_GAPS = {
    "missing-slots.json": "if/then: a video track needs slots",
    "vfr-without-conform.json": "if/then: variable frame rate needs conform",
    "sound-ref-insecure-link.json": "format uri plus pattern ^https:// becomes a plain AnyUrl",
}


def dump(template: Template) -> dict:
    return json.loads(template.model_dump_json(exclude_unset=True))


@pytest.mark.parametrize("path", EXAMPLES, ids=lambda p: p.name)
def test_example_round_trips_without_loss(path: Path) -> None:
    document = json.loads(path.read_text())
    assert dump(Template.model_validate(document)) == document


def test_unknown_fields_survive_a_rewrite() -> None:
    document = json.loads(EXAMPLES[0].read_text())
    document["future_field"] = {"added_in": "0.2.0"}
    document["tracks"][0]["future_track_field"] = [1, 2, 3]
    document["source"]["future_source_field"] = "kept"
    assert dump(Template.model_validate(document)) == document


def test_sound_ref_stays_closed() -> None:
    document = json.loads(EXAMPLES[0].read_text())
    base = next(
        (d for d in map(json.loads, map(Path.read_text, EXAMPLES)) if "sound_ref" in d),
        None,
    )
    assert base is not None, "no example has a sound_ref to test with"
    document = copy.deepcopy(base)
    document["sound_ref"]["audio"] = "base64..."
    with pytest.raises(ValidationError):
        Template.model_validate(document)


@pytest.mark.parametrize("path", INVALID, ids=lambda p: p.name)
def test_invalid_fixture_is_rejected(path: Path) -> None:
    document = json.loads(path.read_text())
    if path.name in KNOWN_GAPS:
        # Still accepted today. If this fails, the gap closed: remove it from KNOWN_GAPS.
        Template.model_validate(document)
    else:
        with pytest.raises(ValidationError):
            Template.model_validate(document)


def test_known_gaps_name_real_fixtures() -> None:
    assert set(KNOWN_GAPS) <= {p.name for p in INVALID}
