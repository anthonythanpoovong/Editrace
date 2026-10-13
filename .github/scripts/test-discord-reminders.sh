#!/usr/bin/env bash
# Tests for the Discord reminder scripts (#184). Run: .github/scripts/test-discord-reminders.sh
set -uo pipefail
cd "$(dirname "$0")"
here=$(pwd)
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

CONFIG=$(cat ../reminders.json)
ep() { jq -nr --arg t "$1" '$t | fromdate'; }
due() { # UTC timestamp, optional SPRINTS json, optional CONFIG override
  CONFIG="${3:-$CONFIG}" NOW="$(ep "$1")" SPRINTS="${2:-null}" ./discord-reminder-due.sh
}
kinds() { jq -r '[.due[].kind] | join(",")' <<<"$1"; }
SPRINTS='[{"title":"Sprint 1","startDate":"2026-10-05","duration":14},{"title":"Sprint 2","startDate":"2026-10-19","duration":14}]'

# --- meeting eve: Tuesday, 2:30 to 10:30 PM Eastern (8 hours, for late scheduled runs) ---
[ "$(kinds "$(due 2026-10-13T18:30:00Z)")" = meeting_eve ]; check "eve: Tuesday 2:30 PM EDT (summer)" $?
[ "$(kinds "$(due 2026-11-03T19:30:00Z)")" = meeting_eve ]; check "eve: Tuesday 2:30 PM EST (winter)" $?
[ "$(kinds "$(due 2026-10-13T19:30:00Z)")" = meeting_eve ]; check "eve: the other cron entry in summer (3:30 PM) is also in the window (deduped by key)" $?
[ "$(kinds "$(due 2026-11-03T18:30:00Z)")" = "" ]; check "eve: the other cron entry in winter (1:30 PM) does not send" $?
[ "$(kinds "$(due 2026-10-13T18:59:00Z)")" = meeting_eve ]; check "eve: a run 29 minutes late still sends" $?
[ "$(kinds "$(due 2026-10-13T19:29:00Z)")" = meeting_eve ]; check "eve: a run 59 minutes late still sends" $?
[ "$(kinds "$(due 2026-10-13T22:30:00Z)")" = meeting_eve ]; check "eve: a run 4 hours late (6:30 PM) still sends" $?
[ "$(kinds "$(due 2026-10-14T02:29:00Z)")" = meeting_eve ]; check "eve: a run just before 10:30 PM still sends" $?
[ "$(kinds "$(due 2026-10-14T02:31:00Z)")" = "" ]; check "eve: after 10:30 PM it does not send" $?
[ "$(kinds "$(due 2026-10-13T18:29:00Z)")" = "" ]; check "eve: before 2:30 PM it does not send" $?
[ "$(kinds "$(due 2026-10-14T18:30:00Z)")" != *meeting_eve* ]; check "eve: not on the meeting day itself" $?
[ "$(kinds "$(due 2026-10-12T18:30:00Z)")" = "" ]; check "eve: not on Monday" $?
e=$(due 2026-10-13T18:30:00Z); [ "$(jq -r '.due[0].meeting_epoch' <<<"$e")" = "$(ep 2026-10-14T18:30:00Z)" ] && [ "$(jq -r '.due[0].meeting_date' <<<"$e")" = 2026-10-14 ]
check "eve: carries the meeting's own time (Wednesday 14:30 EDT)" $?
e=$(due 2026-11-03T19:30:00Z); [ "$(jq -r '.due[0].meeting_epoch' <<<"$e")" = "$(ep 2026-11-04T19:30:00Z)" ]
check "eve: the meeting time is 14:30 EST in winter (19:30 UTC)" $?

# --- meeting start: Wednesday, 2:30 to 3:00 PM Eastern ---
[ "$(kinds "$(due 2026-10-14T18:30:00Z)")" = meeting_start ]; check "start: Wednesday 2:30 PM EDT" $?
[ "$(kinds "$(due 2026-11-04T19:30:00Z)")" = meeting_start ]; check "start: Wednesday 2:30 PM EST" $?
[ "$(kinds "$(due 2026-10-14T19:30:00Z)")" = "" ]; check "start: the other cron entry (3:30 PM) does not send" $?
[ "$(kinds "$(due 2026-10-14T18:55:00Z)")" = meeting_start ]; check "start: 25 minutes late still sends" $?
[ "$(kinds "$(due 2026-10-14T19:05:00Z)")" = "" ]; check "start: 35 minutes late is too late for 'starts now'" $?
[ "$(kinds "$(due 2026-10-15T18:30:00Z)")" = "" ]; check "start: not on Thursday" $?

# --- daylight saving changeovers ---
[ "$(kinds "$(due 2026-10-27T18:30:00Z)")" = meeting_eve ]; check "dst: last summer Tuesday (Oct 27) still 18:30 UTC" $?
[ "$(kinds "$(due 2026-11-03T19:30:00Z)")" = meeting_eve ] && [ "$(kinds "$(due 2026-11-03T18:30:00Z)")" = "" ]
check "dst: first winter Tuesday (Nov 3) moves to 19:30 UTC" $?
[ "$(kinds "$(due 2027-03-09T19:30:00Z)")" = meeting_eve ]; check "dst: Tuesday Mar 9 2027 (still winter) at 19:30 UTC" $?
[ "$(kinds "$(due 2027-03-16T18:30:00Z)")" = meeting_eve ]; check "dst: Tuesday Mar 16 2027 (summer again) at 18:30 UTC" $?
[ "$(kinds "$(due 2027-03-17T18:30:00Z)")" = meeting_start ]; check "dst: Wednesday Mar 17 2027 start at 18:30 UTC" $?
n=0; for t in 18:30 19:30; do [ -n "$(kinds "$(due 2026-10-13T${t}:00Z)")" ] && n=$((n+1)); done; [ "$n" -ge 1 ]
check "at least one of the two cron times is due in summer" $?
n=0; for t in 18:30 19:30; do [ -n "$(kinds "$(due 2026-11-03T${t}:00Z)")" ] && n=$((n+1)); done; [ "$n" -ge 1 ]
check "at least one of the two cron times is due in winter" $?
[ "$(jq -r '.due[0].key' <<<"$(due 2026-10-13T18:30:00Z)")" = "$(jq -r '.due[0].key' <<<"$(due 2026-10-13T19:30:00Z)")" ] && [ "$(jq -r '.due[0].key' <<<"$(due 2026-10-13T18:30:00Z)")" = meeting_eve-2026-10-14 ]
check "both cron times in a window give the same key, so they dedupe" $?
[ "$(jq -r '.due[0].key' <<<"$(due 2026-10-14T18:30:00Z)")" = meeting_start-2026-10-14 ]; check "start: the key names the meeting date" $?

# --- skip dates ---
skip=$(jq '.meeting.skip = ["2026-10-14"]' <<<"$CONFIG")
[ "$(kinds "$(due 2026-10-13T18:30:00Z "" "$skip")")" = "" ]; check "skip: no eve reminder for a skipped meeting date" $?
[ "$(kinds "$(due 2026-10-14T18:30:00Z "" "$skip")")" = "" ]; check "skip: no start reminder on a skipped date" $?
[ "$(kinds "$(due 2026-10-20T18:30:00Z "" "$skip")")" = meeting_eve ]; check "skip: other weeks are unaffected" $?

# --- config drives it ---
mon=$(jq '.meeting.weekday = 5 | .meeting.start = "10:00"' <<<"$CONFIG")
[ "$(kinds "$(due 2026-10-15T14:00:00Z "" "$mon")")" = meeting_eve ]; check "config: Friday 10:00 meeting -> Thursday 10:00 EDT eve" $?
[ "$(kinds "$(due 2026-10-16T14:00:00Z "" "$mon")")" = meeting_start ]; check "config: Friday 10:00 meeting -> Friday 10:00 EDT start" $?
sun=$(jq '.meeting.weekday = 1' <<<"$CONFIG")
[ "$(kinds "$(due 2026-10-18T18:30:00Z "" "$sun")")" = meeting_eve ]; check "config: Monday meeting -> eve on Sunday (week wraps)" $?

# --- sprint due: 9:00 AM Eastern the day before the last day ---
s=$(due 2026-10-17T13:00:00Z "$SPRINTS")
[ "$(kinds "$s")" = sprint_due ] && [ "$(jq -r '.due[0].sprint_title' <<<"$s")" = "Sprint 1" ] && [ "$(jq -r '.due[0].due_label' <<<"$s")" = "Sunday, October 18" ]
check "sprint: Saturday 9:00 AM EDT before the Sunday Oct 18 end" $?
[ "$(kinds "$(due 2026-10-16T13:00:00Z "$SPRINTS")")" = "" ]; check "sprint: nothing on Friday" $?
[ "$(kinds "$(due 2026-10-18T13:00:00Z "$SPRINTS")")" = "" ]; check "sprint: nothing on the last day itself" $?
[ "$(kinds "$(due 2026-10-17T14:00:00Z "$SPRINTS")")" = sprint_due ]; check "sprint: 10:00 AM (a late run) is still in the window" $?
[ "$(kinds "$(due 2026-10-17T20:59:00Z "$SPRINTS")")" = sprint_due ]; check "sprint: just before 5:00 PM is still in the window" $?
[ "$(kinds "$(due 2026-10-17T21:01:00Z "$SPRINTS")")" = "" ]; check "sprint: after 5:00 PM is out of the window" $?
[ "$(jq -r '.due[0].key' <<<"$(due 2026-10-17T13:00:00Z "$SPRINTS")")" = sprint_due-2026-10-18 ]; check "sprint: the key names the due date" $?
[ "$(kinds "$(due 2026-10-17T12:00:00Z "$SPRINTS")")" = "" ]; check "sprint: 8:00 AM is out of the window" $?
[ "$(kinds "$(due 2026-10-31T13:00:00Z "$SPRINTS")")" = sprint_due ] && [ "$(jq -r '.due[0].sprint_title' <<<"$(due 2026-10-31T13:00:00Z "$SPRINTS")")" = "Sprint 2" ]
check "sprint: the next sprint ends Sunday Nov 1 (daylight saving ends that night)" $?
[ "$(kinds "$(due 2026-11-14T14:00:00Z "$(jq -c '. + [{"title":"Sprint 3","startDate":"2026-11-02","duration":14}]' <<<"$SPRINTS")")")" = sprint_due ]
check "sprint: winter 9:00 AM EST is 14:00 UTC" $?
[ "$(kinds "$(due 2026-10-17T13:00:00Z '[]')")" = "" ]; check "sprint: no sprints means nothing is sent" $?
[ "$(jq -r .sprint_window <<<"$(due 2026-10-17T13:00:00Z)")" = true ] && [ "$(jq -r .sprint_window <<<"$(due 2026-10-17T22:00:00Z)")" = false ]
check "sprint_window tells the caller when to read the board" $?
[ "$(kinds "$(due 2026-10-17T13:00:00Z "$(jq -c '.[0].startDate = "not a date"' <<<"$SPRINTS")")")" = "" ]; check "sprint: a malformed start date is ignored, not fatal" $?

# --- bad input ---
bad=$(jq '.meeting.start = "25:99"' <<<"$CONFIG"); due 2026-10-13T18:30:00Z "" "$bad" > /dev/null 2>&1; [ $? -ne 0 ]; check "a bad time in the config is rejected" $?
bad=$(jq '.timezone = "Not a zone; rm"' <<<"$CONFIG"); due 2026-10-13T18:30:00Z "" "$bad" > /dev/null 2>&1; [ $? -ne 0 ]; check "a bad timezone name is rejected" $?
bad=$(jq '.meeting.weekday = 9' <<<"$CONFIG"); due 2026-10-13T18:30:00Z "" "$bad" > /dev/null 2>&1; [ $? -ne 0 ]; check "a bad weekday is rejected" $?
CONFIG="$CONFIG" NOW=abc ./discord-reminder-due.sh > /dev/null 2>&1; [ $? -ne 0 ]; check "a non-numeric NOW is rejected" $?

# --- payloads ---
pl() { KIND="$1" CONFIG="${PLCONFIG:-$CONFIG}" ROLE_ID=999 MEETING_EPOCH=1792002600 SPRINT_TITLE="${SPRINT_TITLE:-Sprint 1}" DUE_LABEL="Sunday, October 18" ./discord-reminder-payload.sh; }
out=$(pl meeting_start)
[ "$(jq -r .content <<<"$out")" = $'<@&999> 🟢 Editrace weekly sync starts now\nhttps://meet.google.com/xmq-csjt-npw' ]; check "payload: 'Editrace weekly sync starts now' with the Meet link" $?
[ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[],"roles":["999"]}' ]; check "payload: only the role can be pinged" $?
out=$(pl meeting_eve)
[ "$(jq -r .content <<<"$out")" = '<@&999> 📅 Editrace Weekly Sync is tomorrow: <t:1792002600:F> (<t:1792002600:R>)' ]; check "payload: eve shows the time in each reader's timezone" $?
d=$(jq -r '.embeds[0].description' <<<"$out"); [[ "$d" == *'Come prepared'* && "$d" == *'What you are blocked by'* && "$d" == *'(https://meet.google.com/xmq-csjt-npw)' ]]
check "payload: eve lists the agenda and the Meet link" $?
out=$(pl sprint_due)
[ "$(jq -r .content <<<"$out")" = '<@&999> ⏰ Sprint due tomorrow' ] && [ "$(jq -r '.embeds[0].title' <<<"$out")" = 'Sprint 1 ends Sunday, October 18' ] && jq -r '.embeds[0].description' <<<"$out" | grep -q 'projects/2'
check "payload: 'Sprint due tomorrow' with the sprint, due date and board link" $?
out=$(SPRINT_TITLE='@everyone **x** [a](http://evil.test)' pl sprint_due)
! jq -r '.embeds[0].title' <<<"$out" | grep -qE '@everyone|\]\(http' && [ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[],"roles":["999"]}' ]
check "payload: a sprint title cannot ping or render a link" $?
evil=$(jq '.meeting.agenda = ["@everyone <@123> [x](http://evil.test)"] | .meeting.name = "@here **Sync**"' <<<"$CONFIG")
out=$(PLCONFIG="$evil" pl meeting_eve)
! jq -r '.content,.embeds[0].title,.embeds[0].description' <<<"$out" | grep -E '@everyone|@here|<@123>|\[x\]\(http' | grep -v 'Join the Google Meet' | grep -q . && [ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[],"roles":["999"]}' ]
check "payload: agenda and name text cannot ping or render links" $?
for edit in '.meeting.meet_url = "https://evil.test/x"' '.meeting.meet_url = "https://meet.google.com/x) [y](http://evil"' '.project.url = "https://evil.test/p"' '.meeting.agenda = ["a","b","c","d","e","f","g","h","i","j","k"]'; do
  PLCONFIG=$(jq "$edit" <<<"$CONFIG") pl meeting_eve > /dev/null 2>&1; [ $? -ne 0 ]; check "payload rejects: $edit" $?
done
KIND=nope CONFIG="$CONFIG" ROLE_ID=999 ./discord-reminder-payload.sh > /dev/null 2>&1; [ $? -ne 0 ]; check "payload: an unknown kind is rejected" $?
KIND=meeting_start CONFIG="$CONFIG" ROLE_ID=abc MEETING_EPOCH=1 ./discord-reminder-payload.sh > /dev/null 2>&1; [ $? -ne 0 ]; check "payload: a non-numeric role is rejected" $?

# --- the cron lines in the workflow must match the config ---
# GitHub cron is fixed UTC, so a meeting time or day changed in reminders.json needs matching cron
# lines. For a summer and a winter date, work out the UTC weekday, hour and minute of each reminder
# from the config and require some cron line to fire then.
wf=../workflows/discord-reminders.yml
crons=$(grep -E '^\s*- cron:' "$wf" | sed -E 's/.*cron: *"([^"]+)".*/\1/')
tz=$(jq -r .timezone <<<"$CONFIG")
utc_slots() { # ISO weekday, local HH:MM -> "utc_dow hour minute" for one summer and one winter date
  for base in 2026-07-06 2027-01-04; do # both Mondays
    TZ="$tz" jq -nr --arg base "$base" --argjson wd "$1" --arg hm "$2" '
      (($base + "T00:00:00Z") | fromdate) as $mon
      | ($mon + ($wd - 1) * 86400 | todate | .[0:10]) as $date
      | (($date + "T" + $hm + ":00Z") | fromdate) as $naive
      | ([range(-14; 15)] | map($naive - . * 3600) | map(select(strflocaltime("%Y-%m-%d %H:%M") == ($date + " " + $hm))) | .[0]) as $e
      | $e | strftime("%w %-H %-M")'
  done
}
cron_fires() { # utc_dow hour minute
  local dow=$1 hour=$2 min=$3 line m h d
  while read -r line; do
    read -r m h _ _ d <<<"$line"
    [ "$m" = "$min" ] || continue
    [[ ",$h," == *",$hour,"* ]] || continue
    [ "$d" = "*" ] || [[ ",$d," == *",$dow,"* ]] || continue
    return 0
  done <<<"$crons"
  return 1
}
start=$(jq -r .meeting.start <<<"$CONFIG"); wd=$(jq -r .meeting.weekday <<<"$CONFIG"); eve=$(( (wd + 5) % 7 + 1 ))
remind=$(jq -r .sprint.remind_at <<<"$CONFIG")
missing=""
while read -r dow hour min; do cron_fires "$dow" "$hour" "$min" || missing="$missing meeting-start(utc weekday $dow $hour:$min)"; done < <(utc_slots "$wd" "$start")
while read -r dow hour min; do cron_fires "$dow" "$hour" "$min" || missing="$missing meeting-eve(utc weekday $dow $hour:$min)"; done < <(utc_slots "$eve" "$start")
for d in 1 2 3 4 5 6 7; do
  while read -r dow hour min; do cron_fires "$dow" "$hour" "$min" || missing="$missing sprint(utc weekday $dow $hour:$min)"; done < <(utc_slots "$d" "$remind")
done
[ -z "$missing" ]; check "the workflow's cron lines cover every reminder time in reminders.json (missing:${missing:- none})" $?

# A config change that moves the meeting must be caught: a 10:00 meeting is not covered by the crons.
cfg_moved=$(jq '.meeting.start = "10:00"' <<<"$CONFIG")
saved=$CONFIG; CONFIG=$cfg_moved
start2=$(jq -r .meeting.start <<<"$CONFIG"); miss2=0
while read -r dow hour min; do cron_fires "$dow" "$hour" "$min" || miss2=1; done < <(utc_slots "$wd" "$start2")
CONFIG=$saved; [ "$miss2" -eq 1 ]; check "the cron check does notice a meeting moved to a time the crons do not cover" $?

# --- orchestrator, against fake gh and curl ---
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/curl" <<'FAKE'
#!/usr/bin/env bash
data=""; while [ $# -gt 0 ]; do case "$1" in --data) data="$2"; shift ;; esac; shift; done
[ -z "${FAKE_CURL_FAIL:-}" ] || exit 22
printf '%s\n' "$data" >> "$FAKE_SENT"
FAKE
cat > "$tmp/gh" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = api ] && [[ "$*" == *git/refs* ]]; then # claim refs: POST creates, DELETE releases
  echo "$GH_TOKEN $*" >> "$FAKE_REF_CALLS"
  [ -z "${FAKE_REF_FAIL:-}" ] || { echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1; }
  if [ "$2" = "-X" ] && [ "$3" = POST ]; then
    ref=$(sed -n 's/.*ref=\(refs[^ ]*\).*/\1/p' <<<"$*")
    grep -qxF "$ref" "$FAKE_REFS" 2>/dev/null && { echo '{"message":"Reference already exists"}gh: Reference already exists (HTTP 422)' >&2; exit 1; }
    echo "$ref" >> "$FAKE_REFS"
  else
    ref="refs/${4##*git/refs/}"; grep -vxF "$ref" "$FAKE_REFS" > "$FAKE_REFS.n"; mv "$FAKE_REFS.n" "$FAKE_REFS"
  fi
  exit 0
fi
echo gh >> "$FAKE_GH_CALLS"
[ -z "${FAKE_GH_FAIL:-}" ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }
echo '{"data":{"user":{"projectV2":{"field":{"configuration":{"iterations":[{"title":"Sprint 1","startDate":"2026-10-05","duration":14}]}}}}}}'
FAKE
chmod +x "$tmp/curl" "$tmp/gh"
export FAKE_SENT="$tmp/sent" FAKE_GH_CALLS="$tmp/gh_calls" FAKE_REF_CALLS="$tmp/ref_calls" FAKE_REFS="$tmp/refs"
run() { : > "$FAKE_SENT"; : > "$FAKE_GH_CALLS"; : > "$FAKE_REF_CALLS"
  env PATH="$tmp:$PATH" ROLE_ID=999 WEBHOOK=https://discord.com/api/webhooks/1/x GITHUB_REPOSITORY=o/r GITHUB_SHA=abc123 CLAIM_TOKEN=claimtok \
    "$@" "$here/discord-reminders.sh" > "$tmp/out" 2>&1; }
runreal() { : > "$FAKE_REFS"; run "$@"; } # a real run starting with no reminder sent yet

run DRY_RUN=true NOW=2026-10-14T18:30:00Z; [ "$?" -eq 0 ] && grep -q 'starts now' "$tmp/out" && [ ! -s "$FAKE_SENT" ]
check "orchestrator: a dry run prints the message and posts nothing" $?
run DRY_RUN=false; grep -q "No reminder" "$tmp/out" || grep -q "Sent" "$tmp/out"
check "orchestrator: a real run at the current time works (nothing due or one sent)" $?
run DRY_RUN=true NOW=2026-10-13T22:00:00Z; grep -q 'is tomorrow' "$tmp/out" && ! [ -s "$FAKE_GH_CALLS" ]
check "orchestrator: a meeting reminder does not read the board" $?
run DRY_RUN=true NOW=2026-10-17T13:00:00Z; [ "$?" -eq 0 ] && grep -q 'Sprint due tomorrow' "$tmp/out" && [ "$(wc -l < "$FAKE_GH_CALLS")" -eq 1 ]
check "orchestrator: the sprint reminder reads the board once" $?
run DRY_RUN=true NOW=2026-10-17T13:00:00Z FAKE_GH_FAIL=1; [ "$?" -ne 0 ] && grep -q "PROJECT_TOKEN" "$tmp/out"
check "orchestrator: an unreadable board fails loudly and names PROJECT_TOKEN" $?
run DRY_RUN=false NOW=2026-10-14T18:30:00Z; [ "$?" -ne 0 ] && grep -q "DRY_RUN=true" "$tmp/out"
check "orchestrator: a simulated time can never post" $?
run DRY_RUN=true NOW=2026-10-14T18:30:00 ; [ "$?" -ne 0 ]
check "orchestrator: a malformed NOW is rejected" $?
run DRY_RUN=false WEBHOOK=nope; [ "$?" -ne 0 ]
check "orchestrator: a bad webhook URL fails" $?

# --- each reminder is sent once ---
# A real run needs the clock inside a window; the fake `date` pins it to Tuesday 2026-10-13 3:30 PM EDT.
cat > "$tmp/date" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "+%s" ]; then jq -nr '"2026-10-13T19:30:00Z" | fromdate'; else /bin/date "$@"; fi
FAKE
chmod +x "$tmp/date"
runreal; [ "$?" -eq 0 ] && grep -q "Sent meeting_eve-2026-10-14" "$tmp/out" && [ "$(wc -l < "$FAKE_SENT")" -eq 1 ] && [ "$(cat "$FAKE_REFS")" = refs/reminders/meeting_eve-2026-10-14 ]
check "once: the first run posts the reminder and records it as sent" $?
grep -q "claimtok api -X POST repos/o/r/git/refs -f ref=refs/reminders/meeting_eve-2026-10-14 -f sha=abc123" "$FAKE_REF_CALLS"
check "once: the claim uses CLAIM_TOKEN, the repo and the commit" $?
run; [ "$?" -eq 0 ] && grep -q "Already sent meeting_eve-2026-10-14" "$tmp/out" && [ ! -s "$FAKE_SENT" ]
check "once: a second run in the same window posts nothing" $?
runreal FAKE_CURL_FAIL=1; [ "$?" -ne 0 ] && grep -q "failed" "$tmp/out" && [ ! -s "$FAKE_REFS" ]
check "once: a failed post releases the claim so a later run can retry" $?
run; [ "$?" -eq 0 ] && grep -q "Sent meeting_eve" "$tmp/out" && [ "$(wc -l < "$FAKE_SENT")" -eq 1 ]
check "once: after a failed post, the retry sends it" $?
runreal FAKE_REF_FAIL=1; [ "$?" -ne 0 ] && grep -q "Could not record" "$tmp/out" && [ ! -s "$FAKE_SENT" ]
check "once: if the claim itself fails, nothing is posted and the run fails" $?
runreal DRY_RUN=true; [ "$?" -eq 0 ] && grep -q "dry run" "$tmp/out" && [ ! -s "$FAKE_REF_CALLS" ] && [ ! -s "$FAKE_SENT" ]
check "once: a dry run neither posts nor claims" $?
runreal CLAIM_TOKEN= ; [ "$?" -ne 0 ]
check "once: a real run without CLAIM_TOKEN fails" $?
exit $fail
