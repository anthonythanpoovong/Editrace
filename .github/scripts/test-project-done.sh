#!/usr/bin/env bash
# Tests for project-done-issues.sh. Run: .github/scripts/test-project-done.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
issues() { PR_BODY="$1" CLOSING="${2:-}" ./project-done-issues.sh | paste -sd, -; }

[ "$(issues 'Closes #5')" = 5 ]; check "a closing keyword counts" $?
[ "$(issues $'Fixes #3, #4 and #9\nResolved: #12')" = 3,4,9,12 ]; check "lists and several keywords count" $?
[ "$(issues $'Part of #7\nRelated to #8\nsee #9')" = "" ]; check "non-closing references do not count" $?
[ "$(issues 'Closes #5' '5 6')" = 5,6 ]; check "closing references merge with keywords, unique" $?
[ "$(issues 'mentions Closes #5 mid-line')" = "" ]; check "a keyword mid-line does not count" $?
[ "$(issues '')" = "" ]; check "an empty body yields nothing" $?
exit "$fail"
