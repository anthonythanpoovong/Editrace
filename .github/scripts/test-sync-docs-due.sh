#!/usr/bin/env bash
# Tests for sync-docs-due.sh. Run: .github/scripts/test-sync-docs-due.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
cd "$repo" || exit 1
git init -q
git config user.email t@example.test
git config user.name t
commit() { git add -A && git commit -q -m "$1"; }

echo a >README.md && commit base
base=$(git rev-parse HEAD)

echo b >>README.md && commit "ordinary change"
head=$(git rev-parse HEAD)
out=$("$here/sync-docs-due.sh" "$base" "$head")
[ -z "$out" ]; check "only ordinary files changed: nothing is due" $?

mkdir -p .github/workflows docs/decisions
echo x >.github/workflows/a.yml
echo x >docs/decisions/0009-x.md
commit "large change"
head=$(git rev-parse HEAD)
out=$("$here/sync-docs-due.sh" "$base" "$head")
grep -q 'CI workflows' <<<"$out" && grep -q 'an ADR' <<<"$out"
check "a workflow and an ADR are both listed" $?
grep -q '<!-- sync-docs-due -->' <<<"$out"; check "the body carries the marker" $?
grep -q '2 commits' <<<"$out"; check "it counts the commits since the sync" $?
grep -q "${base:0:7}" <<<"$out"; check "it names the synced commit" $?

out=$("$here/sync-docs-due.sh" "$head" "$head")
[ -z "$out" ]; check "already synced to HEAD: nothing is due" $?

"$here/sync-docs-due.sh" 0000000000000000000000000000000000000000 "$head" >/dev/null 2>&1
[ $? -ne 0 ]; check "an unknown marker fails instead of reporting up to date" $?

exit $fail
