#!/usr/bin/env bash
# Sets Status Done on the Editrace project board for each issue a merged PR closes. Idempotent: an issue
# already Done is left alone, and one not on the board yet is added first. Needs a token with "project"
# scope in GH_TOKEN (GITHUB_TOKEN cannot write to a user-owned project) and a repo token in LIST_TOKEN
# to resolve issue node IDs.
# Inputs (env): ISSUES (whitespace-separated issue numbers), REPO, PROJECT_OWNER, PROJECT_NUMBER.
# Optional (env): OWNER_TYPE (user | organization; default user).
set -euo pipefail

[[ "${REPO:?}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "REPO must be owner/name" >&2; exit 1; }
[[ "${PROJECT_OWNER:?}" =~ ^[A-Za-z0-9-]{1,39}$ ]] || { echo "PROJECT_OWNER is not a GitHub login" >&2; exit 1; }
[[ "${PROJECT_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PROJECT_NUMBER must be numeric" >&2; exit 1; }
case "${OWNER_TYPE:-user}" in user|organization) ;; *) echo "OWNER_TYPE must be user or organization" >&2; exit 1 ;; esac
owner_type=${OWNER_TYPE:-user}
[ -n "${ISSUES:-}" ] || { echo "No closed issues; nothing to do."; exit 0; }

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

proj=$(gql "query(\$owner: String!, \$n: Int!) { $owner_type(login: \$owner) { projectV2(number: \$n) { id
  fields(first: 50) { nodes { ... on ProjectV2SingleSelectField { id name options { id name } } } } } } }" \
  -f owner="$PROJECT_OWNER" -F n="$PROJECT_NUMBER" | jq -c ".data.$owner_type.projectV2")
[ "$proj" != null ] || { echo "Project #$PROJECT_NUMBER not found for $PROJECT_OWNER" >&2; exit 1; }
project_id=$(jq -r .id <<<"$proj")
status_field=$(jq -r '.fields.nodes[] | select(.name == "Status") | .id' <<<"$proj")
done_opt=$(jq -r '.fields.nodes[] | select(.name == "Status") | .options[] | select(.name == "Done") | .id' <<<"$proj")
[ -n "$status_field" ] && [ -n "$done_opt" ] || { echo "The project needs a Status field with a Done option" >&2; exit 1; }

failed=0
for n in $ISSUES; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "Skipping non-numeric issue '$n'" >&2; continue; }
  if ! node=$(GH_TOKEN="$LIST_TOKEN" gh api "repos/$REPO/issues/$n" --jq .node_id 2>&1); then
    echo "::warning::Could not read #$n: $node"; failed=1; continue
  fi
  # Adding an item that is already on the board returns the existing item.
  if ! item=$(gql 'mutation($p: ID!, $c: ID!) { addProjectV2ItemById(input: {projectId: $p, contentId: $c}) { item { id
      status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { optionId } } } } }' \
      -f p="$project_id" -f c="$node" | jq -c .data.addProjectV2ItemById.item); then
    echo "::warning::Could not add #$n to the board"; failed=1; continue
  fi
  if [ "$(jq -r '.status.optionId // empty' <<<"$item")" = "$done_opt" ]; then
    echo "#$n already Done."; continue
  fi
  if gql 'mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) {
      updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f, value: {singleSelectOptionId: $o}}) { projectV2Item { id } } }' \
      -f p="$project_id" -f i="$(jq -r .id <<<"$item")" -f f="$status_field" -f o="$done_opt" > /dev/null; then
    echo "#$n set to Done."
  else
    echo "::warning::Could not set #$n to Done"; failed=1
  fi
done
exit "$failed"
