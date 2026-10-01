#!/usr/bin/env bash
# Builds the Discord webhook JSON for a "PR ready for review" request.
# Inputs (env): ROLE_ID, PR_NUMBER, PR_TITLE, PR_BODY, PR_AUTHOR, PR_URL.
# PR title and body are untrusted: they only ever reach jq via --arg, every "@" in them is
# defused, Markdown is escaped, and allowed_mentions lets exactly one role ping, so text there can never ping anyone.
set -euo pipefail

: "${ROLE_ID:?DISCORD_REVIEW_ROLE_ID is not set}"
[[ "$ROLE_ID" =~ ^[0-9]+$ ]] || { echo "ROLE_ID must be numeric" >&2; exit 1; }

jq -n \
  --arg role "$ROLE_ID" \
  --arg num "${PR_NUMBER:?}" \
  --arg title "${PR_TITLE:-}" \
  --arg body "${PR_BODY:-}" \
  --arg author "${PR_AUTHOR:?}" \
  --arg url "${PR_URL:?}" '
  def defuse: gsub("@"; "@\u200b");
  # Discord drops a backslash before any punctuation, so escaping all of it is safe. This stops
  # PR text from formatting the message or rendering links like [click](https://...).
  def md: gsub("(?<c>[\\\\`*_~|<>\\[\\]()#-])"; "\\\(.c)");
  def trunc($n): if length > $n then .[:$n] + "…" else . end;
  # The text under a "## Summary" heading (up to the next "## " heading), or null if there is none.
  def summary:
    split("\n") as $lines
    | ($lines | map(test("^##\\s*summary\\s*$"; "i")) | index(true)) as $i
    | if $i == null then null
      else $lines[$i + 1:]
        | (map(test("^##\\s")) | index(true)) as $j
        | (if $j == null then . else .[:$j] end) | join("\n")
      end;
  # Prefer the Summary section; otherwise the whole body. Drop HTML comments, collapse whitespace.
  def excerpt:
    gsub("<!--.*?-->"; ""; "s")
    | (summary // .)
    | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")
    | if . == "" then "No description provided." else . end
    | trunc(280) | defuse | md;
  {
    content: "<@&\($role)> PR #\($num) is ready for review\n**\($title | trunc(150) | defuse | md)**\nby \($author) · <\($url)>\n> \($body | excerpt)",
    allowed_mentions: { parse: [], roles: [$role] }
  }'
