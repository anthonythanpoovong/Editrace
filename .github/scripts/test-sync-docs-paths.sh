#!/usr/bin/env bash
# Tests for sync-docs-paths.sh. Run: .github/scripts/test-sync-docs-paths.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
areas() { ./sync-docs-paths.sh; }

out=$(printf '%s\n' README.md docs/plan.md web/app/page.tsx | areas)
[ -z "$out" ]; check "ordinary files match nothing" $?

out=$(printf '%s\n' schema/template.schema.json | areas)
[ "$out" = '- the template schema (`schema/template.schema.json`)' ]; check "the schema file is a large change" $?

out=$(printf '%s\n' schema/examples/01-simple-reel-30fps.json schema/README.md | areas)
[ -z "$out" ]; check "schema examples and README alone are not" $?

out=$(printf '%s\n' docs/decisions/0002-time.md | areas)
[ "$out" = '- an ADR (`docs/decisions/`)' ]; check "an ADR file matches" $?

out=$(printf '%s\n' docs/decisions/README.md docs/decisions/0000-template.md docs/epics/README.md docs/epics/TEMPLATE.md | areas)
[ -z "$out" ]; check "the ADR/epic index and templates do not" $?

out=$(printf '%s\n' docs/epics/marketing-launch.md | areas)
[ "$out" = '- an epic (`docs/epics/`)' ]; check "an epic file matches" $?

out=$(printf '%s\n' .claude/skills/schema-change/SKILL.md .github/workflows/ci.yml | areas)
[ "$(wc -l <<<"$out" | tr -d ' ')" = 2 ] && grep -q 'skills' <<<"$out" && grep -q 'workflows' <<<"$out"
check "skills and workflows match" $?

out=$(printf '%s\n' .github/workflows/a.yml .github/workflows/b.yml docs/decisions/0003-x.md | areas)
[ "$(wc -l <<<"$out" | tr -d ' ')" = 2 ]; check "each area is listed once, however many files hit it" $?

out=$(printf '%s\n' 'docs/decisions/$(touch pwned).md' '.claude/skills/a b/SKILL.md' | areas)
[ "$(wc -l <<<"$out" | tr -d ' ')" = 2 ] && [ ! -e pwned ] && [ ! -e 'a b' ]
check "odd file names are only pattern-matched, never run" $?

out=$(printf '%s' "" | areas)
[ -z "$out" ]; check "no files at all is fine" $?

exit $fail
