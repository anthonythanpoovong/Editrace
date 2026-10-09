#!/usr/bin/env bash
# Works out who to ping to review again after new commits were pushed to an approved PR (#177).
# Inputs (env): REVIEWS (JSON array of the PR's reviews from the API: user.login, user.type, state,
# commit_id, submitted_at), BEFORE (the head SHA the push replaced).
# Optional (env): EXCLUDE (JSON array of logins never to ping, e.g. the pusher and the PR author).
# A reviewer is pinged when their latest decision (APPROVED, DISMISSED or CHANGES_REQUESTED;
# plain COMMENTED reviews do not count) is an approval or a dismissal made on BEFORE. DISMISSED
# counts because the repo dismisses stale approvals on push, and that can land after the event.
# Only the first push after an approval matches BEFORE, so a run of pushes pings once.
# Prints a JSON array of logins.
set -euo pipefail

jq -e 'type == "array"' <<<"${REVIEWS:?}" > /dev/null || { echo "REVIEWS must be a JSON array" >&2; exit 1; }
[[ "${BEFORE:?}" =~ ^[0-9a-f]{7,40}$ ]] || { echo "BEFORE must be a commit SHA" >&2; exit 1; }
jq -e 'type == "array"' <<<"${EXCLUDE:-[]}" > /dev/null || { echo "EXCLUDE must be a JSON array" >&2; exit 1; }

jq -n --argjson reviews "$REVIEWS" --argjson exclude "${EXCLUDE:-[]}" --arg before "$BEFORE" '
  ($exclude | map(ascii_downcase)) as $skip
  | $reviews
  | map(select(.user != null and .user.type != "Bot"
      and (.state | ascii_upcase | IN("APPROVED", "DISMISSED", "CHANGES_REQUESTED"))))
  | group_by(.user.login | ascii_downcase)
  | map(sort_by(.submitted_at) | last)
  | map(select((.state | ascii_upcase | IN("APPROVED", "DISMISSED")) and .commit_id == $before))
  | map(.user.login)
  | map(select((. | ascii_downcase) as $l | $skip | index($l) | not))'
