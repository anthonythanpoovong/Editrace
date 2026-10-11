#!/usr/bin/env bash
# Prints the login to assign a new issue to: its author, unless someone is already assigned or the
# author is a bot or not a plain login. Prints nothing otherwise. Inputs (env): ASSIGNEES (JSON
# array of logins), AUTHOR, AUTHOR_TYPE.
set -euo pipefail
[ "$(jq 'length' <<<"${ASSIGNEES:-[]}")" -eq 0 ] || exit 0
[ "${AUTHOR_TYPE:-}" = User ] || exit 0
[[ "${AUTHOR:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || exit 0
printf '%s\n' "$AUTHOR"
