#!/usr/bin/env bash
# Fails when a table in the local database's public schema isn't named in any RLS test (#49).
# 000_rls_guardrails.test.sql already fails a table with no RLS or no policy; this adds "and a two-user test".
# Needs the local stack running (`supabase start`). Uses psql, or the stack's own database container when psql
# isn't installed. DB_URL overrides the URL taken from `supabase status`.
# RLS_TESTS_DIR overrides the tests folder (the unit test uses it).
set -euo pipefail
cd "$(dirname "$0")/../.."

tests=${RLS_TESTS_DIR:-supabase/tests/database}
db_url=${DB_URL:-$(supabase status -o env 2>/dev/null | sed -n 's/^DB_URL="\(.*\)"$/\1/p')}
[ -n "$db_url" ] || { echo "No database URL: is the local stack running (supabase start)?" >&2; exit 2; }

query="select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') order by 1"
if command -v psql > /dev/null; then
  tables=$(psql "$db_url" -Atc "$query")
else
  container=$(docker ps --filter name=supabase_db_ --format '{{.Names}}' | head -n 1)
  [ -n "$container" ] || { echo "Neither psql nor a running supabase_db_ container found." >&2; exit 2; }
  tables=$(docker exec "$container" psql -U postgres -Atc "$query")
fi

missing=()
for t in $tables; do
  # The guardrail file names no table; it checks all of them, so it can't count as a table's own test.
  grep -rqw --include='*.test.sql' --exclude='000_*' -- "$t" "$tests" || missing+=("$t")
done

if [ "${#missing[@]}" -gt 0 ]; then
  for t in "${missing[@]}"; do
    echo "::error::public.$t has no RLS test. Add $tests/$t.test.sql (copy 001_two_user_probe.test.sql)."
  done
  exit 1
fi
count=$(printf '%s' "$tables" | grep -c . || true)
echo "Every table in public ($count) is named in an RLS test."
