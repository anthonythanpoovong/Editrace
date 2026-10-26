#!/usr/bin/env bash
# Says whether a PR was already announced in Discord (#140), so a push doesn't announce it again.
# Input (stdin): one JSON object per PR comment, one per line: {"login": "...", "body": "..."}, e.g. from
#   gh api --paginate repos/<repo>/issues/<n>/comments --jq '.[] | {login: .user.login, body: .body}'
# Exit: 0 = announced, 1 = not announced, 2 or more = the input could not be read (never treat that as "not announced").
# Only a comment from the Actions bot counts, and only the exact marker discord-review-ack.yml reads. A person who
# quotes the marker in a comment must not be able to silence an announcement.
set -euo pipefail

jq -e --slurp '
  any(.[]; .login == "github-actions[bot]" and ((.body // "") | test("<!-- discord-review-message:[0-9]+ -->")))
' > /dev/null
