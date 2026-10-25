-- Two-user RLS test for public.profiles (#15). Copied from 001_two_user_probe.test.sql; rolled back, nothing is left behind.
begin;
select plan(16);

-- The trigger creates a profile for every new user, with no session involved.
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@profiles.test', 'authenticated', 'authenticated'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@profiles.test', 'authenticated', 'authenticated');
select is(
  (select count(*)::int from public.profiles where id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')),
  2, 'signing up creates a profile row');

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  set local role authenticated;
end $$;

create function pg_temp.affected(q text) returns int language plpgsql as $$
declare n int;
begin
  execute q;
  get diagnostics n = row_count;
  return n;
end $$;

-- User A
select pg_temp.act_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select is((select count(*)::int from public.profiles), 1, 'A sees exactly one profile: their own');
select is((select id from public.profiles), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, 'and it is A''s');
select is(pg_temp.affected($$update public.profiles set display_name = 'Ana'$$), 1, 'A can change their display name');
select throws_ok($$update public.profiles set display_name = repeat('x', 81)$$, '23514', null, 'a display name over 80 characters is refused');
select throws_ok(
  $$update public.profiles set id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  '42501', null, 'A cannot change their own id (column-level grant)');
select throws_ok(
  $$insert into public.profiles (id) values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
  '42501', null, 'A cannot insert profiles: the trigger does that');
select throws_ok($$delete from public.profiles$$, '42501', null, 'A cannot delete their profile directly');

-- User B
reset role;
select pg_temp.act_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select is((select count(*)::int from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 0, 'B cannot read A''s profile');
select is(pg_temp.affected($$update public.profiles set display_name = 'hijacked' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$), 0, 'B cannot update A''s profile');

-- Anonymous. Clear the claims too, or auth.uid() is still B's id (see the probe test for why).
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok($$select * from public.profiles$$, '42501', null, 'anonymous users cannot read profiles');
select throws_ok($$update public.profiles set display_name = 'anon'$$, '42501', null, 'anonymous users cannot update profiles');

-- Back as the owner: A's edit was saved, B's attack changed nothing, and deleting a user deletes their profile.
reset role;
select is((select display_name from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Ana', 'A''s edit was saved and B''s was not');
select is((select display_name from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), null, 'B''s own profile is untouched');
delete from auth.users where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select is((select count(*)::int from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 0, 'deleting the user deletes their profile');
select is((select count(*)::int from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 1, 'and only theirs');

select * from finish();
rollback;
