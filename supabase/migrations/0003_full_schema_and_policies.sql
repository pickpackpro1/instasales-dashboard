-- InstaSales — FULL schema, in one file. Safe to run even if 0001/0002 already ran
-- (every statement is idempotent: CREATE ... IF NOT EXISTS, or DROP POLICY IF EXISTS
-- before CREATE POLICY). This is the single source of truth going forward.
--
-- Isolated in its own "instasales" schema so nothing here can ever collide with the
-- other app's tables in this same Supabase project.

create schema if not exists instasales;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists instasales.accounts (
  id text primary key,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists instasales.master_products (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  platform text not null,
  name text,
  sku text,
  asin text,
  product_id text,
  country text,
  currency text,
  buying_cost_per_unit numeric,
  operational_cost_per_unit numeric,
  shipping_cost_per_unit numeric,
  referral_pct numeric,
  affiliate_pct numeric,
  shopads_pct numeric,
  regulatory_pct numeric,
  fixed_fee_per_unit numeric,
  selling_price numeric,
  updated_at timestamptz not null default now()
);
create index if not exists idx_master_products_account on instasales.master_products(account_id);

create table if not exists instasales.sku_map (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists instasales.stock (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  product_name text not null,
  daily jsonb not null default '{}'::jsonb,
  inventory numeric,
  actions text,
  alarm text,
  updated_at timestamptz not null default now(),
  unique(account_id, product_name)
);

create table if not exists instasales.opex (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  name text not null,
  amount numeric not null,
  channel text not null default 'all'
);

create table if not exists instasales.tasks (
  id bigint generated always as identity primary key,
  account_id text references instasales.accounts(id) on delete cascade,
  text text not null,
  done boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists instasales.history_daily (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  channel text not null,
  date date not null,
  revenue numeric not null default 0,
  units integer not null default 0,
  refunds numeric not null default 0,
  orders integer not null default 0,
  unique(account_id, channel, date)
);

create table if not exists instasales.history_snapshots (
  id bigint primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  saved_at date not null,
  from_date date,
  to_date date,
  channels jsonb not null,
  skus jsonb,
  created_at timestamptz not null default now()
);

create table if not exists instasales.settings (
  account_id text primary key references instasales.accounts(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists instasales.uploaded_files (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  file_type text not null,
  file_name text not null,
  rows jsonb not null,
  row_count integer not null default 0,
  uploaded_at timestamptz not null default now(),
  unique(account_id, file_type, file_name)
);
create index if not exists idx_uploaded_files_account on instasales.uploaded_files(account_id, file_type);

-- ---------------------------------------------------------------------------
-- Row Level Security: enabled on every table.
-- ---------------------------------------------------------------------------

alter table instasales.accounts            enable row level security;
alter table instasales.master_products     enable row level security;
alter table instasales.sku_map             enable row level security;
alter table instasales.stock               enable row level security;
alter table instasales.opex                enable row level security;
alter table instasales.tasks               enable row level security;
alter table instasales.history_daily       enable row level security;
alter table instasales.history_snapshots   enable row level security;
alter table instasales.settings            enable row level security;
alter table instasales.uploaded_files      enable row level security;

-- ---------------------------------------------------------------------------
-- Policies: any LOGGED-IN user (Supabase Auth) has full read/write access.
-- The anon (public, unauthenticated) role gets NO policy at all - it is fully
-- denied by default. This is a single shared-team tool, not per-user data, so
-- there is no per-row ownership check - just "are you logged in at all".
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'accounts','master_products','sku_map','stock','opex','tasks',
    'history_daily','history_snapshots','settings','uploaded_files'
  ])
  loop
    execute format('drop policy if exists "authenticated_full_access" on instasales.%I;', t);
    execute format(
      'create policy "authenticated_full_access" on instasales.%I for all to authenticated using (true) with check (true);',
      t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Grants: PostgREST also checks plain Postgres privileges, not just RLS.
-- authenticated gets full CRUD grants; anon gets NOTHING on this schema at all.
-- ---------------------------------------------------------------------------

grant usage on schema instasales to authenticated;
grant select, insert, update, delete on all tables in schema instasales to authenticated;
grant usage, select on all sequences in schema instasales to authenticated;

alter default privileges in schema instasales
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema instasales
  grant usage, select on sequences to authenticated;
