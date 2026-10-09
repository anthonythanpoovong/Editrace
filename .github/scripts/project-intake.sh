#!/usr/bin/env bash
# Puts one issue on the Editrace project board in the current sprint with Status Backlog (#178).
# Idempotent: an issue already on the board is reused, and a Sprint or Status that is already set
# is never overwritten. Needs a token with "project" scope in GH_TOKEN (GITHUB_TOKEN cannot write
# to a user-owned project).
# Inputs (env): ISSUE_NODE_ID (the issue's GraphQL node ID), PROJECT_OWNER, PROJECT_NUMBER.
# Optional (env): OWNER_TYPE (user | organization; default user), TODAY (YYYY-MM-DD UTC; default now).
# Nothing from the issue's title or body is used; only its node ID.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

[[ "${ISSUE_NODE_ID:?}" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "ISSUE_NODE_ID is not a node ID" >&2; exit 1; }
[[ "${PROJECT_OWNER:?}" =~ ^[A-Za-z0-9-]{1,39}$ ]] || { echo "PROJECT_OWNER is not a GitHub login" >&2; exit 1; }
[[ "${PROJECT_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PROJECT_NUMBER must be numeric" >&2; exit 1; }
case "${OWNER_TYPE:-user}" in user|organization) ;; *) echo "OWNER_TYPE must be user or organization" >&2; exit 1 ;; esac
today=${TODAY:-$(date -u +%F)}

gql() { # query, then -f/-F variables
  local out
  if ! out=$(gh api graphql -f query="$1" "${@:2}" 2>&1); then
    if grep -qiE '401|Bad credentials|Resource not accessible' <<<"$out"; then
      echo "PROJECT_TOKEN expired, revoked or missing the project scope. Rotate it (see CONTRIBUTING.md)." >&2
    fi
    echo "$out" >&2
    return 1
  fi
  jq -e 'has("errors") | not' <<<"$out" > /dev/null || { jq -r '.errors[].message' <<<"$out" >&2; return 1; }
  echo "$out"
}

fields='fields(first: 50) { nodes {
  ... on ProjectV2SingleSelectField { id name options { id name } }
  ... on ProjectV2IterationField { id name configuration { iterations { id title startDate duration } } } } }'
proj=$(gql "query(\$owner: String!, \$n: Int!) { ${OWNER_TYPE:-user}(login: \$owner) { projectV2(number: \$n) { id $fields } } }" \
  -f owner="$PROJECT_OWNER" -F n="$PROJECT_NUMBER" | jq -c ".data.${OWNER_TYPE:-user}.projectV2")
[ "$proj" != null ] || { echo "Project #$PROJECT_NUMBER not found for $PROJECT_OWNER" >&2; exit 1; }

project_id=$(jq -r .id <<<"$proj")
sprint_field=$(jq -r '.fields.nodes[] | select(.name == "Sprint") | .id' <<<"$proj")
status_field=$(jq -r '.fields.nodes[] | select(.name == "Status") | .id' <<<"$proj")
backlog=$(jq -r '.fields.nodes[] | select(.name == "Status") | .options[] | select(.name == "Backlog") | .id' <<<"$proj")
[ -n "$sprint_field" ] && [ -n "$status_field" ] && [ -n "$backlog" ] \
  || { echo "The project needs a Sprint iteration field and a Status field with a Backlog option" >&2; exit 1; }

# Adding an item that is already on the board returns the existing item.
item=$(gql 'mutation($p: ID!, $c: ID!) { addProjectV2ItemById(input: {projectId: $p, contentId: $c}) { item { id
  fieldValues(first: 30) { nodes {
    ... on ProjectV2ItemFieldIterationValue { field { ... on ProjectV2FieldCommon { name } } }
    ... on ProjectV2ItemFieldSingleSelectValue { field { ... on ProjectV2FieldCommon { name } } } } } } } }' \
  -f p="$project_id" -f c="$ISSUE_NODE_ID" | jq -c .data.addProjectV2ItemById.item)
item_id=$(jq -r .id <<<"$item")
is_set() { jq -e --arg f "$1" '[.fieldValues.nodes[] | select(.field.name == $f)] | length > 0' <<<"$item" > /dev/null; }

set_field() { # field id, value kind (iterationId | singleSelectOptionId), value id (both come from the API)
  [[ "$3" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "Unexpected $2: $3" >&2; return 1; }
  gql "mutation(\$p: ID!, \$i: ID!, \$f: ID!) {
    updateProjectV2ItemFieldValue(input: {projectId: \$p, itemId: \$i, fieldId: \$f, value: {$2: \"$3\"}}) { projectV2Item { id } } }" \
    -f p="$project_id" -f i="$item_id" -f f="$1" > /dev/null
}

if is_set Sprint; then
  echo "Sprint already set; left as is."
else
  iterations=$(jq -c '.fields.nodes[] | select(.name == "Sprint") | .configuration.iterations' <<<"$proj")
  sprint=$(ITERATIONS="$iterations" TODAY="$today" "$here/project-intake-sprint.sh")
  set_field "$sprint_field" iterationId "$(jq -r .id <<<"$sprint")"
  echo "Sprint set to $(jq -r .title <<<"$sprint")."
  note=$(jq -r .note <<<"$sprint")
  [ -z "$note" ] || echo "::notice::$note"
fi
if is_set Status; then
  echo "Status already set; left as is."
else
  set_field "$status_field" singleSelectOptionId "$backlog"
  echo "Status set to Backlog."
fi
