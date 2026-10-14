#!/usr/bin/env bash
# Tests for armour-inputs.sh (#125), against a fake gh. Run: .github/scripts/test-armour-inputs.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; mkdir "$tmp/bin"

# A fake gh: serves the PR's files, the commit's check runs, its workflow runs, CI's artifacts and the
# coverage-summary zip from files in $tmp, or fails when FAKE_FAIL is set.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ -z "${FAKE_FAIL:-}" ] || exit 1
case "$*" in
  *"/pulls/7/files"*) cat "$FAKE/files.json" ;;
  *"/commits/abcdef0123/check-runs"*) cat "$FAKE/checks.json" ;;
  *"/actions/runs?head_sha=abcdef0123"*) cat "$FAKE/runs.json" ;;
  *"/actions/runs/42/artifacts"*) cat "$FAKE/artifacts.json" ;;
  *"/actions/artifacts/9/zip"*) cat "$FAKE/summary.zip" ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$tmp/bin/gh"
export FAKE="$tmp"
run() {
  rm -rf "$tmp/out"
  env PATH="$tmp/bin:$PATH" REPO=o/r PR=7 SHA=abcdef0123 OUT="$tmp/out" WAIT_SECONDS=0 POLL_SECONDS=0 "$@" \
    ./armour-inputs.sh > "$tmp/log" 2>&1
}
checks() { jq -n --argjson r "[$1]" '{check_runs: $r}' > "$tmp/checks.json"; }
cr() { jq -cn --arg n "$1" --arg s "$2" --arg c "$3" '{name: $n, status: $s, conclusion: (if $c == "" then null else $c end), started_at: "2026-10-14T10:00:00Z"}'; }
status() { head -n 1 "$tmp/out/coverage.md"; }
# CI's run for this commit (42, plus an older run of another workflow) and its coverage-summary artifact (9).
jq -n '{workflow_runs: [
  {id: 41, path: ".github/workflows/deploy.yml", created_at: "2026-10-14T10:00:00Z"},
  {id: 40, path: ".github/workflows/ci.yml", created_at: "2026-10-14T09:00:00Z"},
  {id: 42, path: ".github/workflows/ci.yml", created_at: "2026-10-14T10:00:00Z"}]}' > "$tmp/runs.json"
jq -n '{artifacts: [{id: 9, name: "coverage-summary", expired: false}]}' > "$tmp/artifacts.json"
summary_zip() { mkdir -p "$tmp/z"; printf '%s' "$1" > "$tmp/z/summary.json"; rm -f "$tmp/summary.zip"; (cd "$tmp/z" && zip -q ../summary.zip summary.json); }

jq -n '[
  {filename: "web/lib/a.ts", status: "modified", additions: 3, deletions: 1, changes: 4, patch: "@@"},
  {filename: "web/package-lock.json", status: "modified", additions: 90, deletions: 2, changes: 92, patch: "@@"},
  {filename: "web/lib/generated/template.ts", status: "added", additions: 40, deletions: 0, changes: 40, patch: "@@"},
  {filename: "docs/logo.png", status: "added", additions: 0, deletions: 0, changes: 0},
  {filename: "web/lib/b.ts", previous_filename: "web/lib/old-b.ts", status: "renamed", additions: 0, deletions: 0, changes: 0},
  {filename: "old.py", status: "removed", additions: 0, deletions: 12, changes: 12}
]' > "$tmp/files.json"
checks "$(cr coverage completed skipped)"; run
f="$tmp/out/files.md"
head -n 1 "$f" | grep -q '`abcdef0`: 6' \
  && grep -q '^- `web/lib/a.ts` +3 −1 modified · review$' "$f" \
  && grep -q 'package-lock.json.*skip: lock file' "$f" \
  && grep -q 'lib/generated/template.ts.*skip: generated' "$f" \
  && grep -q 'logo.png.*skip: no diff' "$f" \
  && grep -q '^- `web/lib/b.ts` +0 −0 renamed from `web/lib/old-b.ts` · review$' "$f" \
  && grep -q '^- `old.py` +0 −12 removed · review$' "$f"
check "files.md lists every file with +/−, skips lock, generated and binary files, and shows renames" $?

[ "$(status)" = "status: none" ]; check "coverage job skipped with no failed tests: no coverage data" $?

checks "$(cr web completed failure),$(cr coverage completed skipped)"; run
[ "$(status)" = "status: not-measured" ] && grep -q "tests failed" "$tmp/out/coverage.md"
check "coverage job skipped because the tests failed: not measured, and says why" $?

summary_zip '{"status":"pass","overall":84.25,"baseline":84.5,"delta":-0.25,"changed_percent":91.0,"changed_lines":44,"missed_lines":4,"threshold":80,"files":[]}'
checks "$(cr coverage completed success)"; run
c="$tmp/out/coverage.md"
[ "$(status)" = "status: measured" ] && grep -q '91.0%' "$c" && grep -q '84.2%' "$c" && grep -q -- '-0.2 points' "$c" \
  && ! grep -q 'editrace-coverage' "$c" && [ ! -e "$tmp/out/summary.json" ] && [ ! -e "$tmp/out/summary.zip" ]
check "a finished coverage job: this commit's CI summary, rendered like CI's comment" $?

jq -n '{artifacts: []}' > "$tmp/artifacts.json"; run
[ "$(status)" = "status: pending" ]; check "no coverage-summary artifact for this commit: pending" $?
jq -n '{artifacts: [{id: 9, name: "coverage-summary", expired: false}]}' > "$tmp/artifacts.json"

checks "$(cr coverage completed failure)"; run
[ "$(status)" = "status: not-measured" ]; check "the coverage job itself failed: not measured" $?

checks "$(cr web completed success),$(cr ci-ok completed success)"; run
[ "$(status)" = "status: none" ]; check "CI finished with no coverage job: no coverage data" $?

checks "$(cr web in_progress '')"; run
[ "$(status)" = "status: pending" ] && grep -q "hadn't finished" "$tmp/out/coverage.md"
check "coverage job not started before the wait ends: pending" $?

checks "$(cr coverage in_progress '')"; run
[ "$(status)" = "status: pending" ]; check "coverage job still running when the wait ends: pending" $?

run FAKE_FAIL=1; code=$?
[ "$code" -eq 0 ] && [ "$(status)" = "status: pending" ] && grep -q "couldn't be listed" "$tmp/out/files.md"
check "GitHub API failures never fail the review: files unknown, coverage pending" $?
exit $fail
