-- Everything else that was previously local-only: the raw uploaded platform files
-- (what used to live in IndexedDB) and a single JSONB "settings" catch-all covering
-- every remaining bit of app/UI state (VAT config, fallback rates, enabled KPI tiles,
-- active date filter, sort/search state, etc.) so genuinely nothing is left local.

create table if not exists instasales.uploaded_files (
  id bigint generated always as identity primary key,
  account_id text not null references instasales.accounts(id) on delete cascade,
  file_type text not null,        -- e.g. 'tt_orders', 'amz_biz', 'ebay_txn', 'amz2_biz', ...
  file_name text not null,        -- original filename - re-uploading the same name replaces it
  rows jsonb not null,
  row_count integer not null default 0,
  uploaded_at timestamptz not null default now(),
  unique(account_id, file_type, file_name)
);
create index if not exists idx_uploaded_files_account on instasales.uploaded_files(account_id, file_type);

alter table instasales.uploaded_files enable row level security;

-- instasales.settings (created in 0001) is the catch-all for every remaining setting:
-- { vat: {...}, amzRef, ttRate, shopFee, amzRefund, enabledKpis: [...], chFilter,
--   dataSource, dateFrom, dateTo, custFrom, custTo, ttAdsMode, amzDateMode,
--   skuSort, skuSearch, ... } - one JSON document per account, whatever shape the
-- app needs. No schema change required for it; it already exists.
