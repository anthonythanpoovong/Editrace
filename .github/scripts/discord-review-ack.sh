#!/usr/bin/env bash
# Builds the Discord webhook edit that marks a review request once a human reviews the PR.
# Inputs (env): MESSAGE (the current message JSON from the webhook), REVIEWER (GitHub login),
# REVIEW_STATE (approved | changes_requested | commented).
# The content line is the only state: "<headline> · <emoji> alice approved · <emoji> bob commented".
# A repeat review by the same person replaces their entry. The headline and embed colour follow the
# most decisive state across reviewers: changes requested (red) beats approved (green) beats
# comment only (blue). The edit never pings: allowed_mentions is empty.
set -euo pipefail

[[ "${REVIEWER:?}" =~ ^[A-Za-z0-9-]{1,39}$ ]] || { echo "REVIEWER is not a GitHub login" >&2; exit 1; }
case "${REVIEW_STATE:?}" in
  approved) emoji="✅"; verb="approved" ;;
  changes_requested) emoji="🔧"; verb="requested changes" ;;
  commented) emoji="💬"; verb="commented" ;;
  *) echo "REVIEW_STATE must be approved, changes_requested or commented" >&2; exit 1 ;;
esac

jq -n \
  --argjson msg "${MESSAGE:?}" \
  --arg who "$REVIEWER" \
  --arg entry "$emoji $REVIEWER $verb" '
  ["💬 Feedback left", "🔧 Changes requested", "✅ Approved"] as $headlines
  | ($msg.content // "") as $c
  | ($c | split(" · ")) as $parts
  # Only a message this script already edited carries entries; the original ping line has none.
  | (if ($headlines | index($parts[0])) != null then $parts[1:] else [] end) as $prev
  | (($prev | map(select(sub("^\\S+ "; "") | startswith($who + " ") | not))) + [$entry]) as $entries
  | (if any($entries[]; endswith(" requested changes")) then 1
     elif any($entries[]; endswith(" approved")) then 2
     else 0 end) as $level
  | {
      content: ([$headlines[$level]] + $entries | join(" · ")),
      embeds: ($msg.embeds // [] | map(
        {title, url, description, color, fields, footer} | with_entries(select(.value != null))
        | .color = [5793266, 15548997, 5763719][$level])),
      allowed_mentions: { parse: [] }
    }'
