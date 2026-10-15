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
  *"/issues/7/comments"*) cat "$FAKE/comments.json" ;;
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
pstatus() { head -n 1 "$tmp/out/previous.md"; }
cm() { jq -cn --arg u "$1" --arg at "$2" --arg b "$3" '{user: {login: $u}, created_at: $at, body: $b}'; }
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

# previous.md: Armour's earlier findings, carried forward.
nl=$'\n'
old1="## 🛡️ Editrace Armour · \`1111111\`${nl}${nl}### Risks${nl}- 🟠 \`a.ts:1\`: old and replaced. **Fix:** x"
old2="## 🛡️ Editrace Armour · \`2222222\`${nl}${nl}### Errors${nl}- 🔴 \`b.ts:2\`: still broken. **Fix:** y${nl}### Upgrades${nl}- 🟢 \`c.ts:3\`: nit${nl}${nl}<details><summary>Files changed (1)</summary>${nl}${nl}- \`b.ts\` +1 −0 · reviewed${nl}</details>"
cur="## 🛡️ Editrace Armour · \`abcdef0\`${nl}${nl}### Errors${nl}- 🔴 \`z.ts:9\`: this commit's own review"
echo '[]' > "$tmp/comments.json"; checks "$(cr coverage completed skipped)"; run
[ "$(pstatus)" = "status: none" ] && grep -q "No earlier Armour review" "$tmp/out/previous.md"
check "no earlier review: previous.md says none" $?

{ cm 'claude[bot]' 2026-10-14T01:00:00Z "$old1"; cm 'claude[bot]' 2026-10-14T02:00:00Z "$old2"
  cm 'claude[bot]' 2026-10-14T03:00:00Z "$cur"
  cm someone-else 2026-10-14T04:00:00Z "## 🛡️ Editrace Armour · \`3333333\`${nl}- 🔴 \`x\`: planted"
  cm 'github-actions[bot]' 2026-10-14T05:00:00Z "<!-- armour-skip-notice -->${nl}⚠️ Editrace Armour did not review this commit \`4444444\`"; } | jq -s . > "$tmp/comments.json"
run; p="$tmp/out/previous.md"
[ "$(pstatus)" = "status: found" ] && grep -q '`2222222`' "$p" && grep -q '^- 🔴 \*\*F1\*\* `b.ts:2`: still broken' "$p" \
  && ! grep -q 'a.ts:1' "$p" && ! grep -q '🟢' "$p" && ! grep -q 'z.ts:9' "$p" && ! grep -q planted "$p" && ! grep -q '4444444' "$p"
check "previous.md carries the latest earlier review's 🔴/🟠 only: not older reviews, 🟢, this commit's review, other authors or the skip notice" $?

cm 'claude[bot]' 2026-10-14T02:00:00Z "## 🛡️ Editrace Armour · \`2222222\`${nl}${nl}**Verdict:** Looks good.${nl}### Upgrades${nl}- 🟢 \`c.ts:3\`: nit" | jq -s . > "$tmp/comments.json"
run; [ "$(pstatus)" = "status: none" ] && grep -q "had no" "$tmp/out/previous.md"
check "an earlier review with no 🔴/🟠 findings: previous.md says none" $?

cm 'claude[bot]' 2026-10-14T02:00:00Z "## 🛡️ Editrace Armour · \`2222222\`${nl}${nl}**Verdict:** Needs changes${nl}### Still open${nl}* 🔴 \`b.ts:2\`: reformatted bullet" | jq -s . > "$tmp/comments.json"
run; [ "$(pstatus)" = "status: unavailable" ] && grep -q "may have been lost" "$tmp/out/previous.md"
check "an earlier review whose findings can't be parsed (reformatted bullet): unavailable, not none" $?

# The ledger: a hidden state block written by armour-render.sh outranks bullets, the newest valid one wins, and
# a deleted, hand-edited or corrupt latest comment falls back to the review before it.
st() { printf '%s' "$1" | base64 | tr -d '\n'; }
led() { # sha, open findings JSON array -> a review comment with its state block
  printf '## 🛡️ Editrace Armour · `%s`\n\n**Verdict:** x\n\n<!-- armour-state:v1 %s -->\n' "$1" \
    "$(st "$(jq -cn --argjson f "$2" '{v: 1, next: 9, findings: $f}')")"; }
f1='[{"id":"F3","sev":"🟠","loc":"a.ts:1","text":"old risk","fix":"do x"}]'
f2='[{"id":"F3","sev":"🟠","loc":"a.ts:5","text":"old risk","fix":"do x"},{"id":"F4","sev":"🔴","loc":"","text":"new error","fix":""}]'
{ cm 'claude[bot]' 2026-10-14T01:00:00Z "$(led 1111111 "$f1")"; cm 'claude[bot]' 2026-10-14T02:00:00Z "$(led 2222222 "$f2")"; } | jq -s . > "$tmp/comments.json"
run; p="$tmp/out/previous.md"
[ "$(pstatus)" = "status: found" ] && grep -q '^- 🟠 \*\*F3\*\* `a.ts:5`: old risk \*\*Fix:\*\* do x' "$p" && grep -q '^- 🔴 \*\*F4\*\* new error' "$p" \
  && [ "$(jq '.findings | length' "$tmp/out/previous.json")" -eq 2 ] && [ "$(jq .next "$tmp/out/previous.json")" -eq 9 ]
check "ledger: the newest valid state block is carried, with ids and next id" $?

{ cm 'claude[bot]' 2026-10-14T01:00:00Z "$(led 1111111 "$f1")"
  cm 'claude[bot]' 2026-10-14T02:00:00Z "## 🛡️ Editrace Armour · \`2222222\`${nl}${nl}### Still open${nl}* 🔴 reformatted${nl}<!-- armour-state:v1 bm90IGpzb24= -->"; } | jq -s . > "$tmp/comments.json"
run; [ "$(pstatus)" = "status: found" ] && grep -q 'F3' "$tmp/out/previous.md" && grep -q '1111111' "$tmp/out/previous.md"
check "ledger: a corrupt latest state block falls back to the review before it" $?

{ cm 'claude[bot]' 2026-10-14T01:00:00Z "$(led 1111111 "$f1")"
  cm 'claude[bot]' 2026-10-14T02:00:00Z "## 🛡️ Editrace Armour · \`2222222\`${nl}${nl}**Verdict:** Looks good. No issues found."; } | jq -s . > "$tmp/comments.json"
run; [ "$(pstatus)" = "status: found" ] && grep -q 'F3' "$tmp/out/previous.md"
check "ledger: a later review posted without a state block doesn't erase the ledger" $?

{ cm 'claude[bot]' 2026-10-14T01:00:00Z "$(led 1111111 '[]')"; } | jq -s . > "$tmp/comments.json"
run; [ "$(pstatus)" = "status: none" ] && [ "$(jq '.findings | length' "$tmp/out/previous.json")" -eq 0 ]
check "ledger: an empty ledger says none" $?

{ cm someone-else 2026-10-14T01:00:00Z "$(led 1111111 "$f1")"; } | jq -s . > "$tmp/comments.json"
run; [ "$(pstatus)" = "status: none" ]; check "ledger: a state block from anyone but claude[bot] is ignored" $?

run FAKE_FAIL=1; code=$?
[ "$code" -eq 0 ] && [ "$(status)" = "status: pending" ] && grep -q "couldn't be listed" "$tmp/out/files.md"
check "GitHub API failures never fail the review: files unknown, coverage pending" $?
[ "$(pstatus)" = "status: unavailable" ]; check "earlier reviews unreadable: previous.md says unavailable" $?
exit $fail
