BEGIN;
SELECT plan(16);

-- waitlist_signups (#54) has no owning user, so this adapts the usual
-- two-user RLS test (/db-migration, #49): instead of "user A vs user B",
-- it proves the table itself is fully locked down (no insert, select,
-- update or delete policy for anon/authenticated) and that the only
-- way in is the join_waitlist() RPC, which bypasses RLS internally and
-- never reveals whether an email was new or already registered.

-- 1. anon cannot insert directly into the table (no insert policy).
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ insert into public.waitlist_signups (first_name, last_name, email, role, source)
     values ('Ada', 'Lovelace', 'direct-insert@example.com', 'creator', 'tiktok') $$,
  42501,
  null,
  'anon cannot insert directly into the table'
);

-- 2. anon can join the waitlist via the RPC.
SELECT lives_ok(
  $$ select public.join_waitlist('Ada', 'Lovelace', 'ada@example.com', 'creator', 'tiktok') $$,
  'anon can join the waitlist via join_waitlist()'
);

-- 3. anon cannot read any rows back, including the one just inserted.
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  0,
  'anon cannot select any waitlist rows'
);

-- 4. Invalid email is rejected.
SELECT throws_ok(
  $$ select public.join_waitlist('Grace', 'Hopper', 'not-an-email', 'editor', 'other') $$,
  23514,
  null,
  'invalid email is rejected by the check constraint'
);

-- 5. Invalid role is rejected.
SELECT throws_ok(
  $$ select public.join_waitlist('Grace', 'Hopper', 'grace@example.com', 'wizard', 'other') $$,
  23514,
  null,
  'invalid role is rejected by the check constraint'
);

-- 6. A duplicate (case-insensitive) email is silently absorbed: no
--    error, no distinguishable response, so the RPC can never be used
--    to probe which emails are already on the list.
SELECT lives_ok(
  $$ select public.join_waitlist('Ada', 'Lovelace', 'ADA@example.com', 'creator', 'tiktok') $$,
  'a duplicate email via join_waitlist() is silently ignored, not rejected'
);

-- 7. anon cannot update any row (no update policy exists).
WITH attempted AS (
  UPDATE public.waitlist_signups SET first_name = 'Changed' RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM attempted),
  0,
  'anon cannot update any waitlist row'
);

-- 8. anon cannot delete any row (no delete policy exists).
WITH attempted AS (
  DELETE FROM public.waitlist_signups RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM attempted),
  0,
  'anon cannot delete any waitlist row'
);

-- 9. authenticated can also join the waitlist via the RPC.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ select public.join_waitlist('Margaret', 'Hamilton', 'margaret@example.com', 'agency', 'linkedin') $$,
  'authenticated can join the waitlist via join_waitlist()'
);

-- 10. authenticated cannot read any rows either.
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  0,
  'authenticated cannot select any waitlist rows'
);

-- 11. first_name over the 100-char cap is rejected.
SELECT throws_ok(
  $$ select public.join_waitlist(repeat('a', 101), 'Hopper', 'toolong@example.com', 'editor', 'other') $$,
  23514,
  null,
  'first_name over 100 chars is rejected by the length check'
);

-- 12-14. Three more signups land in the same 'unknown' rate-limit
--        bucket (there is no request.headers GUC outside of PostgREST,
--        so every call in this test file shares that bucket; Ada +
--        Margaret already used 2 of the 5 allowed slots — the
--        duplicate Ada call in test 6 did not consume a slot, since it
--        was discarded by ON CONFLICT DO NOTHING and never persisted).
SELECT lives_ok(
  $$ select public.join_waitlist('Rate', 'Limit1', 'rate-limit-1@example.com', 'editor', 'other') $$,
  'rate-limit bucket insert 3 of 5'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Rate', 'Limit2', 'rate-limit-2@example.com', 'editor', 'other') $$,
  'rate-limit bucket insert 4 of 5'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Rate', 'Limit3', 'rate-limit-3@example.com', 'editor', 'other') $$,
  'rate-limit bucket insert 5 of 5'
);

-- 15. A 6th signup from the same address within the window is rejected.
SELECT throws_ok(
  $$ select public.join_waitlist('Rate', 'Limit4', 'rate-limit-4@example.com', 'editor', 'other') $$,
  'P0001',
  'Too many signups from this address. Try again later.',
  'a 6th signup from the same address within the window is rate-limited'
);

-- 16. service_role (used by internal admin tooling only) bypasses RLS
--     and can see everything that actually landed in the table.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  5,
  'service_role can read all signups that were successfully inserted'
);

SELECT * FROM finish();
ROLLBACK;
