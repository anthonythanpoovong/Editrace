-- Coming-soon site waitlist signups (#54), hardened per the #153 review (squashed from the original
-- create/hardening/trusted-ip/comment/rate-limit/retention migrations: nothing here has shipped to a
-- live Supabase project yet, so one clean migration is easier to review than six).
--
-- Public, anonymous-write table: not user-owned, so there is no auth.uid() ownership column. There is
-- no insert, select, update or delete policy for anon/authenticated at all — the only way in is the
-- join_waitlist() RPC below, a SECURITY DEFINER function that bypasses RLS internally and never
-- reveals whether an email was new or already registered (ON CONFLICT (email) DO NOTHING on insert,
-- with no error either way).
-- Retention (#153 review): unlike waitlist_attempts below, nothing prunes this table. Rows are kept
-- indefinitely today -- there is no automatic expiry, scheduled deletion, or self-serve removal path.
-- That's a known gap (tracked for a follow-up: a deletion request path, and a decision on how long a
-- signup should be kept after launch), not a deliberate retention policy.
create table if not exists public.waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  first_name text not null check (char_length(trim(first_name)) > 0 and char_length(first_name) <= 100),
  last_name text not null check (char_length(trim(last_name)) > 0 and char_length(last_name) <= 100),
  email text not null unique check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254),
  role text not null check (role in ('creator', 'editor', 'hobbyist', 'agency')),
  source text not null check (source in ('instagram', 'tiktok', 'facebook', 'linkedin', 'word-of-mouth', 'other')),
  created_at timestamptz not null default now()
);

alter table public.waitlist_signups enable row level security;

comment on table public.waitlist_signups is
  'service-role only: signups are written through join_waitlist() (security definer), never directly by anon or authenticated';

create or replace function public.normalize_waitlist_email()
returns trigger
language plpgsql
as $$
begin
  new.email := lower(trim(new.email));
  return new;
end;
$$;

create trigger waitlist_signups_normalize_email
  before insert on public.waitlist_signups
  for each row execute function public.normalize_waitlist_email();

-- A per-IP rate limit (5 signups per 10 minutes), logged in its own table rather than counted off
-- waitlist_signups: join_waitlist() inserts with ON CONFLICT DO NOTHING, so a call that resubmits an
-- already-registered email would otherwise never count against the limit — a script could hammer the
-- endpoint forever with one known email. A duplicate-email call still spends its own place in the
-- window, exactly like a new signup, because the attempt row below is inserted before we know whether
-- the signup itself will succeed.
--
-- This is a soft, best-effort limit, not strict enforcement: concurrent inserts can each read a count
-- under the cap and all succeed (acceptable here; a hard guarantee would need an advisory lock, not
-- worth it for a coming-soon waitlist). It also has no ip_address on waitlist_signups itself (#153
-- review: storing IP alongside name/email indefinitely, with no retention policy, is unnecessary PII
-- correlation once this table exists — the rate limit is the only reason an IP is ever collected, and
-- it only needs the last 10 minutes of it). Rows here older than a day are pruned opportunistically by
-- the trigger itself, so no separate cron job is needed either.
--
-- IP source (#153 review, blocker 3): the client IP is supplied by join_waitlist()'s caller as
-- p_ip_address, not read from any header in here. That caller is now always trusted: execute on
-- join_waitlist() is service_role only (see its grant below), so the only ways in are the web app's own
-- /api/waitlist route (web/app/api/waitlist/route.ts), which reads the IP via Vercel's ipAddress()
-- helper — Vercel's edge sets x-forwarded-for itself on every request a Function sees, overwriting
-- whatever the client sent, so this doesn't rest on an unconfirmed assumption about *.supabase.co's own
-- front door the way reading cf-connecting-ip in here used to — or someone/something already holding
-- the service-role key. This also closes the previous design's anon-key bypass: anon and authenticated
-- have no execute on join_waitlist() at all now, so the public anon key alone can't reach this trigger,
-- let alone supply its own IP. One residual gap, local-dev only: plain `next dev`, not running on
-- Vercel, gets nothing from ipAddress(), so every local call falls back to the shared 'unknown' bucket
-- below, exactly as before this migration started passing the IP in explicitly — not a concern in any
-- deployed environment, all of which run on Vercel.
--
-- Caveat (#153 review): this does NOT log every attempt unconditionally. The attempt insert below and
-- the trigger's raise exception run in the same transaction as the signup it's guarding, so a *blocked*
-- call's own attempt row is rolled back along with everything else when the exception propagates — only
-- calls that stayed under the cap leave a row. The limit still works, because the committed rows from
-- the window's earlier allowed calls are enough to keep blocking later ones, but this table can't be
-- read as a count of how many signups were actually attempted or refused.
create table if not exists public.waitlist_attempts (
  id bigint generated always as identity primary key,
  ip_address text not null check (char_length(ip_address) <= 45),
  attempted_at timestamptz not null default now()
);

create index waitlist_attempts_ip_time_idx
  on public.waitlist_attempts (ip_address, attempted_at);

-- The prune below filters on attempted_at alone, which the composite index above can't serve (it leads
-- with ip_address) -- without this, every signup pays a sequential scan of the whole table to prune it.
create index waitlist_attempts_time_idx
  on public.waitlist_attempts (attempted_at);

alter table public.waitlist_attempts enable row level security;

comment on table public.waitlist_attempts is
  'service-role only: written only by enforce_waitlist_rate_limit() (security definer), never directly by anon or authenticated';

-- security definer: anon/authenticated have no select policy on either table, so without elevated
-- privileges this count would always read back zero rows and the rate limit would never trigger.
create or replace function public.enforce_waitlist_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  client_ip text;
  recent_count int;
begin
  -- Set by join_waitlist() below, for the rest of this transaction, to the IP its caller passed in as
  -- p_ip_address -- see the comment above waitlist_attempts for where that value comes from and why
  -- it's trusted now, instead of being read from request.headers in here. Reading a header in here had
  -- no way to tell a PostgREST call from a plain psql session, and meant trusting an unconfirmed
  -- assumption about Supabase's own front door (#153 review, blocker 3).
  client_ip := coalesce(nullif(trim(current_setting('editrace.waitlist_client_ip', true)), ''), 'unknown');

  -- waitlist_attempts has no purpose once outside the 10-minute window either; prune opportunistically
  -- on every call rather than keep an unbounded IP log or stand up a separate cron job for it. Served by
  -- waitlist_attempts_time_idx below, not the (ip_address, attempted_at) index, since this filters on
  -- attempted_at alone.
  delete from public.waitlist_attempts where attempted_at < now() - interval '1 day';

  insert into public.waitlist_attempts (ip_address) values (client_ip);

  select count(*) into recent_count
  from public.waitlist_attempts
  where ip_address = client_ip
    and attempted_at > now() - interval '10 minutes';

  -- A stable, custom SQLSTATE (not one of plpgsql's reserved P0001-P0004) so the web client can tell
  -- "rate limited" apart from other failures via PostgREST's error body `code` field, instead of
  -- string-matching this message.
  if recent_count > 5 then
    raise exception 'Too many signups from this address. Try again later.'
      using errcode = 'EDR01';
  end if;

  return new;
end;
$$;

create trigger waitlist_signups_rate_limit
  before insert on public.waitlist_signups
  for each row execute function public.enforce_waitlist_rate_limit();

create or replace function public.join_waitlist(
  p_first_name text,
  p_last_name text,
  p_email text,
  p_role text,
  p_source text,
  p_ip_address text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Read by enforce_waitlist_rate_limit() (fired by the insert below, in the same transaction) via
  -- current_setting('editrace.waitlist_client_ip', true) -- see the comment above waitlist_attempts.
  perform set_config('editrace.waitlist_client_ip', coalesce(p_ip_address, ''), true);

  insert into public.waitlist_signups (first_name, last_name, email, role, source)
  values (p_first_name, p_last_name, p_email, p_role, p_source)
  on conflict (email) do nothing;
end;
$$;

-- Execute is service_role only (#153 review, blocker 3): the previous anon/authenticated grant meant
-- anyone holding the public anon key could call this directly, bypassing the web app entirely and
-- supplying whatever IP (or none) they liked. Now the only ways in are the web app's own /api/waitlist
-- route (web/app/api/waitlist/route.ts, which holds the service-role key server-side and passes a real
-- p_ip_address) or someone/something already trusted with that key.
revoke execute on function public.join_waitlist(text, text, text, text, text, text) from public;
grant execute on function public.join_waitlist(text, text, text, text, text, text) to service_role;
