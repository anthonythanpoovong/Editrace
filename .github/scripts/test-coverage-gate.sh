#!/usr/bin/env bash
# Tests for coverage-gate.sh (#129), the measuring half, against a throwaway git repo and the real diff-cover.
# The pass/fail decision and the exemption are tested in test-coverage-decide.sh.
# Needs diff-cover on PATH (pip install diff-cover). Run: .github/scripts/test-coverage-gate.sh
set -uo pipefail
cd "$(dirname "$0")"
here=$(pwd)
command -v diff-cover > /dev/null || { echo "FAIL diff-cover is not installed (pip install diff-cover)"; exit 1; }
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo" && cd "$repo" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
mkdir -p web/lib web/lib/generated .github pkg
printf 'line1\n' > README.md
printf 'export const a = 1;\n' > web/lib/a.ts
printf '# comment\n/.github/ @owner\n' > .github/CODEOWNERS
git add -A && git commit -q -m base

lcov() { # file, covered lines (space-separated), uncovered lines  -> lcov record on stdout
  echo "SF:$1"; local l; for l in $2; do echo "DA:$l,1"; done; for l in $3; do echo "DA:$l,0"; done
  echo "LF:$(( $(wc -w <<<"$2") + $(wc -w <<<"$3") ))"; echo "LH:$(wc -w <<<"$2")"; echo end_of_record
}
gate() { # extra env as args; output in $tmp/out
  rm -rf "$tmp/out"
  env COMPARE_BRANCH=main OUT_DIR="$tmp/out" EVENT_NAME=pull_request "$@" "$here/coverage-gate.sh" > "$tmp/stdout" 2>&1
}
st() { jq -r .status "$tmp/out/summary.json"; }

newbranch() { git checkout -q main && git checkout -q -B pr main; }

# --- web: lcov paths are relative to web/ ---
newbranch; printf 'export const b = 1;\nexport const c = 2;\n' > web/lib/b.ts; git add -A; git commit -q -m b
lcov lib/b.ts "" "1 2" > "$tmp/web.info"
gate WEB_LCOV="$tmp/web.info"; rc=$?
[ "$rc" -eq 0 ] && [ "$(st)" = fail ] && jq -e '.changed_percent == 0' "$tmp/out/summary.json" > /dev/null && grep -q 'web/lib/b.ts' "$tmp/out/summary.md"
check "a PR that adds untested code fails, and the comment names the file (web/ prefix applied)" $?
lcov lib/b.ts "1 2" "" > "$tmp/web.info"
gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = pass ] && jq -e '.changed_percent == 100' "$tmp/out/summary.json" > /dev/null
check "adding tests makes the same change pass" $?

newbranch; printf 'l1\nl2\nl3\nl4\nl5\n' > web/lib/b.ts; git add -A; git commit -q -m b
lcov lib/b.ts "1 2 3 4" "5" > "$tmp/web.info"; gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = pass ]
check "exactly 80% of changed lines passes" $?
lcov lib/b.ts "1 2 3" "4 5" > "$tmp/web.info"; gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = fail ]
check "60% is recorded as fail" $?
gate WEB_LCOV="$tmp/web.info" FAIL_UNDER=50; [ $? -eq 0 ]; check "the threshold can be changed" $?
gate WEB_LCOV="$tmp/web.info" FAIL_UNDER=abc; [ $? -eq 2 ]; check "a non-numeric threshold is rejected" $?

# A percentage just under the threshold must fail, not be rounded up to it: 1999 of 2500 lines is 79.96%.
newbranch; seq 1 2500 > web/lib/b.ts; git add -A; git commit -q -m big
{ echo "SF:lib/b.ts"; for i in $(seq 1 1999); do echo "DA:$i,1"; done; for i in $(seq 2000 2500); do echo "DA:$i,0"; done; echo LF:2500; echo LH:1999; echo end_of_record; } > "$tmp/web.info"
gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = fail ] && grep -q '79.9%' "$tmp/out/summary.md"
check "79.96% fails and is shown as 79.9%, not rounded up to 80" $?

# --- docs-only and non-source changes are not affected ---
newbranch; printf 'line1\nmore docs\n' > README.md; git add -A; git commit -q -m docs
lcov lib/a.ts "1" "" > "$tmp/web.info"; gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = no-changed-lines ]
check "a docs-only PR is not affected" $?
newbranch; mkdir -p supabase/migrations; printf 'create table t (id int);\n' > supabase/migrations/1.sql; git add -A; git commit -q -m sql
gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = no-changed-lines ]
check "a SQL-only PR is outside the gate" $?

# --- generated code is excluded ---
newbranch; printf 'g1\ng2\n' > web/lib/generated/t.ts; git add -A; git commit -q -m gen
lcov lib/generated/t.ts "" "1 2" > "$tmp/web.info"
gate WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = fail ]; check "without an exclude, uncovered generated code fails" $?
gate WEB_LCOV="$tmp/web.info" EXCLUDES="**/lib/generated/** **/pkg/gen.py"; [ $? -eq 0 ] && [ "$(st)" = no-changed-lines ]
check "generated code is excluded by EXCLUDES" $?

# --- python: Cobertura XML paths are relative to the repo root ---
newbranch; printf 'p1\np2\np3\n' > pkg/mod.py; git add -A; git commit -q -m py
cat > "$tmp/cov.xml" <<'XML'
<?xml version="1.0" ?>
<coverage version="7" lines-valid="3" lines-covered="1" line-rate="0.33">
  <sources><source>.</source></sources>
  <packages><package name="pkg"><classes>
    <class name="mod.py" filename="pkg/mod.py"><lines>
      <line number="1" hits="1"/><line number="2" hits="0"/><line number="3" hits="0"/>
    </lines></class>
  </classes></package></packages>
</coverage>
XML
gate PY_XML="$tmp/cov.xml"; [ $? -eq 0 ] && [ "$(st)" = fail ] && grep -q 'pkg/mod.py' "$tmp/out/summary.md"
check "python: an under-covered changed file fails" $?
[ "$(jq -r .overall "$tmp/out/summary.json")" = "33.3" ]; check "python: the overall percent comes from the report" $?

# --- overall and change vs main, web + python together ---
lcov lib/a.ts "1" "" > "$tmp/web.info"
echo '{"overall": 30.0}' > "$tmp/base.json"
gate WEB_LCOV="$tmp/web.info" PY_XML="$tmp/cov.xml" BASELINE_JSON="$tmp/base.json"
[ "$(jq -r .overall "$tmp/out/summary.json")" = "50.0" ] && [ "$(jq -r .delta "$tmp/out/summary.json")" = "20.0" ] && grep -q '+20.0 points' "$tmp/out/summary.md"
check "overall % sums both reports, and the change vs main is reported" $?
gate WEB_LCOV="$tmp/web.info" PY_XML="$tmp/cov.xml" BASELINE_JSON="$tmp/missing.json"; [ "$(jq -r .delta "$tmp/out/summary.json")" = null ] && grep -q 'n/a' "$tmp/out/summary.md"
check "no baseline: the change vs main is n/a, not an error" $?

# One PR changing both web and python: the two diff-cover runs add up (2 web lines covered + 3 python lines, 1 covered).
printf 'w1\nw2\n' > web/lib/w.ts; git add -A; git commit -q -m both
lcov lib/w.ts "1 2" "" > "$tmp/web.info"
gate WEB_LCOV="$tmp/web.info" PY_XML="$tmp/cov.xml"; rc=$?
[ "$rc" -eq 0 ] && [ "$(st)" = fail ] && [ "$(jq -r .changed_lines "$tmp/out/summary.json")" = 5 ] && [ "$(jq -r .missed_lines "$tmp/out/summary.json")" = 2 ] && jq -e '.changed_percent == 60' "$tmp/out/summary.json" > /dev/null
check "web and python changes in one PR are added up (3 of 5 changed lines covered = 60%)" $?

# --- events and missing data ---
gate EVENT_NAME=push WEB_LCOV="$tmp/web.info"; [ $? -eq 0 ] && [ "$(st)" = reported ]
check "a push event only reports the overall number" $?
gate; [ $? -eq 0 ] && [ "$(st)" = no-data ]; check "no coverage reports: nothing to gate, passes" $?
gate WEB_LCOV="$tmp/web.info" COMPARE_BRANCH=does-not-exist; [ $? -eq 1 ]
check "if diff-cover itself fails, the gate fails closed" $?

# --- the markdown ---
gate WEB_LCOV="$tmp/web.info"; head -n 1 "$tmp/out/summary.md" | grep -q '^<!-- editrace-coverage -->$'; check "the summary starts with the marker the sticky comment is found by" $?
exit $fail
