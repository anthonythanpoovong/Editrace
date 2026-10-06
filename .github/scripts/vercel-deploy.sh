#!/usr/bin/env bash
# Creates a prebuilt Vercel deployment and waits for it to settle, without ever hanging on a blocked one (#48).
# Usage: vercel-deploy.sh [--prod]
# Needs VERCEL_TOKEN and VERCEL_ORG_ID, and `vercel build` already run. Writes url= and state= to $GITHUB_OUTPUT.
# state is READY, ERROR, CANCELED, BLOCKED or TIMEOUT. The script only fails if the deployment can't be created;
# the caller decides what each state means.
#
# Why not plain `vercel deploy`: on Hobby, Vercel marks a deployment BLOCKED when the commit's author isn't on the
# Vercel team, and the CLI then waits on "Building…" forever. Polling lets a blocked deploy end quickly and quietly.
set -euo pipefail

api=${VERCEL_API:-https://api.vercel.com}
tries=${VERCEL_POLL_TRIES:-60}
delay=${VERCEL_POLL_DELAY:-5}

args=(deploy --prebuilt --no-wait --token "$VERCEL_TOKEN")
[ "${1:-}" = "--prod" ] && args+=(--prod)

url=$(vercel "${args[@]}")
echo "Created $url"

state=TIMEOUT
for _ in $(seq 1 "$tries"); do
  s=$(curl -fsS -H "Authorization: Bearer $VERCEL_TOKEN" \
    "$api/v13/deployments/${url#https://}?teamId=$VERCEL_ORG_ID" | jq -r '.readyState // empty' || true)
  case "$s" in
    READY | ERROR | CANCELED | BLOCKED) state=$s; break ;;
  esac
  sleep "$delay"
done
echo "State: $state"

{
  echo "url=$url"
  echo "state=$state"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
