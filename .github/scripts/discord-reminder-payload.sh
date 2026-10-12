#!/usr/bin/env bash
# Builds the Discord webhook JSON for one reminder (#184).
# Inputs (env): KIND (meeting_eve | meeting_start | sprint_due), CONFIG (the reminders.json
# contents), ROLE_ID (the role to ping).
# By kind: meeting_eve and meeting_start need MEETING_EPOCH; sprint_due needs SPRINT_TITLE,
# DUE_LABEL (e.g. "Sunday, October 18").
# Config text (names, agenda, links) and the sprint title come from the repo or the board, so they
# are still treated as untrusted: URLs must match fixed patterns, every "@" is defused, Markdown is
# escaped, and allowed_mentions lets exactly one target ping (the role).
set -euo pipefail

[[ "${ROLE_ID:?}" =~ ^[0-9]+$ ]] || { echo "ROLE_ID must be a numeric role ID" >&2; exit 1; }
case "${KIND:?}" in
  meeting_eve|meeting_start) [[ "${MEETING_EPOCH:?}" =~ ^[0-9]+$ ]] || { echo "MEETING_EPOCH must be epoch seconds" >&2; exit 1; } ;;
  sprint_due) : "${SPRINT_TITLE:?}" "${DUE_LABEL:?}" ;;
  *) echo "Unknown KIND: $KIND" >&2; exit 1 ;;
esac
config=${CONFIG:?}
jq -e '
  (.meeting.meet_url | test("^https://meet\\.google\\.com/[a-z0-9-]+$"))
  and (.project.url | test("^https://github\\.com/(users|orgs)/[A-Za-z0-9-]+/projects/[0-9]+$"))
  and (.meeting.name | type == "string" and length > 0 and length <= 100)
  and ((.meeting.agenda // []) | length <= 10 and all(type == "string" and length <= 200))' \
  <<<"$config" > /dev/null || { echo "reminders.json has an invalid link, name or agenda" >&2; exit 1; }

jq -n \
  --argjson c "$config" \
  --arg kind "$KIND" \
  --arg role "$ROLE_ID" \
  --arg epoch "${MEETING_EPOCH:-0}" \
  --arg sprint "${SPRINT_TITLE:-}" \
  --arg due "${DUE_LABEL:-}" '
  def defuse: gsub("@"; "@​");
  def md: gsub("(?<c>[\\\\`*_~|<>\\[\\]()#-])"; "\\\(.c)");
  def clean($n): tostring | gsub("\\s+"; " ") | .[:$n] | defuse | md;
  ($c.meeting.meet_url) as $meet
  | ($c.meeting.name | clean(100)) as $name
  | ($c.project.url) as $board
  | (($c.meeting.agenda // []) | map("• " + clean(200)) | join("\n")) as $agenda
  | (if $kind == "meeting_eve" then
       { content: "<@&\($role)> 📅 \($name) is tomorrow: <t:\($epoch):F> (<t:\($epoch):R>)",
         embed: { title: $name,
                  description: ((if $agenda != "" then "**Come prepared:**\n\($agenda)\n\n" else "" end) + "[Join the Google Meet](\($meet))"),
                  url: $meet, color: 5793266 } }
     elif $kind == "meeting_start" then
       { content: "<@&\($role)> 🟢 Editrace weekly sync starts now\n\($meet)",
         embed: { title: $name, description: "[Join the Google Meet](\($meet))", url: $meet, color: 5763719 } }
     else
       { content: "<@&\($role)> ⏰ Sprint due tomorrow",
         embed: { title: "\($sprint | clean(100)) ends \($due | clean(60))",
                  description: "Wrap up what you can and move what will not finish.\n[Open the board](\($board))",
                  url: $board, color: 15105570 } }
     end) as $m
  | { content: $m.content, embeds: [$m.embed], allowed_mentions: { parse: [], roles: [$role] } }'
