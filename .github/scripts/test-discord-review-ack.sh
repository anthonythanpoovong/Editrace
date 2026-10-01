#!/usr/bin/env bash
# Tests for discord-review-ack.sh. Run: .github/scripts/test-discord-review-ack.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
orange=15105570 green=5763719 red=15548997
msg() { # content
  jq -n --arg c "$1" --argjson o "$orange" '{id:"1", type:0, content:$c, embeds:[{type:"rich", title:"#7 t", url:"https://x", description:"d", color:$o, fields:[{name:"Author",value:"a",inline:true}], provider:{name:"x"}}]}'
}
ack() { MESSAGE="$1" REVIEWER="$2" REVIEW_STATE="$3" ./discord-review-ack.sh; }

out=$(ack "$(msg '<@&123> Review requested')" alice approved)
[ "$(jq -r .content <<<"$out")" = '✅ Reviewed · alice approved' ]
check "first review replaces the ping line with a checkmark and the reviewer" $?
[ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[]}' ]
check "the edit allows no mentions at all" $?
[ "$(jq -r '.embeds[0].color' <<<"$out")" = "$green" ]
check "an approval turns the embed green" $?
[ "$(jq -r '.embeds[0] | [.title, .url, .description] | join("|")' <<<"$out")" = '#7 t|https://x|d' ] \
  && [ "$(jq -c '.embeds[0].fields' <<<"$out")" = '[{"name":"Author","value":"a","inline":true}]' ] \
  && ! jq -e '.embeds[0] | has("provider") or has("type")' <<<"$out" >/dev/null
check "the embed is kept, minus read-only fields" $?

out=$(ack "$(msg '<@&123> Review requested')" bob commented)
[ "$(jq -r .content <<<"$out")" = '✅ Reviewed · bob commented' ] && [ "$(jq -r '.embeds[0].color' <<<"$out")" = "$orange" ]
check "a comment adds the checkmark but keeps the colour" $?

out=$(ack "$(msg '✅ Reviewed · alice approved')" bob changes_requested)
[ "$(jq -r .content <<<"$out")" = '✅ Reviewed · alice approved · bob requested changes' ] && [ "$(jq -r '.embeds[0].color' <<<"$out")" = "$red" ]
check "a second reviewer is appended, and requested changes wins over approved" $?

out=$(ack "$(msg '✅ Reviewed · alice requested changes · bob approved')" alice approved)
[ "$(jq -r .content <<<"$out")" = '✅ Reviewed · bob approved · alice approved' ] && [ "$(jq -r '.embeds[0].color' <<<"$out")" = "$green" ]
check "a repeat review replaces that person's earlier entry" $?

out=$(ack "$(msg '✅ Reviewed · alice approved')" alice approved)
[ "$(jq -r .content <<<"$out")" = '✅ Reviewed · alice approved' ]
check "re-running the same review is idempotent" $?

ack "$(msg 'x')" 'a b' approved >/dev/null 2>&1; [ $? -ne 0 ]; check "a non-login reviewer is rejected" $?
ack "$(msg 'x')" 'bot[bot]' approved >/dev/null 2>&1; [ $? -ne 0 ]; check "a bot login is rejected" $?
ack "$(msg 'x')" alice dismissed >/dev/null 2>&1; [ $? -ne 0 ]; check "an unknown review state is rejected" $?

exit $fail
