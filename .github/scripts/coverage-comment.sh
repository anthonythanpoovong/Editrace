#!/usr/bin/env bash
# Creates or updates the one sticky "Coverage" comment on a PR (#129), so each push edits it in place.
# Finds its own comment by the marker on the first line and by author: only comments written by
# github-actions[bot] count, so a person pasting the marker into a comment can't redirect the update.
# Inputs (env): REPO, PR, GH_TOKEN, COMMENT_FILE (the markdown, first line the marker).
# A failure to comment (a fork PR's read-only token, say) is a warning, never a failed gate.
set -uo pipefail
repo=${REPO:?} pr=${PR:?} file=${COMMENT_FILE:?}
marker='<!-- editrace-coverage -->'
[ "$(head -n 1 "$file")" = "$marker" ] || { echo "The comment must start with $marker" >&2; exit 2; }

# If the list can't be read, post nothing: a second comment would only duplicate the first.
if ! pages=$(gh api --paginate "repos/$repo/issues/$pr/comments" 2> /dev/null); then
  echo "::warning::Could not read the PR's comments, so the coverage comment was not updated"; exit 0
fi
id=$(jq -rs --arg m "$marker" '[add // [] | .[] | select(.user.login == "github-actions[bot]" and ((.body // "") | startswith($m)))] | last | .id // empty' <<<"$pages") || id=""

body=$(jq -Rs '{body: .}' "$file")
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$repo/issues/comments/$id" --input - <<<"$body" > /dev/null \
    || { echo "::warning::Could not update the coverage comment"; exit 0; }
  echo "Updated coverage comment $id"
else
  gh api -X POST "repos/$repo/issues/$pr/comments" --input - <<<"$body" > /dev/null \
    || { echo "::warning::Could not post the coverage comment"; exit 0; }
  echo "Posted a new coverage comment"
fi
