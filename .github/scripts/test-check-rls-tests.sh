#!/usr/bin/env bash
# Tests for check-rls-tests.sh with a stubbed psql. Run: .github/scripts/test-check-rls-tests.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 1
fail=0
check() { # name, exit code of the condition
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/tests"
# psql: prints the tables in $STUB_TABLES, one per line.
cat > "$tmp/bin/psql" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_TABLES:-}" ] && printf '%s\n' $STUB_TABLES
exit 0
STUB
chmod +x "$tmp/bin/psql"
run() { PATH="$tmp/bin:$PATH" DB_URL=postgresql://stub RLS_TESTS_DIR="$tmp/tests" ./check-rls-tests.sh; }

echo "-- the guardrail file names no table" > "$tmp/tests/000_rls_guardrails.test.sql"

STUB_TABLES="" run > /dev/null 2>&1
check "no tables passes" $?

echo "select * from jobs;" > "$tmp/tests/jobs.test.sql"
STUB_TABLES="jobs" run > /dev/null 2>&1
check "a table named in a test passes" $?

out=$(STUB_TABLES="jobs templates" run 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -q 'public.templates has no RLS test' <<<"$out" && ! grep -q 'public.jobs' <<<"$out"
check "a table with no test fails and is named, one with a test is not" $?

echo "select * from jobs_archive;" > "$tmp/tests/archive.test.sql"
STUB_TABLES="jobs_arch" run > /dev/null 2>&1
check "a table name only matches whole words, not part of another name" $((1 - $?))

echo "select * from templates;" > "$tmp/tests/000_rls_guardrails.test.sql"
STUB_TABLES="templates" run > /dev/null 2>&1
check "the guardrail file doesn't count as a table's test" $((1 - $?))

# A failed query must fail the check, not read as "no tables".
cat > "$tmp/bin/psql_fail" <<'STUB'
#!/usr/bin/env bash
echo "psql: connection refused" >&2
exit 2
STUB
mkdir "$tmp/failbin"; cp "$tmp/bin/psql_fail" "$tmp/failbin/psql"; chmod +x "$tmp/failbin/psql"
PATH="$tmp/failbin:$PATH" DB_URL=postgresql://stub RLS_TESTS_DIR="$tmp/tests" ./check-rls-tests.sh > "$tmp/fail.out" 2>&1
[ $? -ne 0 ] && ! grep -q 'Every table' "$tmp/fail.out"
check "a failed database query fails the check instead of passing as no tables" $?

DB_URL="" PATH="$tmp/bin:$PATH" RLS_TESTS_DIR="$tmp/tests" bash -c 'supabase() { :; }; export -f supabase; ./check-rls-tests.sh' > /dev/null 2>&1
[ $? -eq 2 ]
check "no database URL exits 2" $?

exit "$fail"
