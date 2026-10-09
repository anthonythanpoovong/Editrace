#!/usr/bin/env bash
# Picks the sprint for a new issue (#178). Prints {"id","title","note"}.
# Inputs (env): ITERATIONS (JSON array of {id,title,startDate,duration} from the project's Sprint
# field), TODAY (YYYY-MM-DD, UTC). Current sprint: startDate <= TODAY < startDate + duration days.
# Between sprints it uses the next upcoming one and says so in "note". Exit 2 when there is no
# sprint to use (no iterations, or all in the past), so the caller can fail loudly.
set -euo pipefail

[[ "${TODAY:?}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "TODAY must be YYYY-MM-DD" >&2; exit 1; }
jq -e 'type == "array"' <<<"${ITERATIONS:?}" > /dev/null || { echo "ITERATIONS must be a JSON array" >&2; exit 1; }

out=$(jq -c --arg today "$TODAY" '
  def day: strptime("%Y-%m-%d") | mktime;
  ($today | day) as $t
  | map(. + {s: (.startDate | day)} | . + {e: (.s + .duration * 86400)}) as $its
  | ($its | map(select(.s <= $t and $t < .e)) | sort_by(.s) | .[0]) as $cur
  | ($its | map(select(.s > $t)) | sort_by(.s) | .[0]) as $next
  | if $cur then {id: $cur.id, title: $cur.title, note: ""}
    elif $next then {id: $next.id, title: $next.title, note: "No sprint is running today; used the next upcoming sprint."}
    else empty end' <<<"$ITERATIONS")
[ -n "$out" ] || { echo "No current or upcoming sprint. Create the next iteration on the project board." >&2; exit 2; }
echo "$out"
