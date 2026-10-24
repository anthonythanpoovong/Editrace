-- Coming-soon site waitlist signups (#54), hardened per the #153 review (squashed from the original
-- create/hardening/trusted-ip/comment/rate-limit/retention migrations: nothing here has shipped to a
-- live Supabase project yet, so one clean migration is easier to review than six).
--
-- Public, anonymous-write table: not user-owned, so there is no auth.uid() ownership column. There is
-- no insert, select, update or delete policy for anon/authenticated at all — the only way in is the
-- join_waitlist() RPC below, a SECURITY DEFINER function that bypasses RLS internally and never
-- reveals whether an email was new or already registered (ON CONFLICT (email) DO NOTHING on insert,
-- with no error either way).
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
-- endpoint forever with one known email. Logging every attempt here, unconditionally, closes that
-- gap: a duplicate-email call spends its own place in the window exactly like a new signup would.
--
-- This is a soft, best-effort limit, not strict enforcement: concurrent inserts can each read a count
-- under the cap and all succeed (acceptable here; a hard guarantee would need an advisory lock, not
-- worth it for a coming-soon waitlist). It also has no ip_address on waitlist_signups itself (#153
-- review: storing IP alongside name/email indefinitely, with no retention policy, is unnecessary PII
-- correlation once this table exists — the rate limit is the only reason an IP is ever collected, and
-- it only needs the last 10 minutes of it). Rows here older than a day are pruned opportunistically by
-- the trigger itself, so no separate cron job is needed either.
create table if not exists public.waitlist_attempts (
  id bigint generated always as identity primary key,
  ip_address text not null check (char_length(ip_address) <= 45),
  attempted_at timestamptz not null default now()
);

create index waitlist_attempts_ip_time_idx
  on public.waitlist_attempts (ip_address, attempted_at);

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
  headers json;
  xff_parts text[];
  client_ip text;
  recent_count int;
begin
  -- Prefer cf-connecting-ip: Cloudflare sets this at its edge and overwrites it on every request
  -- regardless of what the client sends, and *.supabase.co is served through Cloudflare, so on the
  -- deployed project this header is trustworthy (#153 review: that assumption isn't independently
  -- confirmed anywhere in this repo — it rests on Supabase's own infrastructure, not ours). Fall back
  -- to the LAST entry of x-forwarded-for (the nearest proxy's own observation, conventionally
  -- appended, rather than the client-supplied first entry) only if cf-connecting-ip is absent.
  --
  -- Residual risk: in a topology with no trusted intermediary in front of Kong at all (this local
  -- Docker stack has no CDN), neither header carries a trustworthy value and the limiter degrades to
  -- one shared 'unknown' bucket, exactly as spoofable as having no limit — five signups from anyone
  -- then lock out every other visitor until the window passes. That's a limitation of the topology,
  -- not something fixable in SQL: closing it for real needs a CAPTCHA (e.g. Cloudflare Turnstile)
  -- verified before insert, independent of any client-supplied header, or moving the limiter out of
  -- SQL into an edge function or a Vercel API route (#153 review; not done here).
  --
  -- This also assumes the browser calls Supabase directly (web/lib/waitlist.ts), not through a Next
  -- server action or any other server hop: every signup would otherwise arrive from that server's own
  -- IP and collapse into one bucket again.
  headers := current_setting('request.headers', true)::json;

  client_ip := nullif(trim(headers ->> 'cf-connecting-ip'), '');

  if client_ip is null then
    xff_parts := regexp_split_to_array(coalesce(headers ->> 'x-forwarded-for', ''), '\s*,\s*');
    client_ip := nullif(trim(xff_parts[array_length(xff_parts, 1)]), '');
  end if;

  client_ip := coalesce(client_ip, 'unknown');

  -- waitlist_attempts has no purpose once outside the 10-minute window either; prune opportunistically
  -- on every call rather than keep an unbounded IP log or stand up a separate cron job for it.
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
  p_source text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.waitlist_signups (first_name, last_name, email, role, source)
  values (p_first_name, p_last_name, p_email, p_role, p_source)
  on conflict (email) do nothing;
end;
$$;

revoke execute on function public.join_waitlist(text, text, text, text, text) from public;
grant execute on function public.join_waitlist(text, text, text, text, text) to anon, authenticated;
