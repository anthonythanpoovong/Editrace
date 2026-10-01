#!/usr/bin/env bash
# Builds the Discord webhook edit that marks a review request as reviewed once a human reviews the PR.
# Inputs (env): MESSAGE (the current message JSON from the webhook), REVIEWER (GitHub login),
# REVIEW_STATE (approved | changes_requested | commented).
# The content line is the only state: "✅ Reviewed · alice approved · bob commented". A repeat
# review by the same person replaces their entry. The embed turns green once anyone has approved
# and red while anyone has requested changes (red wins). The edit never pings: allowed_mentions is empty.
set -euo pipefail

[[ "${REVIEWER:?}" =~ ^[A-Za-z0-9-]{1,39}$ ]] || { echo "REVIEWER is not a GitHub login" >&2; exit 1; }
case "${REVIEW_STATE:?}" in
  approved) verb="approved" ;;
  changes_requested) verb="requested changes" ;;
  commented) verb="commented" ;;
  *) echo "REVIEW_STATE must be approved, changes_requested or commented" >&2; exit 1 ;;
esac

jq -n \
  --argjson msg "${MESSAGE:?}" \
  --arg who "$REVIEWER" \
  --arg verb "$verb" '
  ($msg.content // "") as $c
  | (if ($c | startswith("✅ Reviewed")) then ($c | split(" · ")[1:]) else [] end) as $prev
  | (($prev | map(select(startswith($who + " ") | not))) + ["\($who) \($verb)"]) as $entries
  | {
      content: (["✅ Reviewed"] + $entries | join(" · ")),
      embeds: ($msg.embeds // [] | map(
        {title, url, description, color, fields, footer} | with_entries(select(.value != null))
        | .color = (if any($entries[]; endswith(" requested changes")) then 15548997
                    elif any($entries[]; endswith(" approved")) then 5763719
                    else .color end))),
      allowed_mentions: { parse: [] }
    }'
