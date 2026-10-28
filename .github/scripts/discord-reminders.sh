#!/usr/bin/env bash
# Sends the Discord reminders that are due right now (#184): the weekly sync the day before, the
# weekly sync when it starts, and "sprint due tomorrow". See discord-reminder-due.sh for the rules.
# Inputs (env): ROLE_ID, and WEBHOOK, GITHUB_REPOSITORY, GITHUB_SHA unless DRY_RUN is true.
# Each reminder is sent once: before posting, it creates the git ref refs/reminders/<key> (for example
# meeting_eve-2026-10-14). Creating a ref is atomic and fails if it exists, so a second run that falls in
# the same window finds it taken and skips. If the post fails the ref is deleted so a later run can retry.
# GH_TOKEN reads the board; CLAIM_TOKEN (the workflow's GITHUB_TOKEN, contents: write) makes the refs.
# Optional (env): CONFIG_FILE (default .github/reminders.json), DRY_RUN (true prints the payloads
# and posts nothing), NOW (a UTC timestamp like 2026-10-13T18:30:00Z to simulate; dry runs only),
# GH_TOKEN (a token with the "project" scope, needed only when the board is read).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

config_file=${CONFIG_FILE:-"$here/../reminders.json"}
config=$(cat "$config_file")
jq -e . <<<"$config" > /dev/null || { echo "$config_file is not valid JSON" >&2; exit 1; }
dry=${DRY_RUN:-false}
case "$dry" in true|false) ;; *) echo "DRY_RUN must be true or false" >&2; exit 1 ;; esac
if [ -n "${NOW:-}" ]; then
  [[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "NOW must look like 2026-10-13T18:30:00Z" >&2; exit 1; }
  [ "$dry" = true ] || { echo "NOW can only be used with DRY_RUN=true, so a simulated time never posts" >&2; exit 1; }
  now_epoch=$(jq -nr --arg n "$NOW" '$n | fromdate')
else
  now_epoch=$(date +%s)
fi
if [ "$dry" = false ]; then
  : "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${CLAIM_TOKEN:?}"
  [[ "${WEBHOOK:?}" =~ ^https://(discord|discordapp)\.com/api/webhooks/ ]] \
    || { echo "The Discord webhook secret is missing or not a Discord webhook URL" >&2; exit 1; }
fi
: "${ROLE_ID:?}"

result=$(CONFIG="$config" NOW="$now_epoch" SPRINTS=null "$here/discord-reminder-due.sh")

# Only read the board in the sprint reminder's window, so a missing token only matters then.
if [ "$(jq -r .sprint_window <<<"$result")" = true ]; then
  owner=$(jq -r .project.owner <<<"$config"); number=$(jq -r .project.number <<<"$config")
  [[ "$owner" =~ ^[A-Za-z0-9-]{1,39}$ && "$number" =~ ^[0-9]+$ ]] || { echo "reminders.json project owner or number is invalid" >&2; exit 1; }
  if ! board=$(gh api graphql -f query='query($o: String!, $n: Int!) { repositoryOwner(login: $o) { ... on ProjectV2Owner { projectV2(number: $n) {
        field(name: "Sprint") { ... on ProjectV2IterationField { configuration { iterations { title startDate duration } } } } } } } }' \
        -f o="$owner" -F n="$number"); then
    echo "Could not read the sprints from the board (is PROJECT_TOKEN valid and has the project scope?): $board" >&2; exit 1
  fi
  [ "$(jq -c '.data.repositoryOwner.projectV2' <<<"$board")" != null ] \
    || { echo "Project #$number not found for $owner, or PROJECT_TOKEN cannot access it (it needs the project scope and access to that project)" >&2; exit 1; }
  sprints=$(jq -ce '.data.repositoryOwner.projectV2.field.configuration.iterations' <<<"$board") \
    || { echo "The board has no Sprint iteration field" >&2; exit 1; }
  result=$(CONFIG="$config" NOW="$now_epoch" SPRINTS="$sprints" "$here/discord-reminder-due.sh")
fi

count=$(jq '.due | length' <<<"$result")
if [ "$count" -eq 0 ]; then echo "No reminder is due now."; exit 0; fi

while read -r item; do
  kind=$(jq -r .kind <<<"$item"); key=$(jq -r .key <<<"$item")
  payload=$(KIND="$kind" CONFIG="$config" ROLE_ID="$ROLE_ID" \
    MEETING_EPOCH="$(jq -r '.meeting_epoch // 0' <<<"$item")" \
    SPRINT_TITLE="$(jq -r '.sprint_title // ""' <<<"$item")" \
    DUE_LABEL="$(jq -r '.due_label // ""' <<<"$item")" "$here/discord-reminder-payload.sh" | jq -c .)
  if [ "$dry" = true ]; then
    echo "[dry run] $kind:"; jq . <<<"$payload"
  else
    if ! claim=$(GH_TOKEN=$CLAIM_TOKEN gh api -X POST "repos/$GITHUB_REPOSITORY/git/refs" \
          -f ref="refs/reminders/$key" -f sha="$GITHUB_SHA" 2>&1); then
      if [[ "$claim" == *"Reference already exists"* ]]; then echo "Already sent $key, skipping"; continue; fi
      echo "Could not record $key as sent: $claim" >&2; exit 1
    fi
    if ! curl --fail --silent --show-error --max-time 20 -H "Content-Type: application/json" --data "$payload" "$WEBHOOK"; then
      GH_TOKEN=$CLAIM_TOKEN gh api -X DELETE "repos/$GITHUB_REPOSITORY/git/refs/reminders/$key" > /dev/null 2>&1 || true
      echo "Posting $key to Discord failed" >&2; exit 1
    fi
    echo "Sent $key"
  fi
done < <(jq -c '.due[]' <<<"$result")
