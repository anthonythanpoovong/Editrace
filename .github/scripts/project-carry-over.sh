#!/usr/bin/env bash
# Carries unfinished work into the running sprint (#243). While a sprint is running, every open item on the
# Editrace project board that is not Done and sits on an EARLIER sprint moves to the running one. Done items,
# closed issues and PRs, items with no sprint and items on a later sprint are never touched, and nothing moves
# between sprints (no running sprint). Status, assignees and everything else stay as they are. Idempotent:
# once moved, an item is no longer on an earlier sprint. A failed move is reported and fails the run at the
# end, after the others have been tried.
# Needs a token with "project" scope in GH_TOKEN (GITHUB_TOKEN cannot access Projects v2).
# Inputs (env): PROJECT_OWNER, PROJECT_NUMBER. Optional: OWNER_TYPE (user | organization; default user),
# TODAY (YYYY-MM-DD UTC; default now), DRY_RUN (true: list what would move, change nothing).
set -euo pipefail

[[ "${PROJECT_OWNER:?}" =~ ^[A-Za-z0-9-]{1,39}$ ]] || { echo "PROJECT_OWNER is not a GitHub login" >&2; exit 1; }
[[ "${PROJECT_NUMBER:?}" =~ ^[0-9]+$ ]] || { echo "PROJECT_NUMBER must be numeric" >&2; exit 1; }
case "${OWNER_TYPE:-user}" in user|organization) ;; *) echo "OWNER_TYPE must be user or organization" >&2; exit 1 ;; esac
today=${TODAY:-$(date -u +%F)}
[[ "$today" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "TODAY must be YYYY-MM-DD" >&2; exit 1; }
owner_type=${OWNER_TYPE:-user}

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

query="query(\$owner: String!, \$n: Int!, \$after: String) { $owner_type(login: \$owner) { projectV2(number: \$n) { id
  field(name: \"Sprint\") { ... on ProjectV2IterationField { id configuration { iterations { id title startDate duration } } } }
  items(first: 100, after: \$after) { pageInfo { hasNextPage endCursor } nodes { id
    content { __typename ... on Issue { number state title } ... on PullRequest { number state title } ... on DraftIssue { title } }
    sprint: fieldValueByName(name: \"Sprint\") { ... on ProjectV2ItemFieldIterationValue { iterationId title startDate } }
    status: fieldValueByName(name: \"Status\") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } }"

items='[]' after=""
while :; do
  args=(-f owner="$PROJECT_OWNER" -F n="$PROJECT_NUMBER")
  [ -z "$after" ] || args+=(-f after="$after")
  page=$(gql "$query" "${args[@]}" | jq -c ".data.$owner_type.projectV2")
  [ "$page" != null ] || { echo "Project #$PROJECT_NUMBER not found for $PROJECT_OWNER, or PROJECT_TOKEN cannot access it (it needs the project scope and access to that project)" >&2; exit 1; }
  project_id=$(jq -r .id <<<"$page")
  field=$(jq -c .field <<<"$page")
  items=$(jq -c --argjson more "$(jq -c '.items.nodes' <<<"$page")" '. + $more' <<<"$items")
  [ "$(jq -r .items.pageInfo.hasNextPage <<<"$page")" = true ] || break
  after=$(jq -r .items.pageInfo.endCursor <<<"$page")
done
[ "$(jq -r '.id // empty' <<<"$field")" ] || { echo "The project needs a Sprint iteration field" >&2; exit 1; }
field_id=$(jq -r .id <<<"$field")

# The running sprint: startDate <= today < startDate + duration days.
current=$(jq -c --arg today "$today" '
  def day: strptime("%Y-%m-%d") | mktime;
  ($today | day) as $t
  | .configuration.iterations | map(select((.startDate | day) <= $t and $t < ((.startDate | day) + .duration * 86400))) | sort_by(.startDate) | .[0] // empty' <<<"$field")
if [ -z "$current" ]; then
  echo "No sprint is running on $today; nothing to carry over."
  exit 0
fi
sprint_id=$(jq -r .id <<<"$current") sprint_title=$(jq -r .title <<<"$current") sprint_start=$(jq -r .startDate <<<"$current")

moves=$(jq -c --arg start "$sprint_start" '
  [ .[] | select(.sprint != null and .sprint.startDate < $start
                 and (.status.name // "") != "Done"
                 and ((.content.state // "OPEN") == "OPEN")
                 and (.content.__typename == "Issue" or .content.__typename == "PullRequest" or .content.__typename == "DraftIssue"))
    | {id, label: (if .content.number then "#\(.content.number)" else "draft" end), title: .content.title, from: .sprint.title} ]' <<<"$items")
count=$(jq length <<<"$moves")
summary() { echo "$1"; [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$1" >> "$GITHUB_STEP_SUMMARY"; }
if [ "$count" -eq 0 ]; then
  summary "Nothing to carry into $sprint_title: no open, unfinished items are on an earlier sprint."
  exit 0
fi
summary "$([ "${DRY_RUN:-}" = true ] && echo 'Would move' || echo 'Moving') $count unfinished item(s) into $sprint_title:"

failed=0
while IFS= read -r m; do
  line="- $(jq -r '"\(.label) \(.title) (from \(.from))"' <<<"$m")"
  if [ "${DRY_RUN:-}" = true ]; then summary "$line"; continue; fi
  id=$(jq -r .id <<<"$m")
  [[ "$id" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "Unexpected item id: $id" >&2; failed=$((failed + 1)); continue; }
  if gql 'mutation($p: ID!, $i: ID!, $f: ID!, $v: String!) {
      updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f, value: {iterationId: $v}}) { projectV2Item { id } } }' \
      -f p="$project_id" -f i="$id" -f f="$field_id" -f v="$sprint_id" > /dev/null; then
    summary "$line"
  else
    summary "$line FAILED"; failed=$((failed + 1))
  fi
done < <(jq -c '.[]' <<<"$moves")
[ "$failed" -eq 0 ] || { echo "$failed move(s) failed." >&2; exit 1; }
