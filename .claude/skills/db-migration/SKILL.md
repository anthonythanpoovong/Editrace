---
name: db-migration
description: Create a Supabase Postgres migration for Editrace together with its RLS policies and a two-user access test, so no table ships without row-level security. Use when adding or changing tables, columns, indexes, functions, storage buckets or RLS policies — e.g. "add a jobs table", "store footage match results", "new column on templates".
---

# DB migration + RLS

Every user-owned table needs **RLS policies and a test that proves user B can't see user A's rows** (#49). The migration, policies and test ship together in one PR.

## 0. Preflight
- **Supabase CLI setup (#49):** a `supabase/` directory with `migrations/` and the RLS test harness. If it doesn't exist, stop. That's #49's job. Offer to help with it instead of writing SQL that has nowhere to live.
- Look at existing migrations and **copy their conventions** (naming, timestamps, `created_at`/`updated_at`, `user_id` column name, policy naming).

## 1. Design (confirm with the author)
- **What's stored, and whose is it?** Name the owning column (`user_id` → `auth.users.id`).
- **Is it needed at all?** Prefer existing tables. Don't store media, audio, or anything the Key Decisions forbid (e.g. copyrighted audio, other users' data for benchmarks before #56).
- **Retention:** is there a delete path, and how long is data kept? Check it matches #56.
- **Time fields:** frames + rational fps for template time; `timestamptz` for wall-clock time.
- **Schema-derived data:** template JSON stays schema-valid. Validate it at write time, and don't denormalize template fields into ad-hoc columns without a reason.

## 2. Write the migration
```sh
supabase migration new <verb_noun>        # e.g. create_footage_match_results
```
In the migration:
1. DDL (tables, columns, indexes on foreign keys and common filters).
2. `alter table … enable row level security;`. This is **mandatory** for every new table.
3. Policies, least privilege, one per operation that's actually needed:
   - `select` / `update` / `delete`: `using (auth.uid() = user_id)`
   - `insert`: `with check (auth.uid() = user_id)`
   - Service-role-only tables (e.g. worker writes): no user policies, plus a comment explaining why.
4. Storage buckets: policies scoped to the user's folder prefix.
5. Make it re-runnable where Supabase allows (`if not exists`), and never destructive without an explicit, reviewed plan. Dropping or renaming a column with data in it is breaking, so write an ADR (`/propose-adr`) first.

## 3. Test (two users)
Using the #49 harness, for each new user-owned table:
- User A creates a row, and user A can read, update and delete it.
- **User B can't** select, update or delete A's row, and can't insert a row with A's `user_id`.
- Anonymous access is denied.
Then run `supabase db reset` and the test suite locally.

## 4. Follow-through
- Regenerate DB types if the project generates them from the database.
- Reads through the MCP server or the Bridge must hit the same RLS (use the user's JWT, never the service role, for user-scoped reads).
- PR body: tables and policies added, retention, and test output.

## Rules
- No table without RLS enabled and a two-user test. No exceptions without a written reason in the migration.
- Never use the service-role key for requests made on a user's behalf.
- Never edit an applied migration. Add a new one.
