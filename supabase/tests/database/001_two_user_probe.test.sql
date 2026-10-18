-- Proves the two-user harness works, and is the template for every real table's RLS test (#49).
-- It builds a throwaway table with the standard owner policies inside a transaction that is rolled back, so nothing
-- is left behind. Copy it as `<table>.test.sql`, drop the probe table and point it at the real one: the check in
-- .github/scripts/check-rls-tests.sh requires every table in public to be named in a test file.
begin;
select plan(13);

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@probe.test', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@probe.test', 'authenticated', 'authenticated');

create table public.probe_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  note text
);
alter table public.probe_items enable row level security;
create policy probe_items_select on public.probe_items for select using (auth.uid() = user_id);
create policy probe_items_insert on public.probe_items for insert with check (auth.uid() = user_id);
create policy probe_items_update on public.probe_items for update using (auth.uid() = user_id);
create policy probe_items_delete on public.probe_items for delete using (auth.uid() = user_id);
grant select, insert, update, delete on public.probe_items to authenticated, anon;

-- Run the statements below as a signed-in user, the way PostgREST does.
create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  set local role authenticated;
end $$;

-- Rows touched by a statement; a policy that hides a row shows up as 0, not as an error.
create function pg_temp.affected(q text) returns int language plpgsql as $$
declare n int;
begin
  execute q;
  get diagnostics n = row_count;
  return n;
end $$;

-- User A
select pg_temp.act_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select lives_ok(
  $$insert into public.probe_items (user_id, note) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a''s row')$$,
  'A can insert a row for themself');
select is((select count(*)::int from public.probe_items), 1, 'A can read their own row');
select is(pg_temp.affected($$update public.probe_items set note = 'edited'$$), 1, 'A can update their own row');
-- An update policy checks the new row too: without that, A could hand their row to B (or take one over).
select throws_ok(
  $$update public.probe_items set user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  '42501', null, 'A cannot reassign their row to B');

-- User B
reset role;
select pg_temp.act_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select is((select count(*)::int from public.probe_items), 0, 'B cannot read A''s row');
select is(pg_temp.affected($$update public.probe_items set note = 'hijacked'$$), 0, 'B cannot update A''s row');
select is(pg_temp.affected($$delete from public.probe_items$$), 0, 'B cannot delete A''s row');
select throws_ok(
  $$insert into public.probe_items (user_id, note) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'forged')$$,
  '42501', null, 'B cannot insert a row owned by A');

-- Anonymous. `reset role` doesn't clear B's JWT claims, so clear them too: otherwise auth.uid() is still B's id and
-- A's row stays hidden for the wrong reason, which would let a policy that lets anonymous users in pass this test.
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select is(auth.uid(), null, 'anonymous users have no user id');
select is((select count(*)::int from public.probe_items), 0, 'anonymous users cannot read A''s row');
select throws_ok(
  $$insert into public.probe_items (user_id, note) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'anon')$$,
  '42501', null, 'anonymous users cannot insert a row');
select is(pg_temp.affected($$update public.probe_items set note = 'anon edit'$$), 0, 'anonymous users cannot update A''s row');
select is(pg_temp.affected($$delete from public.probe_items$$), 0, 'anonymous users cannot delete A''s row');

select * from finish();
rollback;
