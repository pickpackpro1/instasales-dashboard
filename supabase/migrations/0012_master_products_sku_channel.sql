-- Two columns the master sheet has and the shared copy did not.
--
-- master_products is rebuilt from named columns, so anything without a column is dropped on the
-- way through. 'SKU CHANNEL' (Merchant / Amazon) and 'FBA Fees' were both missing, which meant
-- a browser loading the shared copy got every offer tagged FBM at a zero fulfilment fee - wrong
-- costs, quietly, and different from whichever browser still had the sheet cached locally.
--
-- Safe to run at any time: two nullable columns, no policy or function changes, nothing dropped.

alter table instasales.master_products
  add column if not exists sku_channel text,
  add column if not exists fba_fees    numeric;

-- After running this, re-upload the master sheet once from the account that has it. That pushes
-- a complete copy up, and every other browser picks it up on its next load.
