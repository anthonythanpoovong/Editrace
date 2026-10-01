#!/usr/bin/env bash
# Builds the Discord webhook JSON for a "PR ready for review" request: a role ping plus one embed
# (linked title, a 1-2 line summary, author and size).
# Inputs (env): ROLE_ID, PR_NUMBER, PR_TITLE, PR_BODY, PR_AUTHOR, PR_URL.
# Optional (env): PR_ADDITIONS, PR_DELETIONS, PR_FILES, REPO.
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
  --arg url "${PR_URL:?}" \
  --arg adds "${PR_ADDITIONS:-}" \
  --arg dels "${PR_DELETIONS:-}" \
  --arg files "${PR_FILES:-}" \
  --arg repo "${REPO:-}" '
  def defuse: gsub("@"; "@​");
  # Discord drops a backslash before any punctuation, so escaping all of it is safe. This stops
  # PR text from formatting the message or rendering links like [click](https://...).
  def md: gsub("(?<c>[\\\\`*_~|<>\\[\\]()#-])"; "\\\(.c)");
  def trunc($n): if length > $n then .[:$n] + "…" else . end;
  # The text under a "Summary" heading (up to the next "## " heading), or null if there is none.
  # The heading may start with an emoji, as in the PR template ("## 🎯 Summary").
  def summary:
    split("\n") as $lines
    | ($lines | map(test("^##\\s*[^A-Za-z0-9\\s]*\\s*summary\\s*$"; "i")) | index(true)) as $i
    | if $i == null then null
      else $lines[$i + 1:]
        | (map(test("^##\\s")) | index(true)) as $j
        | (if $j == null then . else .[:$j] end) | join("\n")
      end;
  # Non-empty lines with the Markdown noise that says nothing about the change removed: heading
  # lines, "Closes #n" lines, bullets, checkboxes and quote markers.
  def tidy:
    split("\n")
    | map(select(test("^\\s*#{1,6}\\s") | not))
    | map(select(test("^\\s*(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?|references?|part of|related to):?\\s+#[0-9]+(\\s*(,|and|&)\\s*#[0-9]+)*\\s*$"; "i") | not))
    | map(sub("^\\s*([-*+]\\s+(\\[[ xX]\\]\\s*)?|>\\s*)"; "") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; ""))
    | map(select(. != "" and (test("^[-*+]$") | not)));
  # The first two lines of the Summary section, else of the whole body, each cut to 160 chars.
  def about:
    gsub("<!--.*?-->"; ""; "s") as $b
    | (($b | summary // "") | tidy) as $s
    | (if ($s | length) > 0 then $s else ($b | tidy) end)
    | if length == 0 then ["No description provided."] else . end
    | .[:2] | map(trunc(160) | defuse | md) | join("\n");
  def size:
    if $adds == "" or $dels == "" then null
    else "+\($adds) −\($dels)" + (if $files == "" then "" else " · \($files) file\(if $files == "1" then "" else "s" end)" end)
    end;
  {
    content: "<@&\($role)> Review requested",
    embeds: [{
      title: "#\($num) \($title | trunc(200) | defuse)",
      url: $url,
      description: ($body | about),
      color: 15105570,
      fields: ([
        { name: "Author", value: ($author | md), inline: true },
        (size | if . == null then empty else { name: "Changes", value: ., inline: true } end)
      ]),
      footer: (if $repo == "" then null else { text: $repo } end)
    } | with_entries(select(.value != null))],
    allowed_mentions: { parse: [], roles: [$role] }
  }'
