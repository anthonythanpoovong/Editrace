-- Fix: the per-IP rate limit (#54 follow-up) trusted the client-
-- supplied X-Forwarded-For header verbatim, which is fully spoofable.
-- Confirmed locally: 10 signups each sent with a different forged
-- X-Forwarded-For value all succeeded past the 5-per-10-minute limit.
--
-- Prefer cf-connecting-ip: Cloudflare sets this at its edge and
-- overwrites it on every request regardless of what the client sends,
-- and *.supabase.co is served through Cloudflare, so on the deployed
-- project this header is trustworthy. Fall back to the LAST entry of
-- x-forwarded-for (the nearest proxy's own observation, conventionally
-- appended, rather than the client-supplied first entry) only if
-- cf-connecting-ip is absent.
--
-- Residual risk, not fully closed by this migration: in a topology
-- with no trusted intermediary in front of Kong at all (this local
-- Docker stack has no CDN), neither header carries any trustworthy
-- value and the limiter still degrades to one shared 'unknown'
-- bucket, exactly as spoofable as before. That's a limitation of the
-- topology, not something fixable in SQL — closing it for real would
-- need a CAPTCHA (e.g. Cloudflare Turnstile) verified before insert,
-- independent of any client-supplied header.

alter table public.waitlist_signups
  add constraint waitlist_signups_ip_address_length check (char_length(ip_address) <= 45);

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
  headers := current_setting('request.headers', true)::json;

  client_ip := nullif(trim(headers ->> 'cf-connecting-ip'), '');

  if client_ip is null then
    xff_parts := regexp_split_to_array(coalesce(headers ->> 'x-forwarded-for', ''), '\s*,\s*');
    client_ip := nullif(trim(xff_parts[array_length(xff_parts, 1)]), '');
  end if;

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
