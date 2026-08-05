-- InstaSales dashboard schema.
-- Lives in its own schema ("instasales") so it can never collide with tables from any
-- other app running in this same Supabase project.
--
-- Every table has Row Level Security ENABLED with NO policies yet. That means, right now,
-- nobody (not even the anon key) can read or write any of this through the API - which is
-- the safe default while this app has no login/auth of its own. Once auth is added, we'll
-- add policies scoped to the authenticated user. Until then, this schema exists but the
-- app cannot talk to it yet.

create schema if not exists instasales;

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

-- Safe by default: RLS on, zero policies, for every table.
alter table instasales.accounts            enable row level security;
alter table instasales.master_products     enable row level security;
alter table instasales.sku_map             enable row level security;
alter table instasales.stock               enable row level security;
alter table instasales.opex                enable row level security;
alter table instasales.tasks               enable row level security;
alter table instasales.history_daily       enable row level security;
alter table instasales.history_snapshots   enable row level security;
alter table instasales.settings            enable row level security;
