-- A second password that grants COST MANAGER ONLY access.
--
-- Why this is a database change and not a UI one: every table's policy checks
-- membership of verified_users, so hiding menu items in the browser would restrict
-- nothing - the data is still fetchable. Restricting it properly means giving the
-- session a role and writing that role into the policies.
--
-- 'full'  - unchanged, everything as before.
-- 'costs' - may read and write the Cost Book (settings), and READ master_products and
--           accounts so products can be identified. Cannot touch sales history, OpEx,
--           stock, tasks, the SKU map or uploaded report files, so no revenue, profit
--           or order data is reachable at all.

-- ---------- 1. roles on the verified list ----------
alter table instasales.verified_users
  add column if not exists role text not null default 'full';

-- ---------- 2. a second password ----------
-- access_gate holds one row per role. Row 1 is the existing full-access password and is
-- left exactly as it is.
alter table instasales.access_gate
  add column if not exists role text not null default 'full';

update instasales.access_gate set role = 'full' where id = 1 and role is distinct from 'full';

-- Set the Cost-Manager password here. Change 'CHANGE-ME' before running, or run the
-- update at the bottom of this file afterwards.
insert into instasales.access_gate (id, password_hash, role)
values (2, crypt('CHANGE-ME', gen_salt('bf')), 'costs')
on conflict (id) do nothing;

-- ---------- 3. verify against any role's password ----------
create or replace function instasales.verify_access_password(attempt text)
returns boolean
language plpgsql
security definer
set search_path = instasales, pg_temp
as $$
declare
  r record;
begin
  -- Check every configured password, most privileged first, so a shared browser that
  -- knows the full password is never downgraded by also matching a weaker one.
  for r in select password_hash, role from instasales.access_gate
           order by case when role = 'full' then 0 else 1 end, id
  loop
    if r.password_hash is not null and r.password_hash = crypt(attempt, r.password_hash) then
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

-- ---------- 4. let the app ask which role it has ----------
create or replace function instasales.my_access_role()
returns text
language sql
security definer
set search_path = instasales, pg_temp
as $$
  select role from instasales.verified_users where user_id = auth.uid();
$$;

revoke all on function instasales.my_access_role() from public, anon;
grant execute on function instasales.my_access_role() to authenticated;

-- am_i_verified stays true for either role, so the existing load path is unchanged.

-- ---------- 5. policies ----------
-- Everything the 'costs' role must NOT see: full access stays limited to role 'full'.
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'sku_map','stock','opex','tasks','history_daily','history_snapshots','uploaded_files'
  ])
  loop
    execute format('drop policy if exists "password_verified_full_access" on instasales.%I;', t);
    execute format(
      $f$create policy "full_role_only" on instasales.%I
        for all to authenticated
        using (auth.uid() in (select user_id from instasales.verified_users where role = 'full'))
        with check (auth.uid() in (select user_id from instasales.verified_users where role = 'full'));$f$,
      t
    );
  end loop;
end $$;

-- settings holds the Cost Book, so both roles may read and write it.
drop policy if exists "password_verified_full_access" on instasales.settings;
create policy "any_verified_role" on instasales.settings
  for all to authenticated
  using (auth.uid() in (select user_id from instasales.verified_users))
  with check (auth.uid() in (select user_id from instasales.verified_users));

-- accounts: both roles read; only 'full' writes.
drop policy if exists "password_verified_full_access" on instasales.accounts;
create policy "any_verified_read" on instasales.accounts
  for select to authenticated
  using (auth.uid() in (select user_id from instasales.verified_users));
create policy "full_role_write" on instasales.accounts
  for all to authenticated
  using (auth.uid() in (select user_id from instasales.verified_users where role = 'full'))
  with check (auth.uid() in (select user_id from instasales.verified_users where role = 'full'));

-- master_products: 'costs' reads it so products can be named; only 'full' changes it.
drop policy if exists "password_verified_full_access" on instasales.master_products;
create policy "any_verified_read" on instasales.master_products
  for select to authenticated
  using (auth.uid() in (select user_id from instasales.verified_users));
create policy "full_role_write" on instasales.master_products
  for all to authenticated
  using (auth.uid() in (select user_id from instasales.verified_users where role = 'full'))
  with check (auth.uid() in (select user_id from instasales.verified_users where role = 'full'));

-- ---------- 6. set the Cost-Manager password ----------
-- Run this on its own, with your own password, then delete it from your SQL history:
--
--   update instasales.access_gate
--      set password_hash = crypt('your-cost-manager-password', gen_salt('bf'))
--    where id = 2;
