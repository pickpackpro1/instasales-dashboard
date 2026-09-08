-- A second password that grants COST MANAGER ONLY access.
--
-- Why this is a database change and not a UI one: every table's policy checks whether the
-- session is verified, so hiding menu items in the browser would restrict nothing - the data
-- is still fetchable. Restricting it properly means giving the session a role and writing that
-- role into the policies.
--
-- 'full'  - unchanged, everything as before.
-- 'costs' - may read and write the Cost Book (settings), and READ master_products and accounts
--           so products can be identified. Cannot touch sales history, OpEx, stock, tasks, the
--           SKU map or the uploaded report files, so no revenue, profit or order data is
--           reachable at all.
--
-- Two things this file must respect, both learned the hard way in earlier migrations:
--   * pgcrypto lives in the "extensions" schema, so crypt/gen_salt are written as
--     extensions.crypt(...) - see 0009.
--   * policies must call a SECURITY DEFINER function, never an inline subquery against
--     verified_users: "authenticated" has no grants on that table, so an inline subquery is
--     itself blocked and the whole policy fails shut - see 0010.

-- ---------- 1. access_gate must be able to hold more than one row ----------
-- It was created with check (id = 1), which would reject the second password outright.
do $$
declare
  c text;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    where ns.nspname = 'instasales' and rel.relname = 'access_gate' and con.contype = 'c'
  loop
    execute format('alter table instasales.access_gate drop constraint %I;', c);
  end loop;
end $$;

alter table instasales.access_gate  add column if not exists role text not null default 'full';
alter table instasales.verified_users add column if not exists role text not null default 'full';

update instasales.access_gate set role = 'full' where id = 1;

-- ---------- 2. the Cost-Manager password ----------
insert into instasales.access_gate (id, password_hash, role)
values (2, extensions.crypt('soungiyoun', extensions.gen_salt('bf')), 'costs')
on conflict (id) do update
  set password_hash = extensions.crypt('soungiyoun', extensions.gen_salt('bf')),
      role = 'costs';

-- ---------- 3. verify against any role's password ----------
create or replace function instasales.verify_access_password(attempt text)
returns boolean
language plpgsql
security definer
set search_path = instasales, public, extensions, pg_temp
as $$
declare
  r record;
begin
  -- Most privileged first, so a browser that knows the full password is never downgraded
  -- by also happening to match a weaker one.
  for r in select password_hash, role from instasales.access_gate
           order by case when role = 'full' then 0 else 1 end, id
  loop
    if r.password_hash is not null and r.password_hash = extensions.crypt(attempt, r.password_hash) then
      insert into instasales.verified_users (user_id, role)
      values (auth.uid(), r.role)
      on conflict (user_id) do update set verified_at = now(), role = excluded.role;
      return true;
    end if;
  end loop;
  return false;
end;
$$;

revoke all on function instasales.verify_access_password(text) from public, anon;
grant execute on function instasales.verify_access_password(text) to authenticated;

-- ---------- 4. role helpers (SECURITY DEFINER - the policies call these) ----------
create or replace function instasales.my_access_role()
returns text
language sql
security definer
set search_path = instasales, pg_temp
as $$
  select role from instasales.verified_users where user_id = auth.uid();
$$;

create or replace function instasales.has_full_access()
returns boolean
language sql
security definer
set search_path = instasales, pg_temp
as $$
  select exists(
    select 1 from instasales.verified_users
    where user_id = auth.uid() and role = 'full'
  );
$$;

revoke all on function instasales.my_access_role()  from public, anon;
revoke all on function instasales.has_full_access() from public, anon;
grant execute on function instasales.my_access_role()  to authenticated;
grant execute on function instasales.has_full_access() to authenticated;

-- am_i_verified() stays true for either role, so the existing load path is unchanged.

-- ---------- 5. policies ----------
-- Everything the 'costs' role must not reach.
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'sku_map','stock','opex','tasks','history_daily','history_snapshots','uploaded_files'
  ])
  loop
    execute format('drop policy if exists "password_verified_full_access" on instasales.%I;', t);
    execute format('drop policy if exists "full_role_only" on instasales.%I;', t);
    execute format(
      $f$create policy "full_role_only" on instasales.%I
        for all to authenticated
        using (instasales.has_full_access())
        with check (instasales.has_full_access());$f$,
      t
    );
  end loop;
end $$;

-- settings holds the Cost Book, so both roles read and write it.
drop policy if exists "password_verified_full_access" on instasales.settings;
drop policy if exists "any_verified_role" on instasales.settings;
create policy "any_verified_role" on instasales.settings
  for all to authenticated
  using (instasales.am_i_verified())
  with check (instasales.am_i_verified());

-- accounts and master_products: both roles read, only 'full' writes.
do $$
declare
  t text;
begin
  for t in select unnest(array['accounts','master_products'])
  loop
    execute format('drop policy if exists "password_verified_full_access" on instasales.%I;', t);
    execute format('drop policy if exists "any_verified_read" on instasales.%I;', t);
    execute format('drop policy if exists "full_role_write" on instasales.%I;', t);
    execute format(
      $f$create policy "any_verified_read" on instasales.%I
        for select to authenticated
        using (instasales.am_i_verified());$f$, t);
    execute format(
      $f$create policy "full_role_write" on instasales.%I
        for all to authenticated
        using (instasales.has_full_access())
        with check (instasales.has_full_access());$f$, t);
  end loop;
end $$;

-- ---------- 6. check ----------
-- Should return one row per role: 1/full and 2/costs.
select id, role from instasales.access_gate order by id;
