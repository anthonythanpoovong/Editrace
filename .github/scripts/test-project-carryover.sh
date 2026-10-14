#!/usr/bin/env bash
# Tests for project-carryover-plan.sh. Run: .github/scripts/test-project-carryover.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

its='[{"id":"a","title":"Sprint 1","startDate":"2026-10-05","duration":14},{"id":"b","title":"Sprint 2","startDate":"2026-10-19","duration":14},{"id":"c","title":"Sprint 3","startDate":"2026-11-02","duration":14}]'
items='[
 {"id":"1","label":"#1 backlog","sprintId":"a","status":"Backlog","state":"OPEN"},
 {"id":"2","label":"#2 in progress","sprintId":"a","status":"In progress","state":"OPEN"},
 {"id":"3","label":"#3 done","sprintId":"a","status":"Done","state":"CLOSED"},
 {"id":"4","label":"#4 closed, status stale","sprintId":"a","status":"In progress","state":"CLOSED"},
 {"id":"5","label":"#5 merged PR","sprintId":"a","status":"Backlog","state":"MERGED"},
 {"id":"6","label":"#6 no status","sprintId":"a","status":null,"state":"OPEN"},
 {"id":"7","label":"draft","sprintId":"a","status":"Backlog","state":null},
 {"id":"8","label":"#8 already in sprint 2","sprintId":"b","status":"Backlog","state":"OPEN"},
 {"id":"9","label":"#9 no sprint","sprintId":null,"status":"Backlog","state":"OPEN"}]'
plan() { ITERATIONS="$its" ITEMS="$items" TODAY="$1" ./project-carryover-plan.sh; }
ids() { jq -r '[.moves[].id] | join(",")' <<<"$1"; }

out=$(plan 2026-10-20)
[ "$(jq -r .from.id <<<"$out")" = a ] && [ "$(jq -r .to.id <<<"$out")" = b ]; check "the running sprint takes from the one before it" $?
[ "$(ids "$out")" = "1,2,6,7" ]; check "backlog, in progress, no-status and draft items move; done, closed, merged, other sprints stay" $?

gap='[{"id":"a","title":"Sprint 1","startDate":"2026-10-05","duration":7},{"id":"b","title":"Sprint 2","startDate":"2026-10-19","duration":7}]'
out=$(ITERATIONS="$gap" ITEMS="$items" TODAY=2026-10-15 ./project-carryover-plan.sh)
[ "$(jq -r .to.id <<<"$out")" = b ] && [ "$(jq -r .from.id <<<"$out")" = a ] && [ "$(ids "$out")" = "1,2,6,7" ]; check "between sprints it moves into the next upcoming one" $?

out=$(plan 2026-11-03)
[ "$(jq -r .from.id <<<"$out")" = b ] && [ "$(ids "$out")" = 8 ]; check "only the immediately previous sprint is carried" $?

plan 2026-10-07 > /dev/null 2>&1; [ $? -eq 2 ]; check "the first sprint has nothing before it (exit 2)" $?
plan 2027-01-01 > /dev/null 2>&1; [ $? -eq 2 ]; check "no current or upcoming sprint exits 2" $?
ITERATIONS="$its" ITEMS='nope' TODAY=2026-10-20 ./project-carryover-plan.sh > /dev/null 2>&1; [ $? -eq 1 ]; check "bad ITEMS is rejected" $?

exit $fail
