#!/usr/bin/env bash
# Writes Editrace Armour's review comment (#239) from the findings ledger, so findings are never retyped by the
# model: it reports a status per earlier finding id and any new findings as JSON, and this script merges them
# with the ledger from armour-inputs.sh, renders Still open / Resolved / Errors / Risks, computes the verdict and
# appends the next ledger as a hidden block that armour-inputs.sh reads on the following commit.
# An earlier finding stays open unless the model marks it resolved with a reason. Nothing is ever dropped.
# Usage: armour-render.sh <previous.json> <armour-findings.json> <commit sha> <out comment file>
# The model's JSON: {"statuses": {"F1": {"status": "open"|"resolved", "loc": "path:line", "reason": "..."}},
#   "findings": [{"sev": "🔴"|"🟠", "kind": "error"|"risk", "loc": "path:line", "text": "...", "fix": "..."}],
#   "upgrades": [{"loc": "path:line", "text": "..."}], "coverage": "...", "files_changed": "<details>...</details>"}
# Exits non-zero, with the reason on stderr, when the model's JSON is missing or malformed, so it can fix and rerun.
set -uo pipefail
prev=${1:?previous.json} model=${2:?findings json} sha=${3:?sha} out=${4:?out file}

[ -f "$model" ] || { echo "$model doesn't exist. Write it first." >&2; exit 1; }
jq -e 'type == "object"' "$model" > /dev/null 2>&1 || { echo "$model isn't a JSON object." >&2; exit 1; }
if [ -f "$prev" ] && jq -e '.v == 1 and (.findings | type == "array")' "$prev" > /dev/null 2>&1; then
  prev_json=$(cat "$prev")
else
  # No readable ledger: render as if there were none, and say so rather than claim there was nothing to carry.
  prev_json='{"v":1,"next":1,"findings":[],"unavailable":true}'
fi

result=$(jq -n --argjson p "$prev_json" --slurpfile m "$model" --arg sha "${sha:0:7}" '
  $m[0] as $m
  | ($m.statuses // {}) as $st
  | ($m.findings // []) as $new
  | def one: tostring | gsub("[\r\n]+"; " ");
    def line($f; $flag):
      "- \($f.sev) **\($f.id)** "
      + (if ($f.loc // "") != "" then "`\($f.loc | one | gsub("`"; "'"'"'"))`: " else "" end)
      + ($f.text | one)
      + (if ($f.fix // "") != "" then " **Fix:** \($f.fix | one)" else "" end)
      + $flag;
    if ($new | all(.sev == "🔴" or .sev == "🟠")) | not then error("every finding needs sev 🔴 or 🟠; 🟢 goes under upgrades") else . end
  | ($p.findings | map(
      . as $f | ($st[$f.id] // null) as $s
      | if $s == null then $f + {state: "open", flag: " ⚠️ _Not reported on; kept open._"}
        elif $s.status == "resolved" and (($s.reason // "") | length) > 0 then $f + {state: "resolved", reason: $s.reason}
        elif $s.status == "resolved" then $f + {state: "open", flag: " ⚠️ _Marked resolved without a reason; kept open._"}
        else $f + {state: "open", flag: "", loc: (($s.loc // "") | if . == "" then $f.loc else . end)} end)) as $carried
  | ($new | to_entries | map(.value + {id: "F\($p.next + .key)", state: "new", flag: ""})) as $added
  | ($carried | map(select(.state == "open"))) as $open
  | ($carried | map(select(.state == "resolved"))) as $resolved
  | ($open + $added) as $live
  | (if any($live[]; .sev == "🔴") then "Blocking issues"
     elif any($live[]; .sev == "🟠") then "Needs changes"
     elif ($resolved | length) > 0 then "Looks good. Earlier findings resolved."
     else "Looks good. No issues found." end) as $verdict
  | def section($title; $items): if ($items | length) > 0 then "\n### \($title)\n" + ($items | join("\n")) + "\n" else "" end;
    {
      state: {v: 1, sha: $sha, next: ($p.next + ($added | length)),
              findings: ($live | map({id, sev, loc: (.loc // ""), text, fix: (.fix // "")}))},
      text: (
        "## 🛡️ Editrace Armour · `\($sha)`\n\n**Verdict:** \($verdict)\n"
        + "**Coverage:** \($m.coverage // "coverage pending: see the CI coverage comment")\n"
        + (if $p.unavailable then "\nEarlier findings couldn'"'"'t be checked.\n" else "" end)
        + section("Still open"; $open | map(line(.; .flag)))
        + section("Resolved"; $resolved | map("- ✅ **\(.id)** \(.text | one | .[0:80]): \(.reason | one)"))
        + section("Errors"; $added | map(select((.kind // "error") != "risk") | line(.; "")))
        + section("Risks"; $added | map(select(.kind == "risk") | line(.; "")))
        + section("Upgrades"; ($m.upgrades // []) | map("- 🟢 " + (if (.loc // "") != "" then "`\(.loc | one | gsub("`"; "'"'"'"))`: " else "" end) + (.text | one)))
        + (if ($m.files_changed // "") != "" then "\n" + $m.files_changed + "\n" else "" end))
    }') || { echo "Couldn't render the review from $model (see the error above). Fix the JSON and rerun." >&2; exit 1; }

state=$(jq -c .state <<< "$result" | base64 | tr -d '\n')
{ jq -r .text <<< "$result"; printf '\n<!-- armour-state:v1 %s -->\n' "$state"; } > "$out"
echo "Wrote $out: $(jq -r '.state.findings | length' <<< "$result") open finding(s) in the ledger."
