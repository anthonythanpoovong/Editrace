#!/usr/bin/env bash
# Tests for coverage-decide.sh (#129): the 80% rule, the owner's exemption and the re-run, against a fake gh.
# Run: .github/scripts/test-coverage-decide.sh
set -uo pipefail
cd "$(dirname "$0")"
here=$(pwd)
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; mkdir "$tmp/bin" "$tmp/cwd"

HEAD=3333333333333333333333333333333333333333
OLD=1111111111111111111111111111111111111111
cat > "$tmp/CODEOWNERS" <<'CO'
# Keep this the single /.github/ line.
/.github/ @owner @second
CO

# A fake gh serving the PR's head SHA, reviews, the base branch's CODEOWNERS and the issue comments.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CALLS"
[ -z "${FAKE_GH_FAIL:-}" ] || { echo "gh: HTTP 500" >&2; exit 1; }
case "$*" in
  *"contents/.github/CODEOWNERS"*) [ -z "${FAKE_CO_FAIL:-}" ] || exit 1; cat "$FAKE_CODEOWNERS" ;;
  *"/reviews"*) [ -z "${FAKE_REVIEWS_FAIL:-}" ] || exit 1; cat "$FAKE_REVIEWS" ;;
  *"issues/7/comments"*"-X POST"*|*"-X POST"*"issues/7/comments"*) cat > "$FAKE_POSTED" ;;
  *"issues/7/comments"*) echo '[]' ;;
  *"pulls/7 "*) [ -z "${FAKE_HEAD_FAIL:-}" ] || exit 1; echo "$FAKE_HEAD" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$tmp/bin/gh"
export FAKE_CALLS="$tmp/calls" FAKE_REVIEWS="$tmp/reviews.json" FAKE_CODEOWNERS="$tmp/CODEOWNERS" FAKE_HEAD=$HEAD FAKE_POSTED="$tmp/posted"

# A measured summary, as coverage-gate.sh writes it.
summary() { jq -cn --arg s "$1" '{status: $s, overall: 61.5, baseline: 60.0, delta: 1.5, changed_percent: 40, changed_lines: 10, missed_lines: 6, threshold: 80,
  files: [{file: "web/lib/b.ts", percent: 40, missing: "3-8"}]}' > "$tmp/summary.json"; }
rv() { jq -cn --arg l "$1" --arg c "$2" --arg b "$3" '{id: 1, user: {login: $l, type: "User"}, state: "COMMENTED", commit_id: $c, submitted_at: "2026-10-13T10:00:00Z", body: $b}'; }
reviews() { printf '%s\n' "$@" | jq -s . > "$FAKE_REVIEWS"; }
decide() { # extra env as args
  : > "$FAKE_CALLS"; rm -rf "$tmp/out" "$tmp/gh_summary"; : > "$tmp/gh_summary"
  (cd "$tmp/cwd" && env PATH="$tmp/bin:$PATH" SUMMARY_JSON="$tmp/summary.json" REPO=o/r PR=7 OUT_DIR="$tmp/out" NO_COMMENT=1 \
    GITHUB_STEP_SUMMARY="$tmp/gh_summary" "$@" "$here/coverage-decide.sh") > "$tmp/stdout" 2>&1
}
final() { jq -r .status "$tmp/out/final.json"; }

summary pass; reviews; decide; [ $? -eq 0 ] && [ ! -s "$FAKE_CALLS" ]
check "a passing summary passes and never calls the API" $?
summary no-changed-lines; decide; [ $? -eq 0 ]; check "docs-only (no changed lines) isn't affected" $?
summary no-data; decide; [ $? -eq 0 ]; check "no coverage data: nothing to gate" $?

summary fail; reviews; decide; [ $? -eq 1 ] && [ "$(final)" = fail ] && grep -q '::error::' "$tmp/stdout"
check "an under-covered PR fails ci-ok" $?

reviews "$(rv owner $HEAD '/coverage-exempt generated glue')"
decide; [ $? -eq 0 ] && [ "$(final)" = exempt ] && grep -q '@owner' "$tmp/gh_summary" && grep -q 'generated glue' "$tmp/gh_summary" && grep -q "${HEAD:0:7}" "$tmp/gh_summary"
check "an owner's /coverage-exempt review on the head commit passes, and the job summary records reviewer, reason and SHA" $?
grep -q "reviewer @owner, reason: generated glue, commit $HEAD" "$tmp/stdout"; check "the log line records reviewer, reason and the full SHA" $?

reviews "$(rv stranger $HEAD '/coverage-exempt trust me')"
decide; [ $? -eq 1 ] && grep -q '@stranger' "$tmp/out/final.md" && grep -q '@stranger' "$tmp/stdout"
check "the same review by a non-owner is ignored; the gate fails and the message names the reviewer" $?

grep -qi 'labels' "$FAKE_CALLS"; [ $? -ne 0 ]; check "labels are never read, so a coverage-exempt label has no effect" $?

reviews "$(rv owner $OLD '/coverage-exempt old push')"
decide; [ $? -eq 1 ]; check "a review made on an older commit doesn't apply to a new push" $?

# The revoke is the later review (submitted_at orders them; GitHub can't dismiss a Comment review).
jq -cn --arg c $HEAD '[{id:1,user:{login:"owner",type:"User"},state:"COMMENTED",commit_id:$c,submitted_at:"2026-10-13T10:00:00Z",body:"/coverage-exempt why"},
                       {id:2,user:{login:"owner",type:"User"},state:"COMMENTED",commit_id:$c,submitted_at:"2026-10-13T11:00:00Z",body:"/coverage-revoke"}]' > "$FAKE_REVIEWS"
decide; [ $? -eq 1 ]; check "a later /coverage-revoke on the same commit restores the gate" $?

# The allowlist comes from the base branch through the API, never from a file in the checkout.
printf '/.github/ @stranger\n' > "$tmp/cwd/CODEOWNERS"; mkdir -p "$tmp/cwd/.github"; printf '/.github/ @stranger\n' > "$tmp/cwd/.github/CODEOWNERS"
reviews "$(rv stranger $HEAD '/coverage-exempt sneaky')"
decide; [ $? -eq 1 ]; check "editing CODEOWNERS in the PR changes nothing (the allowlist is read from the base branch)" $?
grep -q 'contents/.github/CODEOWNERS?ref=main' "$FAKE_CALLS"; check "CODEOWNERS is read at ref=main" $?
decide BASE_BRANCH=trunk; grep -q 'ref=trunk' "$FAKE_CALLS"; check "the base branch is configurable" $?
printf '/.github/ @owner @second\n/web/ @stranger\n/workers/ @stranger\n' > "$FAKE_CODEOWNERS"
decide; [ $? -eq 1 ]; check "adding area lines (#132) doesn't let their owners exempt" $?
printf '/.github/ @owner @second\n' > "$FAKE_CODEOWNERS"

# Fail closed on any API error.
reviews "$(rv owner $HEAD '/coverage-exempt why')"
decide FAKE_GH_FAIL=1; [ $? -eq 1 ]; check "fail closed: every API call fails" $?
decide FAKE_REVIEWS_FAIL=1; [ $? -eq 1 ]; check "fail closed: the reviews can't be read" $?
decide FAKE_HEAD_FAIL=1; [ $? -eq 1 ]; check "fail closed: the head commit can't be read" $?
decide FAKE_CO_FAIL=1; [ $? -eq 1 ]; check "fail closed: CODEOWNERS can't be read" $?
decide REPO= PR=; [ $? -eq 1 ]; check "fail closed: no repo or PR number" $?
printf '/.github/ @owner\n/.github/ @owner\n' > "$FAKE_CODEOWNERS"; decide; [ $? -eq 1 ]; check "fail closed: a duplicated /.github/ line" $?
printf '/docs/ @owner\n' > "$FAKE_CODEOWNERS"; decide; [ $? -eq 1 ]; check "fail closed: no /.github/ line" $?
printf '/.github/ @owner @second\n' > "$FAKE_CODEOWNERS"
jq '.[0].user.type = "Bot"' "$FAKE_REVIEWS" > "$tmp/r3" && mv "$tmp/r3" "$FAKE_REVIEWS"; decide; [ $? -eq 1 ]; check "fail closed: a bot reviewer" $?
echo 'garbage' > "$tmp/summary.json"; decide; [ $? -eq 1 ]; check "fail closed: an unreadable summary" $?

# The re-run: nothing changes between runs except the PR's reviews.
summary fail; reviews
decide; first=$?
reviews "$(rv owner $HEAD '/coverage-exempt added after the first failure')"
decide; second=$?
[ "$first" -eq 1 ] && [ "$second" -eq 0 ] && [ "$(jq -r .status "$tmp/summary.json")" = fail ]
check "re-running ci-ok picks up a review submitted after the failure (same summary, no new push)" $?

# The sticky comment is refreshed with the final result.
reviews "$(rv owner $HEAD '/coverage-exempt for the comment')"
: > "$FAKE_CALLS"; rm -f "$FAKE_POSTED"
(cd "$tmp/cwd" && env PATH="$tmp/bin:$PATH" SUMMARY_JSON="$tmp/summary.json" REPO=o/r PR=7 OUT_DIR="$tmp/out" "$here/coverage-decide.sh") > "$tmp/stdout" 2>&1
[ $? -eq 0 ] && jq -r .body "$FAKE_POSTED" | head -n 1 | grep -q 'editrace-coverage' && jq -r .body "$FAKE_POSTED" | grep -q 'exempted this commit'
check "the sticky comment is updated to show the exemption" $?
exit $fail
