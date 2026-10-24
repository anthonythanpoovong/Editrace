BEGIN;
SELECT plan(25);

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
--    to probe which emails are already on the list. It still reaches
--    the rate-limit trigger and logs an attempt (#153 review, F5): the
--    insert into waitlist_signups is what gets discarded by ON CONFLICT
--    DO NOTHING, not the whole statement, so the attempt the trigger
--    already recorded commits regardless.
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

-- 12-14. Three calls land in the same 'unknown' rate-limit bucket (there
--        is no request.headers GUC outside of PostgREST, so every call
--        so far in this file shares that bucket). Ada (test 2), the
--        duplicate Ada (test 6, which now counts — see its comment) and
--        Margaret (test 9) already used 3 of the 5 allowed slots.
SELECT lives_ok(
  $$ select public.join_waitlist('Rate', 'Limit1', 'rate-limit-1@example.com', 'editor', 'other') $$,
  'rate-limit bucket insert 4 of 5'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Rate', 'Limit2', 'rate-limit-2@example.com', 'editor', 'other') $$,
  'rate-limit bucket insert 5 of 5'
);

-- 14. A 6th attempt from the same address within the window is rejected,
--     with the stable 'EDR01' code the web client matches on to show a
--     rate-limited visitor a different message than a generic failure.
SELECT throws_ok(
  $$ select public.join_waitlist('Rate', 'Limit3', 'rate-limit-3@example.com', 'editor', 'other') $$,
  'EDR01',
  'Too many signups from this address. Try again later.',
  'a 6th attempt from the same address within the window is rate-limited'
);

-- 15-20. The trusted-IP logic (#153 review, F3): a request carrying a real
--        cf-connecting-ip gets its own bucket, independent of 'unknown',
--        and is rate-limited the same way once it fills up.
SELECT set_config('request.headers', '{"cf-connecting-ip": "203.0.113.5"}', true);
SELECT lives_ok(
  $$ select public.join_waitlist('Ip', 'A1', 'ip-a-1@example.com', 'editor', 'other') $$,
  'a request with its own cf-connecting-ip is not blocked by the already-full unknown bucket'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Ip', 'A2', 'ip-a-2@example.com', 'editor', 'other') $$,
  'cf-connecting-ip bucket insert 2 of 5'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Ip', 'A3', 'ip-a-3@example.com', 'editor', 'other') $$,
  'cf-connecting-ip bucket insert 3 of 5'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Ip', 'A4', 'ip-a-4@example.com', 'editor', 'other') $$,
  'cf-connecting-ip bucket insert 4 of 5'
);
SELECT lives_ok(
  $$ select public.join_waitlist('Ip', 'A5', 'ip-a-5@example.com', 'editor', 'other') $$,
  'cf-connecting-ip bucket insert 5 of 5'
);
SELECT throws_ok(
  $$ select public.join_waitlist('Ip', 'A6', 'ip-a-6@example.com', 'editor', 'other') $$,
  'EDR01',
  'Too many signups from this address. Try again later.',
  'a 6th attempt from the same cf-connecting-ip within the window is rate-limited'
);

-- 21. cf-connecting-ip is trusted over x-forwarded-for when both are
--     present (Cloudflare sets the former at its edge; the latter is
--     client-suppliable).
SELECT set_config(
  'request.headers',
  '{"cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "198.51.100.1, 10.0.0.1"}',
  true
);
SELECT lives_ok(
  $$ select public.join_waitlist('Cf', 'Precedence', 'cf-precedence@example.com', 'editor', 'other') $$,
  'cf-connecting-ip takes precedence over x-forwarded-for'
);

-- 22. Without cf-connecting-ip, the last x-forwarded-for entry (the
--     nearest proxy's own observation) is used, not the client-supplied
--     first one.
SELECT set_config(
  'request.headers',
  '{"x-forwarded-for": "198.51.100.2, 10.0.0.2"}',
  true
);
SELECT lives_ok(
  $$ select public.join_waitlist('Xff', 'Fallback', 'xff-fallback@example.com', 'editor', 'other') $$,
  'falls back to the last x-forwarded-for entry when cf-connecting-ip is absent'
);

-- 23-25. service_role (used by internal admin tooling only) bypasses RLS and can see everything that
--        actually landed in waitlist_signups, and the IP each attempt in 21-22 was attributed to in
--        waitlist_attempts (waitlist_signups itself holds no IP: #153 review, see the "drop
--        ip_address" migration).
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_signups),
  11,
  'service_role can read all signups that were successfully inserted'
);
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_attempts WHERE ip_address = '203.0.113.9'),
  1,
  'the precedence attempt was attributed to the cf-connecting-ip value, not the x-forwarded-for decoy'
);
SELECT is(
  (SELECT count(*)::int FROM public.waitlist_attempts WHERE ip_address = '10.0.0.2'),
  1,
  'the fallback attempt was attributed to the last x-forwarded-for entry'
);

SELECT * FROM finish();
ROLLBACK;
