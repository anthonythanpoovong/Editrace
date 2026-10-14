"""Prints editrace_schema/constants.py for `make codegen`: what readers need to know about the schema they were built from.

- SCHEMA_VERSION comes from schema/VERSION, the one place the version is written down. Readers compare a template's
  `schema_version` with it (docs/schema.md, "Versions and forward compatibility"). Bump it with the schema.
- KNOWN_TRACK_KINDS comes from the schema's own per-kind rules (the `kind` constants in the Track definition). Track
  `kind` is a free string, so an unknown one never fails validation; readers report it as skipped instead.

Usage: generated_constants.py schema/VERSION schema/template.schema.json
"""

import json
import re
import sys

SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def known_track_kinds(schema: dict) -> list[str]:
    kinds = [
        rule["if"]["properties"]["kind"]["const"]
        for rule in schema["$defs"]["Track"]["allOf"]
        if "const" in rule.get("if", {}).get("properties", {}).get("kind", {})
    ]
    if not kinds:
        sys.exit(
            "found no track kinds in the Track definition's allOf rules; update scripts/generated_constants.py"
        )
    return kinds


if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        version = handle.read().strip()
    if not SEMVER.match(version):
        sys.exit(f"{sys.argv[1]} must hold a semver like 0.1.0, not {version!r}")
    with open(sys.argv[2]) as handle:
        kinds = known_track_kinds(json.load(handle))
    sys.stdout.write(
        '"""What the readers know about the schema these models were generated from, by `make codegen`."""\n'
        "\n"
        f'SCHEMA_VERSION = "{version}"\n'
        f"KNOWN_TRACK_KINDS = frozenset({json.dumps(kinds)})\n"
    )
