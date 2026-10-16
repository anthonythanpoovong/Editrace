-- Structural RLS checks (#49). They run against every table in `public`, so a new table can't ship without RLS.
-- Run: supabase test db
begin;
select plan(2);

select is(
  array(
    select c.relname::text
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
    order by 1
  ),
  array[]::text[],
  'every table in public has row level security enabled'
);

-- A table with no policy is locked to the service role. That's allowed, but only on purpose: say so in
-- `comment on table <t> is 'service-role only: <why>'`, as the db-migration skill describes.
select is(
  array(
    select c.relname::text
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
      and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname)
      and coalesce(obj_description(c.oid, 'pg_class'), '') not ilike 'service-role only%'
    order by 1
  ),
  array[]::text[],
  'every table in public has a policy, or is commented "service-role only: <why>"'
);

select * from finish();
rollback;
