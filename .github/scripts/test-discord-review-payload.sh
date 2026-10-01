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
desc() { jq -r '.embeds[0].description'; }

out=$(build "Add thing" $'## Summary\nAdds the thing.\n\n## Test plan\n- ran it')
[ "$(jq -r .content <<<"$out")" = '<@&123456789> Review requested' ]
check "content is the role ping and nothing from the PR" $?
[ "$(jq -r '.embeds[0] | "\(.title)|\(.url)"' <<<"$out")" = '#7 Add thing|https://github.com/o/r/pull/7' ]
check "embed title is the PR number and title, linked to the PR" $?
[ "$(desc <<<"$out")" = 'Adds the thing.' ]
check "uses the Summary section and stops at the next heading" $?

out=$(build "t" $'## 🎯 Summary\n\n<!-- What does this do? -->\nAdds the thing.\n\n## 📋 What changed\n- a')
[ "$(desc <<<"$out")" = 'Adds the thing.' ]
check "finds the Summary heading when it starts with an emoji (PR template)" $?

out=$(build "t" $'## Summary\nFirst line.\nSecond line.\nThird line.')
[ "$(desc <<<"$out")" = $'First line.\nSecond line.' ]
check "shows at most two lines" $?

out=$(build "t" $'Plain lead sentence.\n\nMore detail.\nEven more.')
[ "$(desc <<<"$out")" = $'Plain lead sentence.\nMore detail.' ]
check "falls back to the first two lines of the body" $?

out=$(build "t" $'## 🎯 Summary\n\n## 📋 What changed\n- Renames the thing\n- Adds a test')
[ "$(desc <<<"$out")" = $'Renames the thing\nAdds a test' ]
check "an empty Summary section falls back to the body, headings dropped" $?

out=$(build "t" "$(printf 'x%.0s' {1..400})")
[ "$(jq -r '.embeds[0].description | length' <<<"$out")" -eq 161 ]  # 160 + "…"
check "truncates each line to 160 chars plus an ellipsis" $?

out=$(build "t" "")
[ "$(desc <<<"$out")" = 'No description provided.' ]
check "empty body gets a placeholder" $?

out=$(build "t" $'<!-- hidden -->\nVisible.')
[ "$(desc <<<"$out")" = 'Visible.' ]
check "HTML comments are dropped" $?

out=$(build "@everyone <@&123456789> <@42>" "@here @everyone <@&123456789> <@42>")
# The only live mention is the fixed prefix in content; every "@" in title and body is defused.
rest=$(jq -c '.embeds' <<<"$out")
! jq -e -n --arg r "$rest" '$r | test("@(?!​)")' >/dev/null
check "every @ in title and body is defused" $?
[ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[],"roles":["123456789"]}' ]
check "allowed_mentions permits only the review role" $?

out=$(build 'Fix **bold** (#9)' $'See [Click here](https://evil.example) now')
[ "$(jq -r '.embeds[0].title' <<<"$out")" = '#7 Fix **bold** (#9)' ]
check "the embed title is plain text, so it is not Markdown-escaped" $?
[ "$(desc <<<"$out")" = 'See \[Click here\]\(https://evil.example\) now' ]
check "links in the description are escaped, not clickable" $?

out=$(build "t" $'Closes #140\n\n## Acceptance criteria\n- [ ] First thing\n- [x] Second thing\n> quoted')
[ "$(desc <<<"$out")" = $'First thing\nSecond thing' ]
check "drops Closes and heading lines, strips bullet and checkbox markers" $?

out=$(build "t" $'Fixes #1, #2 and #3\nCloses the loop on retries.')
[ "$(desc <<<"$out")" = 'Closes the loop on retries.' ]
check "only pure issue-reference lines are dropped, prose is kept" $?

out=$(build "t" "b")
[ "$(jq -c '.embeds[0].fields | map(.name)' <<<"$out")" = '["Author"]' ] && ! jq -e '.embeds[0] | has("footer")' <<<"$out" >/dev/null
check "no size field or footer without PR_ADDITIONS/PR_DELETIONS/REPO" $?
out=$(PR_ADDITIONS=120 PR_DELETIONS=4 PR_FILES=3 REPO=o/r build "t" "b")
[ "$(jq -r '.embeds[0].fields[] | "\(.name)=\(.value)"' <<<"$out" | tr '\n' ' ')" = 'Author=octocat Changes=+120 −4 · 3 files ' ] \
  && [ "$(jq -r '.embeds[0].footer.text' <<<"$out")" = 'o/r' ]
check "size and repo footer are shown when given" $?
out=$(PR_ADDITIONS=1 PR_DELETIONS=0 PR_FILES=1 build "t" "b")
jq -r '.embeds[0].fields[1].value' <<<"$out" | grep -q '^+1 −0 · 1 file$'
check "a single file is not pluralised" $?

ROLE_ID=abc build "t" "b" >/dev/null 2>&1
[ $? -ne 0 ]; check "non-numeric role id is rejected" $?
ROLE_ID= build "t" "b" >/dev/null 2>&1
[ $? -ne 0 ]; check "missing role id is rejected" $?

exit $fail
