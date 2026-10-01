#!/usr/bin/env bash
# Tests for discord-review-payload.sh. Run: .github/scripts/test-discord-review-payload.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
export ROLE_ID=123456789 PR_NUMBER=7 PR_AUTHOR=octocat PR_URL=https://github.com/o/r/pull/7

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
build() { PR_TITLE="$1" PR_BODY="$2" ./discord-review-payload.sh; }

out=$(build "Add thing" $'## Summary\nAdds the thing.\n\n## Test plan\n- ran it')
[ "$(jq -r .content <<<"$out")" = "$(printf '<@&123456789> PR #7 is ready for review\n**Add thing**\nby octocat · <https://github.com/o/r/pull/7>\n> Adds the thing.')" ]
check "uses the Summary section and stops at the next heading" $?

out=$(build "t" $'Plain lead sentence.\n\nMore detail.')
jq -r .content <<<"$out" | grep -q '> Plain lead sentence. More detail.$'
check "falls back to the whole body, whitespace collapsed" $?

out=$(build "t" "$(printf 'x%.0s' {1..400})")
[ "$(jq -r '.content | split("\n")[3] | length' <<<"$out")" -eq 283 ]  # "> " + 280 + "…"
check "truncates the excerpt to 280 chars plus an ellipsis" $?

out=$(build "t" "")
jq -r .content <<<"$out" | grep -q 'No description provided\.'
check "empty body gets a placeholder" $?

out=$(build "t" $'<!-- hidden -->\nVisible.')
! jq -r .content <<<"$out" | grep -q hidden
check "HTML comments are dropped" $?

out=$(build "@everyone <@&123456789> <@42>" "@here @everyone <@&123456789> <@42>")
# Only our own prefix may contain a live mention; all "@" in title/body must be defused.
rest=$(jq -r .content <<<"$out" | tail -n +2)
# jq: no "@" is followed by anything other than a zero-width space.
! jq -e -n --arg r "$rest" '$r | test("@(?!\u200b)")' >/dev/null
check "every @ in title and body is defused" $?
[ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[],"roles":["123456789"]}' ]
check "allowed_mentions permits only the review role" $?

out=$(build 'Fix **bold** `code` [x](http://e.com) (#9)' $'See [Click here](https://evil.example) now')
[ "$(jq -r '.content | split("\n")[1]' <<<"$out")" = '**Fix \*\*bold\*\* \`code\` \[x\]\(http://e.com\) \(\#9\)**' ]
check "Markdown in the title is escaped" $?
[ "$(jq -r '.content | split("\n")[3]' <<<"$out")" = '> See \[Click here\]\(https://evil.example\) now' ]
check "links in the excerpt are escaped, not clickable" $?

out=$(build "t" $'Closes #140\n\n## Acceptance criteria\n- [ ] First thing\n- [x] Second thing\n> quoted')
[ "$(jq -r '.content | split("\n")[3]' <<<"$out")" = '> Acceptance criteria First thing Second thing quoted' ]
check "fallback drops Closes lines and strips heading, bullet and checkbox markers" $?

out=$(build "t" $'Fixes #1, #2 and #3\nCloses the loop on retries.')
[ "$(jq -r '.content | split("\n")[3]' <<<"$out")" = '> Closes the loop on retries.' ]
check "only pure issue-reference lines are dropped, prose is kept" $?

out=$(build "t" $'Closes #5\n\n## Summary\n- Adds a **thing**\n\n## Plan\n- more')
[ "$(jq -r '.content | split("\n")[3]' <<<"$out")" = '> Adds a \*\*thing\*\*' ]
check "Summary section bullets are cleaned too" $?

ROLE_ID=abc build "t" "b" >/dev/null 2>&1
[ $? -ne 0 ]; check "non-numeric role id is rejected" $?
ROLE_ID= build "t" "b" >/dev/null 2>&1
[ $? -ne 0 ]; check "missing role id is rejected" $?

exit $fail
