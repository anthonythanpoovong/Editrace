-- The hardening migration dropped waitlist_signups' only policy, so the table now has none. That is deliberate: anon
-- and authenticated can't read or write it directly, and signups go through the join_waitlist() function, which runs
-- as the table owner. The RLS guardrail (supabase/tests/database/000_rls_guardrails.test.sql, #49) wants a policy-less
-- table to say so on purpose.

comment on table public.waitlist_signups is
  'service-role only: signups are written through join_waitlist() (security definer), never directly by anon or authenticated';
