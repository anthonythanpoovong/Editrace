#!/usr/bin/env bash
# Tests for check-impeccable-sync.sh. Run: .github/scripts/test-check-impeccable-sync.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 1
fail=0
check() { # name, exit code of the condition
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/a/scripts" "$tmp/b/scripts"
seed() { # dir, skill version, engine version
  printf -- '---\nversion: %s\n---\n' "$2" > "$1/SKILL.md"
  printf '%s' "$3" > "$1/scripts/VERSION"
  echo "same content either way" > "$1/reference.md"
}
run() { ROOTS="$tmp/a $tmp/b" ./check-impeccable-sync.sh; }

seed "$tmp/a" "1.0.0" "0.1.0"
seed "$tmp/b" "1.0.0" "0.1.0"
run > /dev/null 2>&1
check "two copies with the same files and versions pass" $?

echo "an extra file only .claude has" > "$tmp/a/extra.md"
out=$(run 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -q 'extra.md has no counterpart' <<<"$out"
check "a file in one copy but not the other fails, naming it" $?
rm "$tmp/a/extra.md"

run > /dev/null 2>&1
check "removing the extra file passes again" $?

printf -- '---\nversion: %s\n---\n' "1.0.1" > "$tmp/a/SKILL.md"
out=$(run 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -q 'SKILL.md version differs' <<<"$out"
check "a SKILL.md version mismatch fails" $?
printf -- '---\nversion: %s\n---\n' "1.0.0" > "$tmp/a/SKILL.md"

printf '%s' "0.1.1" > "$tmp/a/scripts/VERSION"
out=$(run 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -q 'scripts/VERSION differs' <<<"$out"
check "an engine VERSION mismatch fails" $?

rm -rf "$tmp/b"
ROOTS="$tmp/a $tmp/b" ./check-impeccable-sync.sh > /dev/null 2>&1
check "a missing directory exits 2" $(( $? == 2 ? 0 : 1 ))

exit "$fail"
