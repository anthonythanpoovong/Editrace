-- Coming-soon site waitlist signups (#54).
-- Public, anonymous-write table: not user-owned, so there is no auth.uid()
-- ownership column. Anyone can insert their own signup; nobody (other than
-- service_role, which bypasses RLS) can read, update or delete.
create table if not exists public.waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  first_name text not null check (char_length(trim(first_name)) > 0),
  last_name text not null check (char_length(trim(last_name)) > 0),
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role text not null check (role in ('creator', 'editor', 'hobbyist', 'agency')),
  source text not null check (source in ('instagram', 'tiktok', 'facebook', 'linkedin', 'word-of-mouth', 'other')),
  created_at timestamptz not null default now()
);

-- One signup per email; repeat submissions should fail loudly (409) so the
-- site can show "you're already on the list" instead of a silent duplicate.
create unique index if not exists waitlist_signups_email_key
  on public.waitlist_signups (lower(email));

alter table public.waitlist_signups enable row level security;

-- Anyone (anon or authenticated) can join the waitlist, but can't read back
-- rows: the policy only grants insert, and there is no select policy at all.
create policy "anyone can join the waitlist"
  on public.waitlist_signups
  for insert
  to anon, authenticated
  with check (true);
