#!/usr/bin/env bash
# Tests for coverage-exemption.sh (#129). Run: .github/scripts/test-coverage-exemption.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

SHA=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
cat > "$tmp/CODEOWNERS" <<'CO'
# comment
/.github/ @owner @Second @third-person @org/team someone@example.com
/docs/decisions/ @other
CO
# review <id> <login> <type> <state> <commit> <time> <body>
rv() { jq -cn --argjson id "$1" --arg l "$2" --arg t "$3" --arg s "$4" --arg c "$5" --arg at "$6" --arg b "$7" \
  '{id: $id, user: {login: $l, type: $t}, state: $s, commit_id: $c, submitted_at: $at, body: $b}'; }
run() { # reviews as args (JSON objects); optional CO env for the CODEOWNERS file
  printf '%s\n' "$@" | jq -s . > "$tmp/reviews.json"
  REVIEWS_FILE="$tmp/reviews.json" CODEOWNERS_FILE="${CO:-$tmp/CODEOWNERS}" HEAD_SHA="${SHA_OVERRIDE-$SHA}" ./coverage-exemption.sh
}
exempt() { jq -r .exempt <<<"$1"; }

out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt generated glue, tested upstream')")
[ "$(exempt "$out")" = true ] && [ "$(jq -r .reviewer <<<"$out")" = @owner ] && [ "$(jq -r .reason <<<"$out")" = "generated glue, tested upstream" ] && [ "$(jq -r .sha <<<"$out")" = "$SHA" ]
check "an owner's /coverage-exempt comment review on the head commit exempts, and records reviewer, reason and SHA" $?

out=$(run "$(rv 1 stranger User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt trust me')")
[ "$(exempt "$out")" = false ] && jq -r '.notes[]' <<<"$out" | grep -q '@stranger'
check "the same review by a non-owner is ignored, and the note names the reviewer" $?

out=$(run "$(rv 1 owner User COMMENTED $OLD 2026-10-13T10:00:00Z '/coverage-exempt old push')")
[ "$(exempt "$out")" = false ]; check "a review on an older commit does not apply (a new push ends the exemption)" $?

out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')" "$(rv 2 owner User COMMENTED $SHA 2026-10-13T11:00:00Z '/coverage-revoke changed my mind')")
[ "$(exempt "$out")" = false ]; check "a later /coverage-revoke on the same commit restores the gate" $?

out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-revoke')" "$(rv 2 owner User COMMENTED $SHA 2026-10-13T11:00:00Z '/coverage-exempt again, with a reason')")
[ "$(exempt "$out")" = true ]; check "an exemption after a revoke applies again (the latest wins)" $?

out=$(run "$(rv 2 owner User COMMENTED $SHA 2026-10-13T11:00:00Z '/coverage-exempt why')" "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-revoke')")
[ "$(exempt "$out")" = true ]; check "order is by submitted_at, not by position in the list" $?

out=$(run "$(rv 1 owner User DISMISSED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "a dismissed review does not count" $?
out=$(run "$(jq -c 'del(.submitted_at) | .state = "PENDING"' <<<"$(rv 1 owner User PENDING $SHA x '/coverage-exempt why')")")
[ "$(exempt "$out")" = false ]; check "a pending (unsubmitted) review does not count" $?

out=$(run "$(rv 1 owner Bot COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "a bot author fails closed, even with an allowlisted login" $?
out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt')")
[ "$(exempt "$out")" = false ] && jq -r '.notes[]' <<<"$out" | grep -q 'no reason'
check "an exemption with no reason is ignored" $?
out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z 'please /coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "the command must be at the start of the review body" $?
out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exemptions are bad')")
[ "$(exempt "$out")" = false ]; check "the command must be a whole word, not a prefix of other text" $?
out=$(run "$(rv 1 owner User APPROVED $SHA 2026-10-13T10:00:00Z '/coverage-exempt approved too')")
[ "$(exempt "$out")" = true ]; check "an approving review with the command also works" $?
out=$(run "$(rv 1 OWNER User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = true ]; check "logins compare case-insensitively" $?
out=$(run "$(rv 1 Second User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = true ]; check "every plain @username on the /.github/ line may exempt" $?
out=$(run "$(rv 1 team User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')" "$(rv 2 example User COMMENTED $SHA 2026-10-13T10:05:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "team and email entries are ignored, not expanded" $?
out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z $'/coverage-exempt line one\n\tline two \x01 end')")
[ "$(jq -r .reason <<<"$out")" = "line one line two end" ]; check "the reason is one line without control characters" $?
long=$(printf 'x%.0s' $(seq 1 300)); out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z "/coverage-exempt $long")")
[ "$(jq -r '.reason | length' <<<"$out")" -eq 200 ]; check "the reason is cut to 200 characters" $?

# A non-owner's later review does not revoke the owner's exemption
out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')" "$(rv 2 stranger User COMMENTED $SHA 2026-10-13T11:00:00Z '/coverage-revoke')")
[ "$(exempt "$out")" = true ]; check "a non-owner's /coverage-revoke does not cancel the owner's exemption" $?
out=$(run)
[ "$(exempt "$out")" = false ]; check "no reviews at all: not exempt" $?

# --- fail closed ---
printf '# nothing here\n/docs/ @owner\n' > "$tmp/none"; out=$(CO="$tmp/none" run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ] && jq -r '.notes[]' <<<"$out" | grep -q 'no /.github/ line'
check "fail closed: a missing /.github/ line" $?
printf '/.github/ @owner\n/.github/ @owner\n' > "$tmp/dup"; out=$(CO="$tmp/dup" run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ] && jq -r '.notes[]' <<<"$out" | grep -q 'more than one'
check "fail closed: a duplicated /.github/ line" $?
printf '/.github/ @org/team me@example.com\n' > "$tmp/teams"; out=$(CO="$tmp/teams" run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ] && jq -r '.notes[]' <<<"$out" | grep -q 'no plain @username'
check "fail closed: a /.github/ line with no plain usernames" $?
printf '/.github/workflows/ @owner\n/.github/scripts/ @owner\n' > "$tmp/sub"; out=$(CO="$tmp/sub" run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "only the pattern exactly /.github/ counts, not sub-folders" $?
printf '/docs/ @owner\n/.github/ @stranger\n' > "$tmp/last"; out=$(CO="$tmp/last" run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "an area line elsewhere does not change who may exempt" $?
printf '/.github/ @owner\n/web/ @stranger\n/workers/ @stranger\n' > "$tmp/area"; out=$(CO="$tmp/area" run "$(rv 1 stranger User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "adding area lines (#132) does not let their owners exempt" $?

echo 'not json' > "$tmp/bad.json"
REVIEWS_FILE="$tmp/bad.json" CODEOWNERS_FILE="$tmp/CODEOWNERS" HEAD_SHA=$SHA ./coverage-exemption.sh | jq -e '.exempt == false' > /dev/null
check "fail closed: unreadable reviews JSON" $?
REVIEWS_FILE="$tmp/missing.json" CODEOWNERS_FILE="$tmp/CODEOWNERS" HEAD_SHA=$SHA ./coverage-exemption.sh | jq -e '.exempt == false' > /dev/null
check "fail closed: no reviews file (the API call failed)" $?
echo '{"message":"Not Found"}' > "$tmp/obj.json"
REVIEWS_FILE="$tmp/obj.json" CODEOWNERS_FILE="$tmp/CODEOWNERS" HEAD_SHA=$SHA ./coverage-exemption.sh | jq -e '.exempt == false' > /dev/null
check "fail closed: an API error object instead of a review list" $?
REVIEWS_FILE="$tmp/reviews.json" CODEOWNERS_FILE="$tmp/nofile" HEAD_SHA=$SHA ./coverage-exemption.sh | jq -e '.exempt == false' > /dev/null
check "fail closed: CODEOWNERS unreadable" $?
SHA_OVERRIDE="" out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "fail closed: no head SHA" $?
SHA_OVERRIDE="not-a-sha" out=$(run "$(rv 1 owner User COMMENTED $SHA 2026-10-13T10:00:00Z '/coverage-exempt why')")
[ "$(exempt "$out")" = false ]; check "fail closed: a malformed head SHA" $?

exit $fail
