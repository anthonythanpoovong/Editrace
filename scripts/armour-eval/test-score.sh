#!/usr/bin/env bash
# Tests for score.sh. No network: comments are built inline.
set -euo pipefail
cd "$(dirname "$0")"

SHA=abcdef0123456789abcdef0123456789abcdef01
RE='service[ _-]?role|RLS'
fail=0

# check <name> <want-exit> <want-prefix> <json>
check() {
  local got code=0
  got=$(printf '%s' "$4" | ./score.sh "$SHA" "$RE") || code=$?
  if [ "$code" != "$2" ] || [ "${got#"$3"}" = "$got" ]; then
    echo "FAIL $1: exit $code, output '$got' (want exit $2, '$3...')"
    fail=1
  else
    echo "ok   $1"
  fi
}

top() { # top <first line> <body lines...>
  local body=$1; shift
  for l in "$@"; do body="$body"$'\n'"$l"; done
  jq -n --arg b "$body" '{user: {login: "claude[bot]"}, body: $b}'
}
inline() { # inline <commit> <body> [login]
  jq -n --arg c "$1" --arg b "$2" --arg u "${3:-claude[bot]}" '{user: {login: $u}, commit_id: $c, original_commit_id: $c, body: $b}'
}
doc() { # doc <issue comments json array> <review comments json array>
  jq -n --argjson i "$1" --argjson r "$2" '{issue_comments: $i, review_comments: $r}'
}

hdr="## 🛡️ Editrace Armour · \`abcdef0\`"

check "caught in summary" 0 "caught:" \
  "$(doc "[$(top "$hdr" "### Risks" "- 🔴 \`web/x.ts:5\`: uses the service-role key, bypassing RLS.")]" '[]')"

check "caught inline" 0 "caught:" \
  "$(doc "[$(top "$hdr" "**Verdict:** Needs changes")]" "[$(inline "$SHA" $'🟠 This reads with the\nservice role client.')]")"

check "green mention does not count" 1 "missed" \
  "$(doc "[$(top "$hdr" "- 🟢 \`web/x.ts:5\`: consider not using the service role here.")]" '[]')"

check "unrelated severe finding" 1 "missed" \
  "$(doc "[$(top "$hdr" "- 🔴 \`web/x.ts:5\`: missing dependency in package.json.")]" '[]')"

check "inline on another commit ignored" 1 "missed" \
  "$(doc "[$(top "$hdr" "**Verdict:** Looks good. No issues found.")]" "[$(inline 1111111111111111111111111111111111111111 "🔴 service role bypasses RLS")]")"

check "inline by a person ignored" 1 "missed" \
  "$(doc "[$(top "$hdr" "**Verdict:** Looks good.")]" "[$(inline "$SHA" "🔴 service role bypasses RLS" sktchan)]")"

check "review of an older commit is not a review" 2 "not reviewed" \
  "$(doc "[$(top "## 🛡️ Editrace Armour · \`9999999\`" "- 🔴 service role bypasses RLS")]" '[]')"

check "skip notice only" 2 "not reviewed" \
  "$(doc "[$(jq -n '{user: {login: "github-actions[bot]"}, body: "<!-- armour-skip-notice -->\n⚠️ Editrace Armour did not review this commit"}')]" '[]')"

check "drifted header still matches" 0 "caught:" \
  "$(doc "[$(top "**🛡️ Editrace Armour** · commit abcdef0 · **Verdict:** Blocking" "- 🔴 RLS bypass via service role")]" '[]')"

check "inline only, summary never posted" 0 "caught:" \
  "$(doc '[]' "[$(inline "$SHA" "🔴 Uses the service role key in a request handler.")]")"

check "inline moved onto this commit from an older one is ignored" 1 "missed" \
  "$(doc "[$(top "$hdr" "**Verdict:** Looks good.")]" "[$(jq -n --arg c "$SHA" '{user: {login: "claude[bot]"}, commit_id: $c, original_commit_id: "1111111", body: "🔴 service role bypasses RLS"}')]")"

check "case-insensitive" 0 "caught:" \
  "$(doc "[$(top "$hdr" "- 🟠 SERVICE ROLE client in a request handler")]" '[]')"

# Each case's expect pattern against Armour's real findings (fixtures/): it must match every finding
# about the seeded bug ('+') and none of the other findings on that PR ('-').
for f in fixtures/*.txt; do
  c=$(basename "$f" .txt)
  re=$(cat "cases/$c/expect")
  case_fail=0
  while IFS= read -r line; do
    case $line in '#'*|'') continue ;; esac
    want=${line:0:1}
    got=$(jq -n --arg l "${line:2}" --arg re "$re" '$l | test($re; "i")')
    if { [ "$want" = + ] && [ "$got" != true ]; } || { [ "$want" = - ] && [ "$got" != false ]; }; then
      echo "FAIL $c expect: '$want' line got $got: ${line:2:90}"
      case_fail=1
    fi
  done < "$f"
  if [ "$case_fail" = 0 ]; then echo "ok   $c expect vs real findings"; else fail=1; fi
done

exit $fail
