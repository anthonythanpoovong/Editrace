#!/usr/bin/env bash
# Every fixture in schema/examples/invalid/ must FAIL validation, and for the reason
# listed in EXPECTED. Guards against the schema silently becoming permissive.
# Needs check-jsonschema on PATH (pip install check-jsonschema).
set -uo pipefail
cd "$(dirname "$0")"

dir=examples/invalid
fail=0
declare -a listed=()

while IFS='|' read -r file expected; do
  case "$file" in ''|'#'*) continue ;; esac
  listed+=("$file")
  if [ ! -f "$dir/$file" ]; then
    echo "FAIL $file: listed in EXPECTED but missing"; fail=1; continue
  fi
  if out=$(check-jsonschema --schemafile template.schema.json "$dir/$file" 2>&1); then
    echo "FAIL $file: validated, but it should be rejected"; fail=1; continue
  fi
  if [[ "$out" != *"$expected"* ]]; then
    echo "FAIL $file: rejected for the wrong reason (expected: $expected)"
    echo "$out" | sed 's/^/    /'; fail=1; continue
  fi
  echo "ok   $file"
done < "$dir/EXPECTED"

# Every fixture must have an expectation, so a new one can't be added unchecked.
for f in "$dir"/*.json; do
  name=$(basename "$f")
  printf '%s\n' "${listed[@]}" | grep -qxF "$name" || { echo "FAIL $name: no entry in EXPECTED"; fail=1; }
done

exit $fail
