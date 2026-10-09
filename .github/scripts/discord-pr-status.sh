#!/usr/bin/env bash
# Sends the Discord pings for a PR status change (#177): approval, merge, close without merge,
# review again after new commits, and @mentions/replies. One run can send more than one message
# (an approval that also @mentions someone sends two). Comments and requested changes for the PR
# author are handled by discord-review-comment.sh, so the author is never pinged twice here.
# Inputs (env): EVENT (pull_request_review | issue_comment | pull_request), ACTION, REPO, PR_NUMBER,
# PR_TITLE, PR_AUTHOR, ACTOR, URL (event link), WEBHOOK, GH_TOKEN, USER_MAP, ROLE_ID.
# By event: pull_request_review needs REVIEW_ID, REVIEW_STATE, BODY; issue_comment needs BODY;
# pull_request needs MERGED (true | false) for closed, BEFORE and AFTER for synchronize, and
# REQUESTED (the re-requested reviewer's login) for review_requested.
# Untrusted text (BODY, PR_TITLE) only reaches the helper scripts via env.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

login='^[A-Za-z0-9-]{1,39}$'
[[ "${PR_AUTHOR:?}" =~ $login && "${ACTOR:?}" =~ $login ]] || { echo "PR_AUTHOR or ACTOR is not a GitHub login" >&2; exit 1; }
[[ "${PR_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PR_NUMBER must be numeric" >&2; exit 1; }
[[ "${WEBHOOK:?}" =~ ^https://(discord|discordapp)\.com/api/webhooks/ ]] \
  || { echo "DISCORD_REVIEW_WEBHOOK is missing or not a Discord webhook URL" >&2; exit 1; }
: "${REPO:?}" "${EVENT:?}" "${ACTION:?}" "${URL:?}"

sent=0
send() { # kind, recipients JSON, [body], [commit count], [url]
  KIND="$1" RECIPIENTS="$2" BODY="${3:-}" COMMIT_COUNT="${4:-0}" URL="${5:-$URL}" "$here/discord-pr-notify.sh" | jq -c . > payload.json
  curl --fail --silent --show-error --max-time 20 -H "Content-Type: application/json" --data @payload.json "$WEBHOOK"
  sent=$((sent + 1))
}
author_json=$(jq -nc --arg a "$PR_AUTHOR" '[$a]')
skip_json=$(jq -nc --arg a "$PR_AUTHOR" --arg b "$ACTOR" '[$a, $b]')

export PR_NUMBER PR_TITLE="${PR_TITLE:-}" PR_AUTHOR ACTOR REPO USER_MAP="${USER_MAP:-}" ROLE_ID="${ROLE_ID:-}"

# Pings for @mentions and replies. The PR author is excluded: they already get the approval,
# comment or requested-changes ping for the same event.
mention_ping() { # texts JSON, replied-to JSON, body to quote
  local who
  who=$(TEXTS="$1" REPLIED_TO="$2" EXCLUDE="$skip_json" "$here/discord-pr-mentions.sh")
  if [ "$(jq length <<<"$who")" -gt 0 ]; then send mention "$who" "$3"; fi
}

case "$EVENT/$ACTION" in
  pull_request_review/submitted)
    [[ "${REVIEW_ID:?}" =~ ^[0-9]+$ ]] || { echo "REVIEW_ID must be numeric" >&2; exit 1; }
    # Best effort: if the lookups fail the pings still go out with the review text.
    gh api --paginate "repos/$REPO/pulls/$PR_NUMBER/reviews/$REVIEW_ID/comments" --jq '.[]' 2>/dev/null | jq -s '.' > inline.json || true
    jq -e 'type == "array"' inline.json > /dev/null 2>&1 || echo '[]' > inline.json
    text=${BODY:-}
    [ -n "$text" ] || text=$(jq -r '.[0].body // ""' inline.json)
    if [ "${REVIEW_STATE:-}" = approved ] && [ "$ACTOR" != "$PR_AUTHOR" ]; then send approved "$author_json" "${BODY:-}"; fi
    replied='[]'
    for parent in $(jq -r '[.[].in_reply_to_id | select(. != null)] | unique | .[]' inline.json); do
      [[ "$parent" =~ ^[0-9]+$ ]] || continue
      who=$(gh api "repos/$REPO/pulls/comments/$parent" --jq .user.login 2>/dev/null || true)
      [[ "$who" =~ $login ]] && replied=$(jq -c --arg w "$who" '. + [$w]' <<<"$replied")
    done
    texts=$(jq -c --arg b "${BODY:-}" '[$b] + map(.body)' inline.json)
    mention_ping "$texts" "$replied" "$text" ;;
  issue_comment/created)
    mention_ping "$(jq -nc --arg b "${BODY:-}" '[$b]')" '[]' "${BODY:-}" ;;
  pull_request/closed)
    # Closed by the author themselves: they already know.
    [ "$ACTOR" != "$PR_AUTHOR" ] || { echo "Closed by the author; nothing to send."; exit 0; }
    if [ "${MERGED:?}" = true ]; then send merged "$author_json"; else send closed "$author_json"; fi ;;
  pull_request/synchronize)
    [[ "${BEFORE:?}" =~ ^[0-9a-f]{7,40}$ && "${AFTER:?}" =~ ^[0-9a-f]{7,40}$ ]] || { echo "BEFORE and AFTER must be commit SHAs" >&2; exit 1; }
    reviews=$(gh api --paginate "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '.[]' | jq -s '.')
    who=$(REVIEWS="$reviews" BEFORE="$BEFORE" EXCLUDE="$skip_json" "$here/discord-pr-rereview.sh")
    if [ "$(jq length <<<"$who")" -gt 0 ]; then
      count=$(gh api "repos/$REPO/compare/$BEFORE...$AFTER" --jq .total_commits 2>/dev/null || echo 0)
      [[ "$count" =~ ^[0-9]+$ ]] || count=0
      send rereview "$who" "" "$count" "https://github.com/$REPO/compare/$BEFORE...$AFTER"
    fi ;;
  pull_request/review_requested)
    # Only a reviewer who already reviewed this PR: the first request is discord-review-request's job.
    # A person asking themselves, or the author being requested, is not a re-request.
    [[ "${REQUESTED:?}" =~ $login ]] || { echo "REQUESTED is not a GitHub login" >&2; exit 1; }
    requested_lc=$(tr '[:upper:]' '[:lower:]' <<<"$REQUESTED")
    for same in "$ACTOR" "$PR_AUTHOR"; do
      [ "$requested_lc" != "$(tr '[:upper:]' '[:lower:]' <<<"$same")" ] || { echo "Nothing to send: reviewer is the requester or the author."; exit 0; }
    done
    reviews=$(gh api --paginate "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '.[]' | jq -s '.')
    prior=$(jq -r --arg u "$REQUESTED" '
      map(select(.user.login != null and (.user.login | ascii_downcase) == ($u | ascii_downcase)))
      | if length == 0 then "none"
        else (map(select(.state | ascii_upcase | IN("APPROVED", "CHANGES_REQUESTED", "DISMISSED"))) | sort_by(.submitted_at) | last // null) as $d
          | if $d == null then "other" elif ($d.state | ascii_upcase) == "CHANGES_REQUESTED" then "changes_requested"
            elif ($d.state | ascii_upcase) == "APPROVED" then "approved" else "other" end end' <<<"$reviews")
    if [ "$prior" = none ]; then echo "$REQUESTED has not reviewed this PR yet; nothing to send."; exit 0; fi
    PRIOR_STATE="$prior" send rerequest "$(jq -nc --arg r "$REQUESTED" '[$r]')" ;;
  *) echo "Nothing to do for $EVENT/$ACTION"; exit 0 ;;
esac
echo "Sent $sent message(s) for $EVENT/$ACTION on PR #$PR_NUMBER"
