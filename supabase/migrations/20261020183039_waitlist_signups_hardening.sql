-- Hardening for the public waitlist endpoint (#54 follow-up).
--
-- 1. Cap field lengths: the insert policy and anon key are public by
--    design, so nothing stopped an arbitrary caller stuffing megabyte
--    strings into first_name/last_name/email.
-- 2. Normalize email to lowercase on write and swap the expression
--    unique index for a plain column constraint, then insert only
--    through a SECURITY DEFINER `join_waitlist` RPC that does
--    `ON CONFLICT (email) DO NOTHING`. A direct table insert can't
--    safely do this under RLS: Postgres refuses ON CONFLICT DO NOTHING
--    when the inserting role has no SELECT policy granting visibility
--    into the conflicting row — precisely because that would otherwise
--    let a caller probe which emails are already registered. Routing
--    through a definer-owned function (which bypasses RLS internally)
--    sidesteps that restriction and lets every call return the same
--    result whether the email was new or already on the list.
-- 3. A per-IP rate limit on inserts, since there is no auth and nothing
--    else stops a script from hammering the endpoint directly.

alter table public.waitlist_signups
  add constraint waitlist_signups_first_name_length check (char_length(first_name) <= 100),
  add constraint waitlist_signups_last_name_length check (char_length(last_name) <= 100),
  add constraint waitlist_signups_email_length check (char_length(email) <= 254);

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

-- Replace the case-insensitive expression index with a plain unique
-- constraint on email now that email is always stored lowercase: a
-- plain-column constraint is what PostgREST's on_conflict can target.
drop index if exists public.waitlist_signups_email_key;
alter table public.waitlist_signups
  add constraint waitlist_signups_email_key unique (email);

alter table public.waitlist_signups
  add column ip_address text;

create index waitlist_signups_ip_created_idx
  on public.waitlist_signups (ip_address, created_at);

-- security definer: anon/authenticated have no select policy on this
-- table, so without elevated privileges this count would always read
-- back zero rows and the rate limit would never trigger.
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
  client_ip := nullif(split_part(
    coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''),
    ',', 1
  ), '');
  client_ip := coalesce(client_ip, 'unknown');

  select count(*) into recent_count
  from public.waitlist_signups
  where ip_address = client_ip
    and created_at > now() - interval '10 minutes';

  if recent_count >= 5 then
    raise exception 'Too many signups from this address. Try again later.';
  end if;

  new.ip_address := client_ip;
  return new;
end;
$$;

create trigger waitlist_signups_rate_limit
  before insert on public.waitlist_signups
  for each row execute function public.enforce_waitlist_rate_limit();

-- Lock the table down entirely: all writes now go through
-- join_waitlist(), which bypasses RLS as a SECURITY DEFINER function
-- owned by the table owner.
drop policy if exists "anyone can join the waitlist" on public.waitlist_signups;

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
