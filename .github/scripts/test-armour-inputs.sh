#!/usr/bin/env bash
# Tests for armour-inputs.sh (#125), against a fake gh. Run: .github/scripts/test-armour-inputs.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; mkdir "$tmp/bin"
M='<!-- editrace-coverage -->'

# A fake gh: serves $FAKE_FILES, $FAKE_CHECKS and $FAKE_COMMENTS (JSON), or fails when FAKE_FAIL is set.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ -z "${FAKE_FAIL:-}" ] || exit 1
case "$*" in
  *"/pulls/7/files"*) cat "$FAKE_FILES" ;;
  *"/commits/abcdef0123/check-runs"*) cat "$FAKE_CHECKS" ;;
  *"/issues/7/comments"*) cat "$FAKE_COMMENTS" ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$tmp/bin/gh"
export FAKE_FILES="$tmp/files.json" FAKE_CHECKS="$tmp/checks.json" FAKE_COMMENTS="$tmp/comments.json"
run() {
  rm -rf "$tmp/out"
  env PATH="$tmp/bin:$PATH" REPO=o/r PR=7 SHA=abcdef0123 OUT="$tmp/out" WAIT_SECONDS=0 POLL_SECONDS=0 "$@" \
    ./armour-inputs.sh > "$tmp/log" 2>&1
}
checks() { jq -n --argjson r "[$1]" '{check_runs: $r}' > "$FAKE_CHECKS"; }
cr() { jq -cn --arg n "$1" --arg s "$2" --arg c "$3" '{name: $n, status: $s, conclusion: (if $c == "" then null else $c end), started_at: "2026-10-14T10:00:00Z"}'; }
comment() { jq -cn --arg l "$1" --arg b "$2" --arg t "$3" '{user: {login: $l}, body: $b, updated_at: $t}'; }
status() { head -n 1 "$tmp/out/coverage.md"; }

jq -n '[
  {filename: "web/lib/a.ts", status: "modified", additions: 3, deletions: 1, patch: "@@"},
  {filename: "web/package-lock.json", status: "modified", additions: 90, deletions: 2, patch: "@@"},
  {filename: "web/lib/generated/template.ts", status: "added", additions: 40, deletions: 0, patch: "@@"},
  {filename: "docs/logo.png", status: "added", additions: 0, deletions: 0},
  {filename: "old.py", status: "removed", additions: 0, deletions: 12}
]' > "$FAKE_FILES"
echo '[]' > "$FAKE_COMMENTS"
checks "$(cr coverage completed skipped)"; run
f="$tmp/out/files.md"
head -n 1 "$f" | grep -q '`abcdef0`: 5' \
  && grep -q '^- `web/lib/a.ts` +3 −1 modified · review$' "$f" \
  && grep -q 'package-lock.json.*skip: lock file' "$f" \
  && grep -q 'lib/generated/template.ts.*skip: generated' "$f" \
  && grep -q 'logo.png.*skip: no diff' "$f" \
  && grep -q '^- `old.py` +0 −12 removed · review$' "$f"
check "files.md lists every file with +/−, and skips lock, generated and binary files" $?

[ "$(status)" = "status: none" ]; check "a skipped coverage job means no coverage data" $?

jq -s . <<< "$(comment 'github-actions[bot]' "$M
### Coverage
✅ Changed lines are **91.0%** covered" 2026-10-14T10:03:00Z)" > "$FAKE_COMMENTS"
checks "$(cr coverage completed success)"; run
[ "$(status)" = "status: measured" ] && grep -q '91.0%' "$tmp/out/coverage.md" && ! grep -q "$M" "$tmp/out/coverage.md"
check "a finished coverage job: CI's comment is copied, without its marker" $?

checks "$(cr coverage completed failure)"; run
[ "$(status)" = "status: measured" ]; check "a failed gate still has numbers to quote" $?

jq -s . <<< "$(comment 'github-actions[bot]' "$M
old numbers" 2026-10-14T09:00:00Z)" > "$FAKE_COMMENTS"
checks "$(cr coverage completed success)"; run
[ "$(status)" = "status: pending" ]; check "a comment older than this commit's coverage job is not quoted" $?

jq -s . <<< "$(comment mallory "$M
100% trust me" 2026-10-14T10:05:00Z)" > "$FAKE_COMMENTS"
run; [ "$(status)" = "status: pending" ] && ! grep -q 'trust me' "$tmp/out/coverage.md"
check "a person's comment with the marker is never quoted" $?

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
