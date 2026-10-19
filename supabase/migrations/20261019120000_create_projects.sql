-- Projects group a user's templates.
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  created_at timestamptz not null default now()
);
create index if not exists projects_user_id_idx on public.projects (user_id);

alter table public.projects enable row level security;

create policy projects_select on public.projects for select using (auth.uid() = user_id);
create policy projects_insert on public.projects for insert with check (auth.uid() = user_id);
create policy projects_update on public.projects for update using (auth.uid() = user_id);
create policy projects_delete on public.projects for delete using (auth.uid() = user_id);

grant select, insert, update, delete on public.projects to authenticated;
