BEGIN;
SELECT plan(10);

-- waitlist_signups (#54) has no owning user, so this adapts the usual
-- two-user RLS test (/db-migration, #49): instead of "user A vs user B",
-- it proves anon/authenticated can insert but never read, update or
-- delete, and only service_role (bypasses RLS) can read everything back.

-- 1. anon can join the waitlist.
SET LOCAL ROLE anon;
SELECT lives_ok(
  $$ insert into public.waitlist_signups (first_name, last_name, email, role, source)
     values ('Ada', 'Lovelace', 'ada@example.com', 'creator', 'tiktok') $$,
  'anon can insert a signup'
);

-- 2. anon cannot read any rows back, including the one just inserted.
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  0,
  'anon cannot select any waitlist rows'
);

-- 3. Invalid email is rejected.
SELECT throws_ok(
  $$ insert into public.waitlist_signups (first_name, last_name, email, role, source)
     values ('Grace', 'Hopper', 'not-an-email', 'editor', 'other') $$,
  23514,
  null,
  'invalid email is rejected by the check constraint'
);

-- 4. Invalid role is rejected.
SELECT throws_ok(
  $$ insert into public.waitlist_signups (first_name, last_name, email, role, source)
     values ('Grace', 'Hopper', 'grace@example.com', 'wizard', 'other') $$,
  23514,
  null,
  'invalid role is rejected by the check constraint'
);

-- 5. Duplicate email (case-insensitive) is rejected.
SELECT throws_ok(
  $$ insert into public.waitlist_signups (first_name, last_name, email, role, source)
     values ('Ada', 'Lovelace', 'ADA@example.com', 'creator', 'tiktok') $$,
  23505,
  null,
  'duplicate email is rejected by the unique index'
);

-- 6. anon cannot update any row (no update policy exists).
WITH attempted AS (
  UPDATE public.waitlist_signups SET first_name = 'Changed' RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM attempted),
  0,
  'anon cannot update any waitlist row'
);

-- 7. anon cannot delete any row (no delete policy exists).
WITH attempted AS (
  DELETE FROM public.waitlist_signups RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM attempted),
  0,
  'anon cannot delete any waitlist row'
);

-- 8. authenticated can also join the waitlist.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT lives_ok(
  $$ insert into public.waitlist_signups (first_name, last_name, email, role, source)
     values ('Margaret', 'Hamilton', 'margaret@example.com', 'agency', 'linkedin') $$,
  'authenticated can insert a signup'
);

-- 9. authenticated cannot read any rows either.
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  0,
  'authenticated cannot select any waitlist rows'
);

-- 10. service_role (used by internal admin tooling only) bypasses RLS
--     and can see everything that actually landed in the table.
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  2,
  'service_role can read all signups that were successfully inserted'
);

SELECT * FROM finish();
ROLLBACK;
