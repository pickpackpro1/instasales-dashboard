-- A copy of the stock history that the app cannot overwrite.
--
-- Weekly Stock Tracking is saved by deleting every row for the account and writing the browser's
-- copy back. On 1 October a browser whose copy had not finished loading did exactly that and
-- replaced 57 days of daily figures with the single day it was holding. The app no longer works
-- that way - it merges - but the data is worth more than one layer of protection, and nothing in
-- the database itself was stopping it.
--
-- Every row that is about to be deleted or changed is copied here first, at most one copy per
-- product per calendar day, and only when the row being replaced actually had figures in it. A
-- copy is only overwritten by one holding at least as many days, so a wipe can never shrink the
-- archive. Recovering is then a plain insert back into instasales.stock.
--
-- Safe to run at any time: one new table, one helper, one trigger function, two triggers. Nothing
-- existing is altered, and the app does not need to know this exists.

create table if not exists instasales.stock_archive (
  account_id   text        not null,
  product_name text        not null,
  day_key      date        not null default current_date,
  daily        jsonb       not null,
  inventory    numeric,
  archived_at  timestamptz not null default now(),
  primary key (account_id, product_name, day_key)
);

-- how many days a stored figure set holds; used to refuse a smaller copy
create or replace function instasales.jsonb_keys_count(j jsonb)
returns int language sql immutable as $$
  select coalesce((select count(*)::int from jsonb_object_keys(coalesce(j, '{}'::jsonb))), 0);
$$;

create or replace function instasales.archive_stock()
returns trigger language plpgsql security definer set search_path = instasales, public as $$
begin
  if OLD.daily is not null and instasales.jsonb_keys_count(OLD.daily) > 0 then
    insert into instasales.stock_archive as a (account_id, product_name, day_key, daily, inventory)
    values (OLD.account_id, OLD.product_name, current_date, OLD.daily, OLD.inventory)
    on conflict (account_id, product_name, day_key) do update
      set daily = excluded.daily, inventory = excluded.inventory, archived_at = now()
      where instasales.jsonb_keys_count(excluded.daily) >= instasales.jsonb_keys_count(a.daily);
  end if;
  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end $$;

drop trigger if exists stock_archive_del on instasales.stock;
create trigger stock_archive_del before delete on instasales.stock
  for each row execute function instasales.archive_stock();

drop trigger if exists stock_archive_upd on instasales.stock;
create trigger stock_archive_upd before update on instasales.stock
  for each row execute function instasales.archive_stock();

-- readable by a signed-in, verified user, like every other table here; written only by the trigger
alter table instasales.stock_archive enable row level security;
drop policy if exists "verified_read_stock_archive" on instasales.stock_archive;
create policy "verified_read_stock_archive" on instasales.stock_archive
  for select to authenticated using (instasales.am_i_verified());
grant select on instasales.stock_archive to authenticated;

-- start with what is there today, so the archive is useful from the moment this is run
insert into instasales.stock_archive (account_id, product_name, day_key, daily, inventory)
select account_id, product_name, current_date, daily, inventory
  from instasales.stock
 where daily is not null and daily <> '{}'::jsonb
    on conflict (account_id, product_name, day_key) do nothing;

-- Housekeeping, whenever it gets large (one copy per product per day adds up over a year):
--   delete from instasales.stock_archive where archived_at < now() - interval '180 days';
--
-- To put a day back for every product:
--   update instasales.stock s
--      set daily = a.daily || s.daily          -- the live figures win where both have a day
--     from (select distinct on (account_id, product_name) * from instasales.stock_archive
--            where account_id = 'instamart' order by account_id, product_name, day_key desc) a
--    where s.account_id = a.account_id and s.product_name = a.product_name;
