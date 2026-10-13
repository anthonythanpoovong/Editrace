"""Prints editrace_schema/version.py, built from schema/VERSION, for `make codegen`.

Readers compare a template's `schema_version` with the version they were generated from (docs/schema.md, "Versions and
forward compatibility"). schema/VERSION is the one place that version is written down: bump it with the schema, using
the table in docs/schema.md.

Usage: schema_version.py schema/VERSION
"""

import re
import sys

SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        version = handle.read().strip()
    if not SEMVER.match(version):
        sys.exit(f"{sys.argv[1]} must hold a semver like 0.1.0, not {version!r}")
    sys.stdout.write(
        '"""The template schema version these models were generated from, by `make codegen` from schema/VERSION."""\n'
        "\n"
        f'SCHEMA_VERSION = "{version}"\n'
    )
