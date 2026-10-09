#!/usr/bin/env bash
# Works out which labels a new issue is missing (#178). Additive: it never removes a label a person
# set, only fills the Level, Type and domain/area gaps. Prints {"add":[...],"remove":[...]}.
# Inputs (env): LABELS (JSON array of the issue's label names).
# Optional (env): PARENT_LABELS (JSON array of the parent issue's label names; unset, empty or
# "null" when the issue has no parent).
# Level follows the hierarchy epic > story > subtask, decided by the PARENT's level, not by whether
# a parent exists: a story under an epic is still a story. Parent is an epic -> story; parent is a
# story or subtask -> subtask; no parent, or a parent with no level label -> story (the default).
# Epics, ADRs and proposals are labelled by their own skills and never get a level from here.
# Optional (env): ISSUE_BODY (an issue-form body; its "Area" answer picks the domain and area).
# The body is untrusted: it is only matched against the fixed Area options below and never echoed.
set -euo pipefail

labels=${LABELS:?}
jq -e 'type == "array" and all(type == "string")' <<<"$labels" > /dev/null \
  || { echo "LABELS must be a JSON array of label names" >&2; exit 1; }
parent=${PARENT_LABELS:-null}
jq -e '. == null or (type == "array" and all(type == "string"))' <<<"$parent" > /dev/null \
  || { echo "PARENT_LABELS must be a JSON array of label names, or null" >&2; exit 1; }

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

jq -n --argjson have "$labels" --argjson want "$want" --argjson parent "$parent" '
  def any_of($names): ($have | map(select(. as $l | $names | index($l))) | length) > 0;
  def has_prefix($p): ($have | map(select(startswith($p))) | length) > 0;
  # Level of the parent, if it has one. An epic parent wins over a stray story label.
  ( if $parent == null then null
    elif ($parent | index("epic")) then "epic"
    elif ($parent | (index("story") or index("subtask"))) then "story-or-subtask"
    else null end ) as $parent_level
  | ["epic","story","subtask","adr","proposal"] as $levels
  | ["platform","product","ml"] as $domains
  | ( (if any_of($levels) then [] else [if $parent_level == "story-or-subtask" then "subtask" else "story" end] end)
    + (if has_prefix("type:") then [] else ["type:build"] end)
    + (if any_of($domains) then [] else ($want | map(select(. as $l | $domains | index($l)))) end)
    + (if has_prefix("area:") then [] else ($want | map(select(startswith("area:")))) end)
    ) as $fill
  | (any_of($domains) or ($fill | map(select(. as $l | $domains | index($l))) | length) > 0) as $has_domain
  | { add: ($fill + (if $has_domain or any_of(["needs-triage"]) then [] else ["needs-triage"] end)),
      remove: (if $has_domain and any_of(["needs-triage"]) then ["needs-triage"] else [] end) }'
