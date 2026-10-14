#!/usr/bin/env bash
# Decides which Discord reminders are due right now (#184). Prints
# {"due":[...],"sprint_window":true|false}.
# Inputs (env): CONFIG (the reminders.json contents), NOW (epoch seconds; default: the current time).
# Optional (env): SPRINTS (JSON array of {title,startDate,duration} from the project's Sprint field;
# null or unset when not fetched yet). When SPRINTS is not given, "sprint_window" says whether it is
# the time of day to look at sprints, so the caller only reads the board when it matters.
# Everything is judged in the config's timezone, not UTC, so daylight saving cannot shift a
# reminder: the workflow runs at both the summer and the winter UTC hour and only the one that
# lands in the window sends. Windows: meeting eve = the meeting time to +8 h on the day before;
# meeting start = the meeting time to +30 min (later than that is too late for "starts now");
# sprint due = remind_at to +8 h on the day before the sprint's last day. The last day is startDate + duration - 1 (the Sprint field on
# the board: Sep 30 + 15 days = last day Wed Oct 14, so the ping is Tue Oct 13). The long windows are
# because GitHub starts scheduled runs hours late and sometimes drops one; both cron entries can now
# fall inside a window, so discord-reminders.sh sends each item's "key" at most once.
# Weekdays are ISO: 1 = Monday ... 7 = Sunday. Dates are YYYY-MM-DD.
set -euo pipefail

config=${CONFIG:?}
now=${NOW:-$(date +%s)}
[[ "$now" =~ ^[0-9]+$ ]] || { echo "NOW must be epoch seconds" >&2; exit 1; }
sprints=${SPRINTS:-null}
jq -e '. == null or (type == "array")' <<<"$sprints" > /dev/null || { echo "SPRINTS must be a JSON array or null" >&2; exit 1; }

tz=$(jq -er '.timezone' <<<"$config")
[[ "$tz" =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$ ]] || { echo "timezone is not an IANA name" >&2; exit 1; }
hm='^([01][0-9]|2[0-3]):[0-5][0-9]$'
jq -e --arg re "$hm" '
  (.meeting.weekday | type == "number" and . >= 1 and . <= 7 and . == floor)
  and (.meeting.start | test($re)) and (.sprint.remind_at | test($re))
  and ((.meeting.skip // []) | all(type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))' \
  <<<"$config" > /dev/null || { echo "reminders.json has an invalid weekday, time or skip date" >&2; exit 1; }

TZ="$tz" jq -n --argjson c "$config" --argjson now "$now" --argjson sprints "$sprints" '
  def local($t): $t | strflocaltime("%Y-%m-%d %u %H:%M") | capture("^(?<date>[^ ]+) (?<wd>[0-9]) (?<h>[0-9]{2}):(?<m>[0-9]{2})$")
                 | {date, wd: (.wd | tonumber), min: ((.h | tonumber) * 60 + (.m | tonumber))};
  def minutes($hm): ($hm | split(":") | (.[0] | tonumber) * 60 + (.[1] | tonumber));
  def in_window($m; $from; $len): $m >= $from and $m < $from + $len;
  # The epoch of a local date + time, found by trying each whole-hour UTC offset.
  def local_epoch($date; $hm):
    (($date + "T" + $hm + ":00Z") | fromdate) as $naive
    | [range(-14; 15)] | map($naive - . * 3600)
    | map(select(strflocaltime("%Y-%m-%d %H:%M") == ($date + " " + $hm))) | .[0];
  def day_of($epoch): $epoch | strflocaltime("%Y-%m-%d");
  (local($now)) as $l
  | ($now + 86400) as $tomorrow_epoch
  | (day_of($tomorrow_epoch)) as $tomorrow
  | ($c.meeting.skip // []) as $skip
  | minutes($c.meeting.start) as $start
  | minutes($c.sprint.remind_at) as $remind
  | ((($c.meeting.weekday + 5) % 7) + 1) as $eve_wd
  | in_window($l.min; $remind; 480) as $sprint_window
  | ( [ if $l.wd == $eve_wd and in_window($l.min; $start; 480) and ($skip | index($tomorrow) | not)
        then {kind: "meeting_eve", key: ("meeting_eve-" + $tomorrow), meeting_date: $tomorrow, meeting_epoch: local_epoch($tomorrow; $c.meeting.start)} else empty end,
        if $l.wd == $c.meeting.weekday and in_window($l.min; $start; 30) and ($skip | index($l.date) | not)
        then {kind: "meeting_start", key: ("meeting_start-" + $l.date), meeting_date: $l.date, meeting_epoch: local_epoch($l.date; $c.meeting.start)} else empty end,
        ( if $sprint_window and $sprints != null then
            $sprints[] | select(.startDate | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
            | ((.startDate + "T00:00:00Z" | fromdate) + (.duration - 1) * 86400) as $end
            | select(($end | todate | .[0:10]) == $tomorrow)
            | {kind: "sprint_due", key: ("sprint_due-" + $tomorrow), sprint_title: .title, due_date: $tomorrow,
               due_label: ($end | strftime("%A, %B %d") | sub(" 0"; " "))}
          else empty end ) ] ) as $due
  | {due: $due, sprint_window: $sprint_window}'
