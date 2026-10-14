"""Writes the reader variant of the template schema: the same schema with every `enum` constraint removed.

Writers validate against the strict schema, where an unknown enum value is an error. Readers must not fail a whole template
on a value from a newer minor version (docs/schema.md, "Versions and forward compatibility"), so `make codegen` also
generates models from this variant: enum fields become plain strings and nothing else is relaxed (patterns, ranges and
required fields still apply, and objects stay open).

Usage: reader_schema.py <schema.json> [<output.json>]   (prints to stdout when there is no output file)
"""

import json
import sys
from typing import Any


def strip_enums(node: Any) -> Any:
    if isinstance(node, list):
        return [strip_enums(item) for item in node]
    if isinstance(node, dict):
        # Only the keyword: its value is a list, unlike a property that happens to be called "enum".
        return {
            key: strip_enums(value)
            for key, value in node.items()
            if not (key == "enum" and isinstance(value, list))
        }
    return node


if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        schema = json.load(handle)
    text = json.dumps(strip_enums(schema), indent=2) + "\n"
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as handle:
            handle.write(text)
    else:
        sys.stdout.write(text)
