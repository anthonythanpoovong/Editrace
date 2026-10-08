#!/usr/bin/env bash
# Tests for the project-intake scripts (#178). Run: .github/scripts/test-project-intake.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

# --- labels ---
labels() { LABELS="$1" HAS_PARENT="${2:-false}" ISSUE_BODY="${3:-}" ./project-intake-labels.sh; }
form() { printf '### 🧭 Area\n\n%s\n\n### 💻 Environment\n\nmac\n' "$1"; }
same() { [ "$(jq -cS . <<<"$1")" = "$(jq -cS . <<<"$2")" ]; }

same "$(labels '[]')" '{"add":["story","type:build","needs-triage"],"remove":[]}'
check "a bare issue gets story, type:build and needs-triage" $?

same "$(labels '[]' true)" '{"add":["subtask","type:build","needs-triage"],"remove":[]}'
check "an issue with a parent is a subtask" $?

same "$(labels '["platform","type:build","story","area:infra"]')" '{"add":[],"remove":[]}'
check "a fully labelled issue is left alone" $?

same "$(labels '["epic","type:research","product"]')" '{"add":[],"remove":[]}'
check "an epic is not also made a story, and an existing type is kept" $?

same "$(labels '["bug"]' false "$(form 'Web app')")" '{"add":["story","type:build","product","area:frontend"],"remove":[]}'
check "the Area answer fills domain and area" $?

same "$(labels '["bug"]' false "$(form 'CI / tooling')")" '{"add":["story","type:build","platform","area:infra"],"remove":[]}'
check "CI / tooling maps to platform + area:infra" $?

same "$(labels '["bug","platform"]' false "$(form 'Web app')")" '{"add":["story","type:build","area:frontend"],"remove":[]}'
check "an existing domain label is not replaced" $?

same "$(labels '["bug"]' false "$(form 'Not sure')")" '{"add":["story","type:build","needs-triage"],"remove":[]}'
check "Not sure falls back to needs-triage" $?

same "$(labels '["needs-triage","product"]')" '{"add":["story","type:build"],"remove":["needs-triage"]}'
check "needs-triage is removed once a domain label is set" $?

same "$(labels '["needs-triage"]')" '{"add":["story","type:build"],"remove":[]}'
check "needs-triage is not added twice" $?

same "$(labels '[]' false $'### Area\n\n@everyone Web app\n')" '{"add":["story","type:build","needs-triage"],"remove":[]}'
check "an Area answer that is not an exact option is ignored" $?

LABELS='not json' HAS_PARENT=false ./project-intake-labels.sh > /dev/null 2>&1; [ $? -ne 0 ]
check "bad LABELS is rejected" $?

# --- sprint ---
its='[{"id":"a","title":"Sprint 1","startDate":"2026-10-05","duration":14},{"id":"b","title":"Sprint 2","startDate":"2026-10-19","duration":14}]'
sprint() { ITERATIONS="$its" TODAY="$1" ./project-intake-sprint.sh; }

[ "$(sprint 2026-10-07 | jq -r .id)" = a ]; check "mid-sprint picks the running sprint" $?
[ "$(sprint 2026-10-05 | jq -r .id)" = a ]; check "the start day belongs to the sprint" $?
[ "$(sprint 2026-10-18 | jq -r .id)" = a ]; check "the last day belongs to the sprint" $?
[ "$(sprint 2026-10-19 | jq -r .id)" = b ]; check "the next start day belongs to the next sprint" $?
out=$(sprint 2026-10-01); [ "$(jq -r .id <<<"$out")" = a ] && [ -n "$(jq -r .note <<<"$out")" ]
check "before the first sprint uses the next one and says so" $?
ITERATIONS="$its" TODAY=2026-12-01 ./project-intake-sprint.sh > /dev/null 2>&1; [ $? -eq 2 ]
check "after the last sprint exits 2" $?
ITERATIONS='[]' TODAY=2026-10-07 ./project-intake-sprint.sh > /dev/null 2>&1; [ $? -eq 2 ]
check "no iterations exits 2" $?

# --- orchestrator, against a fake gh ---
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/gh" <<'FAKE'
#!/usr/bin/env bash
q=$(printf '%s\n' "$@")
printf '%s\n' "$q" | tr '\n' ' ' >> "$FAKE_LOG"; echo >> "$FAKE_LOG"
case "$q" in
  *projectV2\(number*) cat <<JSON
{"data":{"user":{"projectV2":{"id":"P1","fields":{"nodes":[{},
 {"id":"S1","name":"Status","options":[{"id":"o1","name":"Backlog"},{"id":"o2","name":"Done"}]},
 {"id":"F1","name":"Sprint","configuration":{"iterations":[{"id":"it1","title":"Sprint 1","startDate":"2026-10-05","duration":14}]}}]}}}}}
JSON
  ;;
  *addProjectV2ItemById*) cat <<JSON
{"data":{"addProjectV2ItemById":{"item":{"id":"I1","fieldValues":{"nodes":${FAKE_VALUES:-[]}}}}}}
JSON
  ;;
  *updateProjectV2ItemFieldValue*) echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"I1"}}}}' ;;
esac
FAKE
chmod +x "$tmp/gh"
run() { PATH="$tmp:$PATH" FAKE_LOG="$tmp/log" ISSUE_NODE_ID=I_abc PROJECT_OWNER=me PROJECT_NUMBER=2 TODAY=2026-10-07 ./project-intake.sh; }

: > "$tmp/log"; run > /dev/null
[ "$(grep -c 'updateProjectV2ItemFieldValue' "$tmp/log")" -eq 2 ] && grep -q 'iterationId: "it1"' "$tmp/log" && grep -q 'singleSelectOptionId: "o1"' "$tmp/log"
check "a new item gets the current sprint and Backlog" $?

: > "$tmp/log"; FAKE_VALUES='[{"field":{"name":"Sprint"}},{"field":{"name":"Status"}}]' run > /dev/null
[ "$(grep -c 'updateProjectV2ItemFieldValue' "$tmp/log")" -eq 0 ]
check "an item with Sprint and Status set is not overwritten" $?

: > "$tmp/log"; FAKE_VALUES='[{"field":{"name":"Sprint"}}]' run > /dev/null
[ "$(grep -c 'updateProjectV2ItemFieldValue' "$tmp/log")" -eq 1 ] && grep -q 'singleSelectOptionId' "$tmp/log"
check "only the missing field is filled" $?

ISSUE_NODE_ID='x";drop' PROJECT_OWNER=me PROJECT_NUMBER=2 ./project-intake.sh > /dev/null 2>&1; [ $? -ne 0 ]
check "a bad node ID is rejected" $?

exit $fail
