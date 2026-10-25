#!/usr/bin/env bash
# Tests for discord-review-announced.sh. Run: .github/scripts/test-discord-review-announced.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
bot=github-actions[bot]
marker='Review requested in Discord. <!-- discord-review-message:1234567890 -->'
comment() { jq -nc --arg l "$1" --arg b "$2" '{login: $l, body: $b}'; }
announced() { ./discord-review-announced.sh; } # reads stdin

comment "$bot" "$marker" | announced
check "the bot's marker comment means announced" $?

{ comment alice "looks good"; comment "$bot" "Coverage: pass"; comment "$bot" "$marker"; comment bob "thanks"; } | announced
check "the marker is found among other comments" $?

{ comment alice "ok"; comment "$bot" "Coverage: pass"; } | announced
[ $? -eq 1 ]; check "no marker means not announced" $?

: | announced
[ $? -eq 1 ]; check "a PR with no comments is not announced" $?

comment alice "$marker" | announced
[ $? -eq 1 ]; check "a person quoting the marker does not count" $?

comment "$bot" 'Review requested. <!-- discord-review-message: -->' | announced
[ $? -eq 1 ]; check "a marker with no message id does not count" $?

comment "$bot" 'Review requested. <!-- discord-review-message:abc -->' | announced
[ $? -eq 1 ]; check "a marker with a non-numeric id does not count" $?

comment "$bot" 'Mentions discord-review-message: in prose, no comment marker' | announced
[ $? -eq 1 ]; check "the bare word without the marker syntax does not count" $?

comment "$bot" $'Line one\n\nReview requested in Discord. <!-- discord-review-message:42 -->\nLine four' | announced
check "a marker inside a multi-line body is found" $?

jq -nc --arg l "$bot" '{login: $l, body: null}' | announced
[ $? -eq 1 ]; check "a comment with a null body is skipped, not an error" $?

echo 'not json' | announced > /dev/null 2>&1
[ $? -ge 2 ]; check "unreadable input is an error, never 'not announced'" $?

exit $fail
