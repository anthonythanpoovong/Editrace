#!/usr/bin/env bash
# Works out which labels a new issue is missing (#178). Additive: it never removes a label a person
# set, only fills the Level, Type and domain/area gaps. Prints {"add":[...],"remove":[...]}.
# Inputs (env): LABELS (JSON array of the issue's label names), HAS_PARENT (true | false).
# Optional (env): ISSUE_BODY (an issue-form body; its "Area" answer picks the domain and area).
# The body is untrusted: it is only matched against the fixed Area options below and never echoed.
set -euo pipefail

labels=${LABELS:?}
jq -e 'type == "array"' <<<"$labels" > /dev/null || { echo "LABELS must be a JSON array" >&2; exit 1; }
case "${HAS_PARENT:?}" in true|false) ;; *) echo "HAS_PARENT must be true or false" >&2; exit 1 ;; esac

# The answer under the form's "### <emoji> Area" heading: the first non-empty line after it.
area=$(awk '/^### .*Area[[:space:]]*$/ {f=1; next} f && /^### / {exit} f && NF {print; exit}' <<<"${ISSUE_BODY:-}" | tr -d '\r')
case "$area" in
  "Web app")                        want='["product","area:frontend"]' ;;
  "Backend / API")                  want='["product","area:backend"]' ;;
  "Workers / detectors")            want='["ml","area:worker"]' ;;
  "Exporters / editor adapters")    want='["product","area:exporter"]' ;;
  "MCP server or Editrace Bridge")  want='["platform","area:mcp"]' ;;
  "Assistant / retrieval")          want='["ml","area:rag"]' ;;
  "CI / tooling")                   want='["platform","area:infra"]' ;;
  *)                                want='[]' ;;
esac

jq -n --argjson have "$labels" --argjson want "$want" --argjson parent "$HAS_PARENT" '
  def any_of($names): ($have | map(select(. as $l | $names | index($l))) | length) > 0;
  def has_prefix($p): ($have | map(select(startswith($p))) | length) > 0;
  ["epic","story","subtask","adr","proposal"] as $levels
  | ["platform","product","ml"] as $domains
  | ( (if any_of($levels) then [] else [if $parent then "subtask" else "story" end] end)
    + (if has_prefix("type:") then [] else ["type:build"] end)
    + (if any_of($domains) then [] else ($want | map(select(. as $l | $domains | index($l)))) end)
    + (if has_prefix("area:") then [] else ($want | map(select(startswith("area:")))) end)
    ) as $fill
  | (any_of($domains) or ($fill | map(select(. as $l | $domains | index($l))) | length) > 0) as $has_domain
  | { add: ($fill + (if $has_domain or any_of(["needs-triage"]) then [] else ["needs-triage"] end)),
      remove: (if $has_domain and any_of(["needs-triage"]) then ["needs-triage"] else [] end) }'
