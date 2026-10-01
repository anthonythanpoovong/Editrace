#!/usr/bin/env bash
# Tests for discord-review-ack.sh. Run: .github/scripts/test-discord-review-ack.sh
set -uo pipefail
cd "$(dirname "$0")"
fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
orange=15105570 blue=5793266 green=5763719 red=15548997
msg() { # content
  jq -n --arg c "$1" --argjson o "$orange" '{id:"1", type:0, content:$c, embeds:[{type:"rich", title:"#7 t", url:"https://x", description:"d", color:$o, fields:[{name:"Author",value:"a",inline:true}], provider:{name:"x"}}]}'
}
ack() { MESSAGE="$1" REVIEWER="$2" REVIEW_STATE="$3" ./discord-review-ack.sh; }
content() { jq -r .content; }
color() { jq -r '.embeds[0].color'; }

out=$(ack "$(msg '<@&123> Review requested')" bob commented)
[ "$(content <<<"$out")" = '💬 Feedback left · 💬 bob commented' ] && [ "$(color <<<"$out")" = "$blue" ]
check "a comment: speech-bubble headline and entry, blue embed" $?

out=$(ack "$(msg '<@&123> Review requested')" bob changes_requested)
[ "$(content <<<"$out")" = '🔧 Changes requested · 🔧 bob requested changes' ] && [ "$(color <<<"$out")" = "$red" ]
check "requested changes: wrench headline and entry, red embed" $?

out=$(ack "$(msg '<@&123> Review requested')" alice approved)
[ "$(content <<<"$out")" = '✅ Approved · ✅ alice approved' ] && [ "$(color <<<"$out")" = "$green" ]
check "an approval: checkmark headline and entry, green embed" $?

out=$(ack "$(msg '💬 Feedback left · 💬 bob commented')" alice approved)
[ "$(content <<<"$out")" = '✅ Approved · 💬 bob commented · ✅ alice approved' ] && [ "$(color <<<"$out")" = "$green" ]
check "an approval upgrades the headline over a comment" $?

out=$(ack "$(msg '✅ Approved · ✅ alice approved')" bob changes_requested)
[ "$(content <<<"$out")" = '🔧 Changes requested · ✅ alice approved · 🔧 bob requested changes' ] && [ "$(color <<<"$out")" = "$red" ]
check "requested changes wins over an approval" $?

out=$(ack "$(msg '🔧 Changes requested · 🔧 bob requested changes')" bob approved)
[ "$(content <<<"$out")" = '✅ Approved · ✅ bob approved' ] && [ "$(color <<<"$out")" = "$green" ]
check "the same reviewer approving later replaces their request and clears the red" $?

out=$(ack "$(msg '✅ Approved · ✅ alice approved')" alice approved)
[ "$(content <<<"$out")" = '✅ Approved · ✅ alice approved' ]
check "re-running the same review is idempotent" $?

out=$(ack "$(msg '💬 Feedback left · 💬 bob commented')" bobby commented)
[ "$(content <<<"$out")" = '💬 Feedback left · 💬 bob commented · 💬 bobby commented' ]
check "a login that is a prefix of another is not treated as the same reviewer" $?

out=$(ack "$(msg '<@&123> Review requested')" alice approved)
[ "$(jq -c .allowed_mentions <<<"$out")" = '{"parse":[]}' ]
check "the edit allows no mentions at all" $?
[ "$(jq -r '.embeds[0] | [.title, .url, .description] | join("|")' <<<"$out")" = '#7 t|https://x|d' ] \
  && [ "$(jq -c '.embeds[0].fields' <<<"$out")" = '[{"name":"Author","value":"a","inline":true}]' ] \
  && ! jq -e '.embeds[0] | has("provider") or has("type")' <<<"$out" >/dev/null
check "the embed is kept, minus read-only fields" $?

ack "$(msg 'x')" 'a b' approved >/dev/null 2>&1; [ $? -ne 0 ]; check "a non-login reviewer is rejected" $?
ack "$(msg 'x')" 'bot[bot]' approved >/dev/null 2>&1; [ $? -ne 0 ]; check "a bot login is rejected" $?
ack "$(msg 'x')" alice dismissed >/dev/null 2>&1; [ $? -ne 0 ]; check "an unknown review state is rejected" $?

exit $fail
