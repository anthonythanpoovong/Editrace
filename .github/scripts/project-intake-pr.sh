#!/usr/bin/env bash
# Puts a pull request on the Editrace board (via project-intake.sh) unless it closes an issue: that
# issue already has its own card, and a second card for the same work would be a duplicate.
# Inputs (env): PR_NODE_ID, LIST_TOKEN (a token that can read the PR; GH_TOKEN is the project token
# project-intake.sh needs), plus what project-intake.sh needs (PROJECT_OWNER, PROJECT_NUMBER).
# Nothing from the PR's title or body is used; only its node ID.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[[ "${PR_NODE_ID:?}" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "PR_NODE_ID is not a node ID" >&2; exit 1; }

closes=$(GH_TOKEN="${LIST_TOKEN:?}" gh api graphql \
  -f query='query($id: ID!) { node(id: $id) { ... on PullRequest { closingIssuesReferences(first: 1) { totalCount } } } }' \
  -f id="$PR_NODE_ID" --jq '.data.node.closingIssuesReferences.totalCount')
[[ "$closes" =~ ^[0-9]+$ ]] || { echo "Could not tell whether the PR closes an issue" >&2; exit 1; }
if [ "$closes" -gt 0 ]; then
  echo "This PR closes an issue, which has its own card. Not adding a second one."
  exit 0
fi
ISSUE_NODE_ID="$PR_NODE_ID" exec "$here/project-intake.sh"
