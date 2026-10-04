#!/usr/bin/env bash
# Builds the Discord webhook JSON that pings a PR author about a human review or comment.
# Inputs (env): KIND (review | comment), PR_NUMBER, PR_TITLE, PR_AUTHOR, COMMENTER, COMMENT_URL.
# Optional (env): REVIEW_STATE (commented | changes_requested; reviews only), COMMENT_BODY,
# INLINE_COUNT (inline comments in a review), USER_MAP (JSON: GitHub login -> Discord user ID),
# ROLE_ID (fallback when the author has no valid mapping), REPO.
# The comment text and PR title are untrusted: they only reach jq via --arg, every "@" in them is
# defused and Markdown is escaped, and allowed_mentions lets exactly one target ping (the author's
# user ID, or the review role when the author is not mapped), so their text can never ping anyone.
set -euo pipefail

login='^[A-Za-z0-9-]{1,39}$'
[[ "${PR_AUTHOR:?}" =~ $login ]] || { echo "PR_AUTHOR is not a GitHub login" >&2; exit 1; }
[[ "${COMMENTER:?}" =~ $login ]] || { echo "COMMENTER is not a GitHub login" >&2; exit 1; }
[[ "${PR_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PR_NUMBER must be numeric" >&2; exit 1; }
[[ "${COMMENT_URL:?}" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+#[A-Za-z0-9_-]+$ ]] \
  || { echo "COMMENT_URL is not a GitHub pull request link" >&2; exit 1; }
[[ "${INLINE_COUNT:-0}" =~ ^[0-9]+$ ]] || { echo "INLINE_COUNT must be numeric" >&2; exit 1; }
case "${KIND:?}" in
  comment) state="commented" ;;
  review)
    case "${REVIEW_STATE:?}" in
      commented|changes_requested) state="$REVIEW_STATE" ;;
      *) echo "REVIEW_STATE must be commented or changes_requested" >&2; exit 1 ;;
    esac ;;
  *) echo "KIND must be review or comment" >&2; exit 1 ;;
esac

# The author's Discord user ID, only if it is a real snowflake. Bad JSON or a placeholder means
# "not mapped", never an error, so nothing is dropped.
uid=$(jq -rn --arg a "$PR_AUTHOR" --arg m "${USER_MAP:-}" '
  (try ($m | fromjson) catch {}) | if type == "object" then .[$a] else null end
  | select(type == "string" and test("^[0-9]{17,20}$"))')
if [ -z "$uid" ]; then
  [[ "${ROLE_ID:-}" =~ ^[0-9]+$ ]] || { echo "Author is not mapped and ROLE_ID is not a numeric fallback" >&2; exit 1; }
fi

jq -n \
  --arg uid "$uid" \
  --arg role "${ROLE_ID:-}" \
  --arg kind "$KIND" \
  --arg state "$state" \
  --arg num "$PR_NUMBER" \
  --arg title "${PR_TITLE:-}" \
  --arg author "$PR_AUTHOR" \
  --arg who "$COMMENTER" \
  --arg url "$COMMENT_URL" \
  --arg body "${COMMENT_BODY:-}" \
  --argjson inline "${INLINE_COUNT:-0}" \
  --arg repo "${REPO:-}" '
  def defuse: gsub("@"; "@​");
  # Discord drops a backslash before any punctuation, so escaping all of it is safe.
  def md: gsub("(?<c>[\\\\`*_~|<>\\[\\]()#-])"; "\\\(.c)");
  def trunc($n): if length > $n then .[:$n] + "…" else . end;
  def excerpt:
    gsub("<!--.*?-->"; ""; "s") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")
    | if . == "" then (if $inline > 0 then "Inline comments only." else "No text." end)
      else trunc(200) | defuse | md end;
  (if $uid != "" then "<@\($uid)>" else "<@&\($role)>" end) as $mention
  | (if $state == "changes_requested" then "🔧 \($who | md) requested changes"
     else "💬 \($who | md) commented" end) as $what
  | {
      content: ("\($mention) \($what) on #\($num)"
        + (if $uid == "" then "\n(no Discord ID is mapped for GitHub user \($author | md); pinging the review role)" else "" end)),
      embeds: [{
        title: "#\($num) \($title | trunc(200) | defuse | md)",
        url: $url,
        description: "\($body | excerpt)\n[View \(if $kind == "review" then "review" else "comment" end)](\($url))",
        color: (if $state == "changes_requested" then 15548997 else 5793266 end),
        fields: (if $inline > 0 then [{ name: "Inline comments", value: ($inline | tostring), inline: true }] else [] end),
        footer: (if $repo == "" then null else { text: $repo } end)
      } | with_entries(select(.value != null))],
      allowed_mentions: (if $uid != "" then { parse: [], users: [$uid] } else { parse: [], roles: [$role] } end)
    }'
