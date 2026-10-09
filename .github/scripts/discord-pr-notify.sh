#!/usr/bin/env bash
# Builds the Discord webhook JSON for a PR status ping (#177): an approval, a merge, a close
# without merge, a request to review again after new commits, a re-request of review (the author
# addressed feedback and asked the reviewer back), or an @mention/reply.
# Inputs (env): KIND (approved | merged | closed | rereview | rerequest | mention), RECIPIENTS (JSON array of
# GitHub logins to ping), ACTOR (who did it), PR_NUMBER, PR_TITLE, URL (the PR, review
# or comment link; the compare link for rereview).
# Optional (env): BODY (review/comment text, approved and mention only), COMMIT_COUNT (rereview),
# PRIOR_STATE (rerequest: changes_requested | approved | other; the reviewer's last decision),
# USER_MAP (JSON: GitHub login -> Discord user ID), ROLE_ID (fallback for a recipient with no
# valid mapping), REPO.
# The text and PR title are untrusted: they only reach jq via --arg, every "@" in them is defused
# and Markdown is escaped, and allowed_mentions lists exactly the mapped user IDs being pinged
# (plus the review role only when someone has no mapping), so their text can never ping anyone.
set -euo pipefail

login='^[A-Za-z0-9-]{1,39}$'
[[ "${ACTOR:?}" =~ $login ]] || { echo "ACTOR is not a GitHub login" >&2; exit 1; }
[[ "${PR_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PR_NUMBER must be numeric" >&2; exit 1; }
[[ "${COMMIT_COUNT:-0}" =~ ^[0-9]+$ ]] || { echo "COMMIT_COUNT must be numeric" >&2; exit 1; }
[[ "${URL:?}" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(pull/[0-9]+(#[A-Za-z0-9_-]+)?|compare/[0-9a-f]{7,40}\.\.\.[0-9a-f]{7,40})$ ]] \
  || { echo "URL is not a GitHub pull request or compare link" >&2; exit 1; }
case "${KIND:?}" in approved|merged|closed|rereview|rerequest|mention) ;; *) echo "Unknown KIND: $KIND" >&2; exit 1 ;; esac
jq -e 'type == "array" and length > 0 and length <= 10 and all(type == "string" and test("^[A-Za-z0-9-]{1,39}$"))' \
  <<<"${RECIPIENTS:?}" > /dev/null || { echo "RECIPIENTS must be 1 to 10 GitHub logins" >&2; exit 1; }

# Recipients with a real Discord snowflake are pinged by ID. Bad JSON or a placeholder means "not
# mapped", never an error; those fall back to the review role so nobody is silently dropped.
resolved=$(jq -n --argjson r "$RECIPIENTS" --arg m "${USER_MAP:-}" '
  (try ($m | fromjson) catch {}) as $raw
  | (if ($raw | type) == "object" then $raw else {} end) as $map
  | def id($l): $map | to_entries | map(select((.key | ascii_downcase) == ($l | ascii_downcase))) | .[0].value
      | select(type == "string" and test("^[0-9]{17,20}$"));
    { ids: ([ $r[] | id(.) ] | unique),
      unmapped: [ $r[] | select([id(.)] | length == 0) ] }')
if [ "$(jq '.unmapped | length' <<<"$resolved")" -gt 0 ]; then
  [[ "${ROLE_ID:-}" =~ ^[0-9]+$ ]] || { echo "A recipient is not mapped and ROLE_ID is not a numeric fallback" >&2; exit 1; }
fi

jq -n \
  --argjson who "$resolved" \
  --arg role "${ROLE_ID:-}" \
  --arg kind "$KIND" \
  --arg num "$PR_NUMBER" \
  --arg title "${PR_TITLE:-}" \
  --arg actor "$ACTOR" \
  --arg url "$URL" \
  --arg body "${BODY:-}" \
  --argjson commits "${COMMIT_COUNT:-0}" \
  --arg prior "${PRIOR_STATE:-other}" \
  --arg repo "${REPO:-}" '
  def defuse: gsub("@"; "@​");
  # Discord drops a backslash before any punctuation, so escaping all of it is safe.
  def md: gsub("(?<c>[\\\\`*_~|<>\\[\\]()#-])"; "\\\(.c)");
  def trunc($n): if length > $n then .[:$n] + "…" else . end;
  def excerpt:
    gsub("<!--[\\s\\S]*?-->"; "") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")
    | if . == "" then "No text." else trunc(200) | defuse | md end;
  ( ($who.ids | map("<@\(.)>")) + (if ($who.unmapped | length) > 0 then ["<@&\($role)>"] else [] end) | join(" ") ) as $mention
  | ({ approved: "✅ \($actor | md) approved",
       merged: "🎉 \($actor | md) merged",
       closed: "🚫 \($actor | md) closed",
       rereview: "🔁 \($actor | md) pushed \(if $commits == 1 then "a new commit" elif $commits > 1 then "\($commits) new commits" else "new commits" end) to",
       rerequest: "🔁 \($actor | md) asked you to review again:",
       mention: "💬 \($actor | md) mentioned or replied to you on" }[$kind]) as $what
  | ({ approved: "", merged: "", closed: " without merging",
       rereview: " after your approval. Please review again.",
       rerequest: (if $prior == "changes_requested" then " (they addressed the changes you requested)" else "" end),
       mention: "" }[$kind]) as $tail
  | ({ approved: "View review", merged: "View pull request", closed: "View pull request",
       rereview: "View changes", rerequest: "View pull request", mention: "View comment" }[$kind]) as $link
  | ({ approved: 5763719, merged: 10181046, closed: 9807270, rereview: 15105570, rerequest: 15105570, mention: 5793266 }[$kind]) as $color
  | {
      content: ("\($mention) \($what) #\($num)\($tail)"
        + (if ($who.unmapped | length) > 0 then "\n(no Discord ID is mapped for GitHub user \($who.unmapped | map(md) | join(", ")); pinging the review role)" else "" end)),
      embeds: [{
        title: "#\($num) \($title | trunc(100) | defuse | md)",
        url: $url,
        description: ((if ($kind == "mention" or ($kind == "approved" and $body != "")) then "\($body | excerpt)\n" else "" end) + "[\($link)](\($url))"),
        color: $color,
        footer: (if $repo == "" then null else { text: $repo } end)
      } | with_entries(select(.value != null))],
      allowed_mentions: ({ parse: [], users: $who.ids } + (if ($who.unmapped | length) > 0 then { roles: [$role] } else {} end))
    }'
