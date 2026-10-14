#!/usr/bin/env bash
# Carries unfinished items (Status Backlog or In progress, issue still open) from the previous
# sprint into the current one on the Editrace project board. Done and closed items stay where
# they were. Idempotent: once moved, an item is no longer in the previous sprint.
# Needs a token with "project" scope in GH_TOKEN (see CONTRIBUTING.md).
# Inputs (env): PROJECT_OWNER, PROJECT_NUMBER. Optional: OWNER_TYPE (user | organization; default
# user), TODAY (YYYY-MM-DD UTC; default now), DRY_RUN=1 to only print what would move.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

[[ "${PROJECT_OWNER:?}" =~ ^[A-Za-z0-9-]{1,39}$ ]] || { echo "PROJECT_OWNER is not a GitHub login" >&2; exit 1; }
[[ "${PROJECT_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PROJECT_NUMBER must be numeric" >&2; exit 1; }
case "${OWNER_TYPE:-user}" in user|organization) ;; *) echo "OWNER_TYPE must be user or organization" >&2; exit 1 ;; esac
owner_type=${OWNER_TYPE:-user}
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

proj=$(gql "query(\$owner: String!, \$n: Int!) { $owner_type(login: \$owner) { projectV2(number: \$n) { id fields(first: 50) { nodes {
  ... on ProjectV2IterationField { id name configuration { iterations { id title startDate duration } } } } } } } }" \
  -f owner="$PROJECT_OWNER" -F n="$PROJECT_NUMBER" | jq -c ".data.$owner_type.projectV2")
[ "$proj" != null ] || { echo "Project #$PROJECT_NUMBER not found for $PROJECT_OWNER" >&2; exit 1; }
project_id=$(jq -r .id <<<"$proj")
sprint_field=$(jq -r '.fields.nodes[] | select(.name == "Sprint") | .id' <<<"$proj")
[ -n "$sprint_field" ] || { echo "The project needs a Sprint iteration field" >&2; exit 1; }
iterations=$(jq -c '.fields.nodes[] | select(.name == "Sprint") | .configuration.iterations' <<<"$proj")

# gh --paginate follows pageInfo using the $endCursor variable.
items=$(gh api graphql --paginate -f query='query($id: ID!, $endCursor: String) { node(id: $id) { ... on ProjectV2 {
  items(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { id
    sprint: fieldValueByName(name: "Sprint") { ... on ProjectV2ItemFieldIterationValue { iterationId } }
    status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
    content { ... on Issue { number title state } ... on PullRequest { number title state } ... on DraftIssue { title } } } } } } }' \
  -f id="$project_id" \
  | jq -cs '[.[].data.node.items.nodes[] | {id, sprintId: .sprint.iterationId, status: .status.name,
      state: .content.state,
      label: ((if .content.number then "#\(.content.number) " else "" end) + (.content.title // "(untitled)"))}]')

set +e
plan=$(ITERATIONS="$iterations" ITEMS="$items" TODAY="$today" "$here/project-carryover-plan.sh")
rc=$?
set -e
if [ "$rc" -eq 2 ]; then echo "Nothing to carry over: no previous sprint, or no sprint to move into."; exit 0; fi
[ "$rc" -eq 0 ] || exit "$rc"

echo "Carrying over from $(jq -r .from.title <<<"$plan") to $(jq -r .to.title <<<"$plan"): $(jq '.moves | length' <<<"$plan") item(s)."
to_id=$(jq -r .to.id <<<"$plan")
[[ "$to_id" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "Unexpected iteration id: $to_id" >&2; exit 1; }
while IFS=$'\t' read -r id label; do
  if [ "${DRY_RUN:-}" = 1 ]; then echo "would move: $label"; continue; fi
  [[ "$id" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "Unexpected item id: $id" >&2; exit 1; }
  gql "mutation(\$p: ID!, \$i: ID!, \$f: ID!) {
    updateProjectV2ItemFieldValue(input: {projectId: \$p, itemId: \$i, fieldId: \$f, value: {iterationId: \"$to_id\"}}) { projectV2Item { id } } }" \
    -f p="$project_id" -f i="$id" -f f="$sprint_field" > /dev/null
  echo "moved: $label"
done < <(jq -r '.moves[] | [.id, .label] | @tsv' <<<"$plan")
