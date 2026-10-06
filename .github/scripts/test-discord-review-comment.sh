#!/usr/bin/env bash
# Tests for discord-review-comment.sh. Run: .github/scripts/test-discord-review-comment.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
ALICE=111111111111111111 BOB=222222222222222222 ROLE=333333333333333333
export PR_NUMBER=7 PR_TITLE="Add thing" PR_AUTHOR=alice COMMENTER=bob
export COMMENT_URL="https://github.com/o/r/pull/7#issuecomment-1" ROLE_ID=$ROLE REPO=o/r
export USER_MAP="{\"alice\":\"$ALICE\",\"bob\":\"$BOB\"}"
build() { ./discord-review-comment.sh; }
content() { jq -r .content; }
desc() { jq -r '.embeds[0].description'; }

out=$(KIND=comment COMMENT_BODY="Please rename this." build)
[ "$(content <<<"$out")" = "<@$ALICE> 💬 bob commented on #7" ] \
  && [ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"users\":[\"$ALICE\"]}" ]
check "a conversation comment pings the author's user, and only that user" $?

out=$(KIND=review REVIEW_STATE=changes_requested COMMENT_BODY="Needs work." COMMENT_URL="https://github.com/o/r/pull/7#pullrequestreview-9" build)
[ "$(content <<<"$out")" = "<@$ALICE> 🔧 bob requested changes on #7" ] \
  && [ "$(jq -r '.embeds[0].color' <<<"$out")" = 15548997 ] \
  && [ "$(desc <<<"$out")" = $'Needs work.\n[View review](https://github.com/o/r/pull/7#pullrequestreview-9)' ]
check "requested changes: wrench, red embed, link to the review" $?

out=$(KIND=review REVIEW_STATE=commented COMMENT_BODY="Nit." COMMENT_URL="https://github.com/o/r/pull/7#pullrequestreview-9" build)
[ "$(content <<<"$out")" = "<@$ALICE> 💬 bob commented on #7" ] && [ "$(jq -r '.embeds[0].color' <<<"$out")" = 5793266 ]
check "a Comment review: speech bubble, blue embed" $?

out=$(KIND=review REVIEW_STATE=approved COMMENT_BODY="LGTM" COMMENT_URL="https://github.com/o/r/pull/7#pullrequestreview-9" build 2>&1)
[ $? -ne 0 ] ; check "an approval is rejected, it never pings" $?

out=$(PR_AUTHOR=carol KIND=comment COMMENT_BODY="Hi" build)
[ "$(head -n1 <<<"$(content <<<"$out")")" = "<@&$ROLE> 💬 bob commented on #7" ] \
  && content <<<"$out" | grep -q 'no Discord ID is mapped for GitHub user carol' \
  && [ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"roles\":[\"$ROLE\"]}" ]
check "an unmapped author falls back to the review role, with a note" $?

out=$(USER_MAP='{"alice":"REPLACE_WITH_DISCORD_USER_ID"}' KIND=comment COMMENT_BODY="Hi" build)
[ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"roles\":[\"$ROLE\"]}" ]
check "a placeholder or non-numeric id falls back to the role" $?

out=$(USER_MAP='not json' KIND=comment COMMENT_BODY="Hi" build)
[ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"roles\":[\"$ROLE\"]}" ]
check "invalid JSON in the map falls back to the role" $?

out=$(USER_MAP= KIND=comment COMMENT_BODY="Hi" build)
[ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"roles\":[\"$ROLE\"]}" ]
check "an empty map falls back to the role" $?

USER_MAP= ROLE_ID= KIND=comment COMMENT_BODY="Hi" build >/dev/null 2>&1
[ $? -ne 0 ]; check "unmapped author and no valid role id is an error, not a silent drop" $?

out=$(ROLE_ID= KIND=comment COMMENT_BODY="Hi" build)
[ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"users\":[\"$ALICE\"]}" ]
check "a mapped author does not need the role id" $?

out=$(KIND=comment COMMENT_BODY="$(printf 'x%.0s' {1..300})" build)
n=$(desc <<<"$out" | head -n1 | python3 -c 'import sys;print(len(sys.stdin.readline().rstrip("\n")))')
[ "$n" -eq 201 ]; check "the excerpt is cut to 200 chars plus an ellipsis" $?

out=$(KIND=comment COMMENT_BODY=$'line one\n\n  line   two <!-- hidden -->' build)
[ "$(desc <<<"$out" | head -n1)" = "line one line two" ]
check "whitespace is collapsed and HTML comments are dropped" $?

out=$(KIND=comment COMMENT_BODY="" build)
[ "$(desc <<<"$out" | head -n1)" = "No text." ]
check "an empty comment says so" $?

out=$(KIND=review REVIEW_STATE=commented COMMENT_BODY="Rename it." INLINE_COUNT=3 COMMENT_URL="https://github.com/o/r/pull/7#pullrequestreview-9" build)
[ "$(jq -c '.embeds[0].fields' <<<"$out")" = '[{"name":"Inline comments","value":"3","inline":true}]' ]
check "a review with inline comments shows the count" $?

out=$(KIND=review REVIEW_STATE=commented COMMENT_BODY="" INLINE_COUNT=2 COMMENT_URL="https://github.com/o/r/pull/7#pullrequestreview-9" build)
[ "$(desc <<<"$out" | head -n1)" = "Inline comments only." ]
check "a review with no text and only inline comments says so" $?

out=$(KIND=comment PR_TITLE='@everyone <@42>' COMMENT_BODY='@everyone @here <@&333333333333333333> <@42> see [click](https://evil.example)' build)
body=$(jq -r '[.embeds[0].title, (.embeds[0].description | split("\n")[0])] | join(" ")' <<<"$out")
# Neither the title nor the excerpt may contain an "@" that is not followed by a zero-width space.
! jq -e -n --arg r "$body" '$r | test("@(?!​)")' >/dev/null \
  && ! grep -q 'click\](' <<<"$body" \
  && [ "$(jq -c .allowed_mentions <<<"$out")" = "{\"parse\":[],\"users\":[\"$ALICE\"]}" ]
check "@everyone, mentions and links in the title and comment cannot ping or link" $?

for bad in "PR_AUTHOR=a b" "COMMENTER=bob@x" "PR_NUMBER=7x" "COMMENT_URL=https://evil.example/o/r/pull/7#c-1" "INLINE_COUNT=x" "KIND=other"; do
  ( export KIND=comment COMMENT_BODY=hi; export "$bad"; build >/dev/null 2>&1 ); [ $? -ne 0 ]
  check "rejects bad input: $bad" $?
done

exit $fail
