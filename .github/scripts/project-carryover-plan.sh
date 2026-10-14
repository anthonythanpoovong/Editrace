#!/usr/bin/env bash
# Decides which board items roll over into the next sprint. Prints {from, to, moves:[{id,label}]}.
# Inputs (env): ITERATIONS (JSON array of {id,title,startDate,duration}), ITEMS (JSON array of
# {id,label,sprintId,status,state}), TODAY (YYYY-MM-DD, UTC).
# "to" is the sprint project-intake-sprint.sh picks (the running one, or the next upcoming one
# between sprints). "from" is the sprint right before it. An item moves when it is in "from",
# its Status is not Done, and its issue is not closed or merged. Exit 2 when there is no "to" or
# no sprint before it, so the caller can say so instead of silently doing nothing.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

jq -e 'type == "array"' <<<"${ITEMS:?}" > /dev/null || { echo "ITEMS must be a JSON array" >&2; exit 1; }
to=$("$here/project-intake-sprint.sh") || exit $?
to_id=$(jq -r .id <<<"$to")

out=$(jq -c --arg to "$to_id" --argjson items "$ITEMS" '
  sort_by(.startDate) as $its
  | ($its | map(.id) | index($to)) as $i
  | if $i == null or $i == 0 then empty
    else $its[$i - 1] as $from | $its[$i] as $dest
      | {from: {id: $from.id, title: $from.title}, to: {id: $dest.id, title: $dest.title},
         moves: [$items[] | select(.sprintId == $from.id and .status != "Done"
                                   and (.state != "CLOSED" and .state != "MERGED"))
                 | {id, label}]}
    end' <<<"$ITERATIONS")
[ -n "$out" ] || { echo "No sprint before the target sprint; nothing to carry over." >&2; exit 2; }
echo "$out"
