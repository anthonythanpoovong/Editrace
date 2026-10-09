#!/usr/bin/env bash
# Every property and type in template.schema.json must appear in docs/schema.md, so a field
# can't be added to the schema without being explained. Needs python3 (stdlib only).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, re, sys

schema = json.load(open("schema/template.schema.json"))
doc = open("docs/schema.md").read()

props, types = set(), set(schema.get("$defs", {}))

def walk(node):
    if isinstance(node, dict):
        for name, sub in node.get("properties", {}).items():
            props.add(name)
            walk(sub)
        for key, sub in node.items():
            if key != "properties":
                walk(sub)
    elif isinstance(node, list):
        for sub in node:
            walk(sub)

walk(schema)

def documented(name):
    # `name`, or a dotted/indexed path containing it, e.g. `lines[].words[].text`
    return re.search(r"`[\w.\[\]]*" + re.escape(name) + r"[\w.\[\]]*`", doc) is not None

missing = sorted(f"field `{n}`" for n in props if not documented(n))
missing += sorted(f"type `{t}`" for t in types if t not in doc)
if missing:
    print("docs/schema.md is missing:")
    for m in missing:
        print("  -", m)
    sys.exit(1)
print(f"ok: {len(props)} fields and {len(types)} types documented")
PY
