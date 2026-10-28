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

# --- project-done.sh, against a fake gh ---
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/gh" <<'FAKE'
#!/usr/bin/env bash
q=$(printf '%s\n' "$@"); echo "$q" | tr '\n' ' ' >> "$FAKE_LOG"; echo >> "$FAKE_LOG"
case "$q" in
  repos/*) echo "NODE_$(basename "${q%%$'\n'*}")" ;;
  *"${FAKE_OWNER_KEY:-user}(login"*) echo "{\"data\":{\"${FAKE_OWNER_KEY:-user}\":{\"projectV2\":{\"id\":\"P1\",\"fields\":{\"nodes\":[{\"id\":\"S1\",\"name\":\"Status\",\"options\":[{\"id\":\"d1\",\"name\":\"Done\"}]}]}}}}}" ;;
  *addProjectV2ItemById*) echo '{"data":{"addProjectV2ItemById":{"item":{"id":"I1","status":null}}}}' ;;
  *updateProjectV2ItemFieldValue*) echo '{"data":{}}' ;;
  *) echo '{"data":{"user":null,"organization":null}}' ;;
esac
FAKE
chmod +x "$tmp/gh"
done_run() { env PATH="$tmp:$PATH" FAKE_LOG="$tmp/log" GH_TOKEN=x LIST_TOKEN=y REPO=o/r PROJECT_OWNER=o PROJECT_NUMBER=1 ISSUES="5" "$@" ./project-done.sh > "$tmp/out" 2>&1; }

: > "$tmp/log"; done_run OWNER_TYPE=organization FAKE_OWNER_KEY=organization
[ $? -eq 0 ] && grep -q 'organization(login' "$tmp/log" && grep -q '#5 set to Done' "$tmp/out"
check "OWNER_TYPE=organization queries organization(login:) and sets the issue Done" $?
done_run FAKE_OWNER_KEY=organization; [ $? -ne 0 ] && grep -q 'PROJECT_TOKEN cannot access it' "$tmp/out"
check "a project the query cannot see fails and names the token" $?
exit "$fail"
