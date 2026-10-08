#!/usr/bin/env bash
# Tests for the PR status ping scripts (#177). Run: .github/scripts/test-discord-pr-status.sh
set -uo pipefail
cd "$(dirname "$0")"
here=$(pwd)
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
same() { [ "$(jq -cS . <<<"$1")" = "$(jq -cS . <<<"$2")" ]; }

MAP='{"alice":"111111111111111111","Bob":"222222222222222222","carol":"333333333333333333"}'

# --- discord-pr-mentions.sh ---
men() { TEXTS="$1" USER_MAP="$MAP" REPLIED_TO="${2:-[]}" EXCLUDE="${3:-[]}" ./discord-pr-mentions.sh; }

same "$(men '["hi @carol"]')" '["carol"]'; check "a mapped @mention is found" $?
same "$(men '["hi @BOB and @Alice"]')" '["Bob","alice"]'; check "logins match case-insensitively and come back as mapped, in order" $?
same "$(men '["@carol @nobody @org/team"]')" '["carol"]'; check "unmapped users and teams are skipped" $?
same "$(men '["mail a@alice.com"]')" '[]'; check "an email address is not a mention" $?
same "$(men '["`@alice` and\n> @carol quoted\n```\n@bob\n```\nplain"]')" '[]'; check "code, quotes and fences do not ping" $?
same "$(men '["<!-- @alice --> hi"]')" '[]'; check "HTML comments do not ping" $?
same "$(men '["@alice @alice @ALICE"]')" '["alice"]'; check "each person once" $?
same "$(men '["@carol"]' '[]' '["CAROL"]')" '[]'; check "excluded users (commenter, author) are not pinged" $?
same "$(men '["no mentions"]' '["alice","dave"]')" '["alice"]'; check "a reply pings the author of the replied-to comment if mapped" $?
same "$(men '["@alice"]' '["alice"]')" '["alice"]'; check "mentioned and replied-to is one ping" $?
big='{"a1":"111111111111111111","a2":"111111111111111112","a3":"111111111111111113","a4":"111111111111111114","a5":"111111111111111115","a6":"111111111111111116"}'
[ "$(TEXTS='["@a1 @a2 @a3 @a4 @a5 @a6"]' USER_MAP="$big" ./discord-pr-mentions.sh | jq length)" = 5 ]; check "capped at 5 pings" $?
[ "$(TEXTS='["@alice"]' USER_MAP='{"alice":"placeholder"}' ./discord-pr-mentions.sh)" = '[]' ]; check "a non-numeric Discord ID is not pinged" $?
[ "$(TEXTS='["@alice"]' USER_MAP='not json' ./discord-pr-mentions.sh)" = '[]' ]; check "a bad map pings nobody and does not fail" $?

# --- discord-pr-rereview.sh ---
rv() { jq -nc --arg u "$1" --arg s "$2" --arg c "$3" --arg t "$4" '{user:{login:$u,type:"User"},state:$s,commit_id:$c,submitted_at:$t}'; }
rr() { REVIEWS="$1" BEFORE=aaaaaaa EXCLUDE="${2:-[]}" ./discord-pr-rereview.sh; }

same "$(rr "[$(rv bob APPROVED aaaaaaa 2026-01-01T00:00:00Z)]")" '["bob"]'; check "an approval on the replaced commit is pinged" $?
same "$(rr "[$(rv bob DISMISSED aaaaaaa 2026-01-01T00:00:00Z)]")" '["bob"]'; check "a dismissed (auto-dismissed stale) approval is pinged" $?
same "$(rr "[$(rv bob APPROVED bbbbbbb 2026-01-01T00:00:00Z)]")" '[]'; check "an approval on an older commit is not pinged (second push)" $?
same "$(rr "[$(rv bob APPROVED aaaaaaa 2026-01-01T00:00:00Z),$(rv bob COMMENTED aaaaaaa 2026-01-02T00:00:00Z)]")" '["bob"]'; check "a later plain comment does not cancel the approval" $?
same "$(rr "[$(rv bob APPROVED aaaaaaa 2026-01-01T00:00:00Z),$(rv bob CHANGES_REQUESTED aaaaaaa 2026-01-02T00:00:00Z)]")" '[]'; check "a newer requested-changes decision is not pinged" $?
same "$(rr "[$(rv bob CHANGES_REQUESTED aaaaaaa 2026-01-01T00:00:00Z),$(rv bob APPROVED aaaaaaa 2026-01-02T00:00:00Z)]")" '["bob"]'; check "a newer approval wins over an older request" $?
same "$(rr "[$(rv bob COMMENTED aaaaaaa 2026-01-01T00:00:00Z)]")" '[]'; check "a reviewer who only commented is not pinged" $?
same "$(rr "[$(rv bob APPROVED aaaaaaa 2026-01-01T00:00:00Z),$(rv alice APPROVED aaaaaaa 2026-01-01T00:00:00Z)]" '["Alice"]')" '["bob"]'; check "excluded users (author, pusher) are not pinged" $?
same "$(rr "[$(rv bob APPROVED aaaaaaa 2026-01-01T00:00:00Z | jq -c '.user.type="Bot"')]")" '[]'; check "bots are not pinged" $?
REVIEWS='[]' BEFORE='not a sha' ./discord-pr-rereview.sh > /dev/null 2>&1; [ $? -ne 0 ]; check "a bad BEFORE is rejected" $?

# --- discord-pr-notify.sh ---
PR=https://github.com/o/r/pull/7
note() { KIND="$1" RECIPIENTS="$2" ACTOR=bob PR_NUMBER=7 PR_TITLE="${5:-Title}" URL="${3:-$PR}" BODY="${4:-}" USER_MAP="$MAP" ROLE_ID=999 ./discord-pr-notify.sh; }

out=$(note approved '["alice"]' "$PR#pullrequestreview-1" 'Looks good')
[ "$(jq -r .content <<<"$out")" = '<@111111111111111111> ✅ bob approved #7' ] && same "$(jq .allowed_mentions <<<"$out")" '{"parse":[],"users":["111111111111111111"]}'
check "approved: pings the author by ID with who" $?
jq -r '.embeds[0].description' <<<"$out" | grep -q 'Looks good'; check "approved: shows the review text" $?
out=$(note approved '["alice"]' "$PR#pullrequestreview-1" ''); [ "$(jq -r '.embeds[0].description' <<<"$out")" = "[View review]($PR#pullrequestreview-1)" ]
check "approved with no text: just the link" $?
out=$(note merged '["alice"]'); [[ "$(jq -r .content <<<"$out")" == *'🎉 bob merged #7' ]]; check "merged message" $?
out=$(note closed '["alice"]'); [[ "$(jq -r .content <<<"$out")" == *'🚫 bob closed #7 without merging' ]]; check "closed message" $?
out=$(KIND=rereview RECIPIENTS='["Bob","carol"]' ACTOR=alice PR_NUMBER=7 PR_TITLE=T URL=https://github.com/o/r/compare/abcdef1...abcdef2 COMMIT_COUNT=3 USER_MAP="$MAP" ./discord-pr-notify.sh)
[ "$(jq -r .content <<<"$out")" = '<@222222222222222222> <@333333333333333333> 🔁 alice pushed 3 new commits to #7 after your approval. Please review again.' ]
check "rereview: pings every approver and counts commits" $?
out=$(note mention '["Bob","carol"]' "$PR#issuecomment-5" 'hey @bob'); [[ "$(jq -r .content <<<"$out")" == '<@222222222222222222> <@333333333333333333> 💬 bob mentioned or replied to you on #7' ]]
check "mention: pings every recipient" $?
out=$(note approved '["zed"]'); [[ "$(jq -r .content <<<"$out")" == *'<@&999>'* ]] && same "$(jq .allowed_mentions <<<"$out")" '{"parse":[],"users":[],"roles":["999"]}'
check "unmapped recipient falls back to the review role with a note" $?
jq -r .content <<<"$out" | grep -q 'no Discord ID is mapped for GitHub user zed'; check "the fallback note names the user" $?
out=$(note mention '["alice"]' "$PR#issuecomment-5" '@everyone @here <@999> [x](http://evil.test) @alice' '@everyone **t**')
[ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[],"users":["111111111111111111"]}' ] && ! jq -r '.embeds[0].description,.embeds[0].title' <<<"$out" | grep -qE '@everyone|@here|@alice|\[x\]\(http'
check "comment text and title cannot ping or render links" $?
long=$(printf 'x%.0s' $(seq 1 300)); out=$(note mention '["alice"]' "$PR#issuecomment-5" "$long")
[ "$(jq -r '.embeds[0].description | split("\n")[0] | length' <<<"$out")" -le 201 ]; check "excerpt is at most 200 characters" $?
for bad in "KIND=nope" "URL=https://evil.test/pull/7" "RECIPIENTS=[]" 'RECIPIENTS=["a b"]'; do
  env KIND=approved RECIPIENTS='["alice"]' ACTOR=bob PR_NUMBER=7 URL=$PR USER_MAP="$MAP" ROLE_ID=999 "$bad" ./discord-pr-notify.sh > /dev/null 2>&1; [ $? -ne 0 ]
  check "rejects $bad" $?
done
KIND=merged RECIPIENTS='["zed"]' ACTOR=bob PR_NUMBER=7 URL=$PR USER_MAP="$MAP" ./discord-pr-notify.sh > /dev/null 2>&1; [ $? -ne 0 ]
check "an unmapped recipient with no numeric ROLE_ID fails loudly" $?

# --- discord-pr-status.sh, against fake gh and curl ---
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/curl" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in @*) cat "${a#@}" >> "$FAKE_SENT"; echo >> "$FAKE_SENT" ;; esac; done
FAKE
cat > "$tmp/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"/reviews/"*"/comments"*) echo "$FAKE_INLINE" ;;
  *"pulls/comments/"*) echo "${FAKE_PARENT:-}" ;;
  *"/reviews"*) echo "$FAKE_REVIEWS" ;;
  *"/compare/"*) echo 2 ;;
esac
FAKE
chmod +x "$tmp/curl" "$tmp/gh"
export FAKE_SENT="$tmp/sent"
status() { # env assignments as arguments; runs in a scratch dir
  : > "$FAKE_SENT"
  ( cd "$tmp" && env PATH="$tmp:$PATH" REPO=o/r PR_NUMBER=7 PR_TITLE=T PR_AUTHOR=alice URL="$PR#x" \
      WEBHOOK=https://discord.com/api/webhooks/1/x USER_MAP="$MAP" ROLE_ID=999 "$@" "$here/discord-pr-status.sh" ) > "$tmp/out" 2>&1
}
sent() { grep -c . "$FAKE_SENT"; }
dbg() { cat "$tmp/out" >&2; }

FAKE_INLINE='' status EVENT=pull_request_review ACTION=submitted REVIEW_ID=5 REVIEW_STATE=approved ACTOR=bob BODY='ok'
[ "$(sent)" -eq 1 ] && grep -q '<@111111111111111111> ✅ bob approved' "$FAKE_SENT"; check "approval: one ping to the author" $?

FAKE_INLINE='' status EVENT=pull_request_review ACTION=submitted REVIEW_ID=5 REVIEW_STATE=approved ACTOR=bob BODY='thanks @carol'
[ "$(sent)" -eq 2 ] && grep -q '<@333333333333333333> 💬 bob mentioned' "$FAKE_SENT"; check "approval that @mentions someone: author ping plus mention ping" $?

FAKE_INLINE='' status EVENT=pull_request_review ACTION=submitted REVIEW_ID=5 REVIEW_STATE=commented ACTOR=bob BODY='@alice please look'
[ "$(sent)" -eq 0 ]; check "the author @mentioned in a comment is left to discord-review-comment (no duplicate)" $?

FAKE_INLINE='{"body":"@carol thoughts?","in_reply_to_id":9}' FAKE_PARENT=Bob status EVENT=pull_request_review ACTION=submitted REVIEW_ID=5 REVIEW_STATE=commented ACTOR=dave BODY=''
[ "$(sent)" -eq 1 ] && grep -q '<@222222222222222222> <@333333333333333333>' "$FAKE_SENT"; check "an inline reply pings the replied-to user and anyone @mentioned in one message" $?

FAKE_INLINE='' status EVENT=issue_comment ACTION=created ACTOR=bob BODY='cc @carol'
[ "$(sent)" -eq 1 ] && grep -q '<@333333333333333333> 💬 bob' "$FAKE_SENT"; check "a conversation comment @mention pings" $?

FAKE_INLINE='' status EVENT=issue_comment ACTION=created ACTOR=bob BODY='cc @carol' WEBHOOK=nope; [ $? -ne 0 ]; check "a bad webhook URL fails" $?

status EVENT=pull_request ACTION=closed ACTOR=bob MERGED=true
[ "$(sent)" -eq 1 ] && grep -q 'merged #7' "$FAKE_SENT"; check "merge by someone else pings the author" $?
status EVENT=pull_request ACTION=closed ACTOR=bob MERGED=false
grep -q 'closed #7 without merging' "$FAKE_SENT"; check "close without merge pings the author" $?
status EVENT=pull_request ACTION=closed ACTOR=alice MERGED=true
[ "$(sent)" -eq 0 ]; check "a self-merge does not ping" $?

R="[$(rv Bob APPROVED aaaaaaa1 2026-01-01T00:00:00Z),$(rv alice APPROVED aaaaaaa1 2026-01-01T00:00:00Z)]"
FAKE_REVIEWS="$(jq -c '.[]' <<<"$R")" status EVENT=pull_request ACTION=synchronize ACTOR=alice BEFORE=aaaaaaa1 AFTER=bbbbbbb2
[ "$(sent)" -eq 1 ] && grep -q '<@222222222222222222> 🔁 alice pushed 2 new commits' "$FAKE_SENT"; check "a push after approval pings the approver, not the author" $?
FAKE_REVIEWS="$(jq -c '.[]' <<<"$R")" status EVENT=pull_request ACTION=synchronize ACTOR=alice BEFORE=ccccccc3 AFTER=ddddddd4
[ "$(sent)" -eq 0 ]; check "a second push no longer matches the approval: no ping" $?

FAKE_INLINE='' status EVENT=pull_request_review ACTION=submitted REVIEW_ID=5 REVIEW_STATE=approved ACTOR=alice BODY='self'
[ "$(sent)" -eq 0 ]; check "an author approving their own PR does not ping" $?

exit $fail
