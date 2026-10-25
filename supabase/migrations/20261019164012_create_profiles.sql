-- One row per signed-up user, for per-user settings (#15). The row is created by the trigger below when the user signs
-- up, and deleted with the user (on delete cascade), so deleting an account leaves nothing here (#56).
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Least privilege: Supabase grants new public tables to anon and authenticated by default, so take that back and
-- grant only what a signed-in user needs. Column-level update means a user can't change their own id or created_at.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

-- The owner column is `id` here (it is the user's id), so the policies compare it with auth.uid().
-- No insert policy (the trigger creates the row) and no delete policy (deleting the user deletes it).
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (auth.uid() = id);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- Runs as the table owner because a new user has no session yet to insert as. An empty search_path stops a
-- same-named object in another schema from being picked up in its place.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Users who signed up before this migration.
insert into public.profiles (id) select id from auth.users on conflict do nothing;
