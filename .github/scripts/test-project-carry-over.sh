#!/usr/bin/env bash
# Tests for project-carry-over.sh (#243), against a fake gh. Run: .github/scripts/test-project-carry-over.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; mkdir "$tmp/bin"

# A fake gh: serves the board in two pages, and records every item it is asked to move (one id per line in
# $FAKE/moved, with the iteration it was moved to) unless the item is FAIL_ITEM.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
q="" item="" iter="" after=""
for a in "$@"; do
  case "$a" in
    query=*) q=${a#query=} ;;
    i=*) item=${a#i=} ;;
    v=*) iter=${a#v=} ;;
    after=*) after=${a#after=} ;;
  esac
done
[ -z "${FAKE_FAIL_ALL:-}" ] || { echo "HTTP 401 Bad credentials" >&2; exit 1; }
case "$q" in
  *updateProjectV2ItemFieldValue*)
    [ "$item" != "${FAIL_ITEM:-}" ] || { echo "boom" >&2; exit 1; }
    echo "$item $iter" >> "$FAKE/moved"; echo '{"data":{}}' ;;
  *) if [ -z "$after" ]; then cat "$FAKE/page1.json"; else cat "$FAKE/page2.json"; fi ;;
esac
FAKE
chmod +x "$tmp/bin/gh"
export FAKE="$tmp"

# Sprint 1 (09-30, 14d), Sprint 2 (10-14, 14d), Sprint 3 (10-28, 14d). Today 10-16: Sprint 2 is running.
it() { jq -cn --arg id "$1" --arg t "$2" --arg s "$3" '{iterationId: $id, title: $t, startDate: $s}'; }
item() { # id, type, state, status, sprint json or null
  jq -cn --arg id "$1" --arg ty "$2" --arg st "$3" --arg status "$4" --argjson sp "$5" \
    '{id: $id, content: ({__typename: $ty, title: "t-\($id)"} + (if $ty == "DraftIssue" then {} else {number: 1, state: $st} end)),
      sprint: $sp, status: (if $status == "" then null else {name: $status} end)}'; }
s1=$(it s1 "Sprint 1" 2026-09-30); s2=$(it s2 "Sprint 2" 2026-10-14); s3=$(it s3 "Sprint 3" 2026-10-28)
write() { # page1 items, page2 items (JSON arrays)
  jq -n --argjson a "$1" '{data: {user: {projectV2: {id: "PVT_1",
    field: {id: "PVTIF_1", configuration: {iterations: [{id: "s2", title: "Sprint 2", startDate: "2026-10-14", duration: 14}, {id: "s3", title: "Sprint 3", startDate: "2026-10-28", duration: 14}]}},
    items: {pageInfo: {hasNextPage: true, endCursor: "C1"}, nodes: $a}}}}}' > "$tmp/page1.json"
  jq -n --argjson a "$2" '{data: {user: {projectV2: {id: "PVT_1",
    field: {id: "PVTIF_1", configuration: {iterations: [{id: "s2", title: "Sprint 2", startDate: "2026-10-14", duration: 14}, {id: "s3", title: "Sprint 3", startDate: "2026-10-28", duration: 14}]}},
    items: {pageInfo: {hasNextPage: false, endCursor: null}, nodes: $b}}}}}' --argjson b "$2" > "$tmp/page2.json"; }
run() { rm -f "$tmp/moved"; env PATH="$tmp/bin:$PATH" PROJECT_OWNER=o PROJECT_NUMBER=2 TODAY="${TODAY:-2026-10-16}" "$@" ./project-carry-over.sh > "$tmp/log" 2>&1; }
moved() { sort "$tmp/moved" 2>/dev/null | tr '\n' ',' ; }

write "[$(item a Issue OPEN "In progress" "$s1"), $(item b Issue OPEN Backlog "$s1"), $(item done Issue OPEN Done "$s1"),
        $(item closed Issue CLOSED "" "$s1"), $(item none Issue OPEN Backlog null), $(item cur Issue OPEN Backlog "$s2")]" \
      "[$(item fut Issue OPEN Backlog "$s3"), $(item pr PullRequest OPEN "In progress" "$s1"), $(item dr DraftIssue "" Backlog "$s1"), $(item old Issue OPEN "" "$s1")]"
run; code=$?
[ "$code" -eq 0 ] && [ "$(moved)" = "a s2,b s2,dr s2,old s2,pr s2," ]
check "open unfinished items on an earlier sprint (issues, PRs, drafts, any page) move to the running sprint; nothing else does" $?
grep -q 'Moving 5 unfinished' "$tmp/log"; check "the log says how many moved" $?

run DRY_RUN=true; [ ! -e "$tmp/moved" ] && grep -q 'Would move 5' "$tmp/log" && grep -q '^- #1 t-a (from Sprint 1)$' "$tmp/log"
check "dry run lists what would move and changes nothing" $?

write "[$(item cur Issue OPEN Backlog "$s2"), $(item done Issue OPEN Done "$s1")]" "[]"
run; [ $? -eq 0 ] && [ ! -e "$tmp/moved" ] && grep -q 'Nothing to carry' "$tmp/log"
check "after the carry-over (or with nothing behind), a re-run moves nothing" $?

write "[$(item a Issue OPEN Backlog "$s1")]" "[]"
TODAY=2026-10-30 run; [ $? -eq 0 ] && [ "$(moved)" = "a s3," ]
check "when the next sprint is running, items on the earlier sprints move there" $?
TODAY=2026-10-05 run; [ $? -eq 0 ] && [ ! -e "$tmp/moved" ] && grep -q 'No sprint is running' "$tmp/log"
check "between sprints (none running) nothing moves" $?

write "[$(item a Issue OPEN Backlog "$s1"), $(item b Issue OPEN Backlog "$s1"), $(item c Issue OPEN Backlog "$s1")]" "[]"
run FAIL_ITEM=b; code=$?
[ "$code" -ne 0 ] && [ "$(moved)" = "a s2,c s2," ] && grep -q 'FAILED' "$tmp/log"
check "a failed move fails the run but the other items still move" $?

run FAKE_FAIL_ALL=1; code=$?
[ "$code" -ne 0 ] && grep -q 'PROJECT_TOKEN expired' "$tmp/log"; check "an unreadable board fails the run and names the token" $?
exit $fail
