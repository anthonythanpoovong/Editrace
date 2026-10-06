#!/usr/bin/env bash
# Tests for vercel-deploy.sh with stubbed vercel and curl. Run: .github/scripts/test-vercel-deploy.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 1
fail=0
check() { # name, exit code of the condition
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
# vercel: records its arguments and prints a deployment URL.
cat > "$tmp/bin/vercel" <<'STUB'
#!/usr/bin/env bash
echo "$*" > "$STUB_DIR/vercel-args"
echo "https://editrace-abc-editrace.vercel.app"
STUB
# curl: answers each poll with the next state in $STUB_STATES (the last one repeats).
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0)
read -ra states <<< "$STUB_STATES"
i=$n; [ "$i" -ge "${#states[@]}" ] && i=$((${#states[@]} - 1))
echo $((n + 1)) > "$STUB_DIR/n"
echo "{\"readyState\":\"${states[$i]}\"}"
STUB
chmod +x "$tmp/bin/vercel" "$tmp/bin/curl"

run() { # states, extra args...; prints the GITHUB_OUTPUT file
  local states=$1; shift
  rm -f "$tmp/n" "$tmp/out"
  STUB_DIR=$tmp STUB_STATES="$states" PATH="$tmp/bin:$PATH" GITHUB_OUTPUT="$tmp/out" \
    VERCEL_TOKEN=t VERCEL_ORG_ID=team_x VERCEL_POLL_DELAY=0 VERCEL_POLL_TRIES=${TRIES:-5} \
    ./vercel-deploy.sh "$@" > /dev/null
  cat "$tmp/out"
}

out=$(run "QUEUED BUILDING READY")
grep -qx 'state=READY' <<<"$out" && grep -qx 'url=https://editrace-abc-editrace.vercel.app' <<<"$out"
check "waits through QUEUED and BUILDING until READY" $?

out=$(run "BLOCKED")
grep -qx 'state=BLOCKED' <<<"$out"
check "a blocked deployment ends at BLOCKED instead of hanging" $?

out=$(run "BUILDING ERROR")
grep -qx 'state=ERROR' <<<"$out"
check "a failed build reports ERROR" $?

out=$(TRIES=3 run "BUILDING")
grep -qx 'state=TIMEOUT' <<<"$out"
check "a deployment that never settles reports TIMEOUT" $?

run "READY" > /dev/null
! grep -q -- '--prod' "$tmp/vercel-args" && grep -q -- '--no-wait' "$tmp/vercel-args" && grep -q -- '--prebuilt' "$tmp/vercel-args"
check "a preview deploy passes --prebuilt and --no-wait but not --prod" $?

run "READY" --prod > /dev/null
grep -q -- '--prod' "$tmp/vercel-args"
check "--prod is passed through" $?

exit $fail
