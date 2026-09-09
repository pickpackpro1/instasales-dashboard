-- Buyer-paid shipping, per product.
--
-- TikTok revenue is the "SKU Subtotal After Discount" from the orders file, which is the product
-- price alone - what the buyer pays for delivery was never part of it. Where TikTok passes that
-- across to the seller it IS revenue, so it is now held per product and added to the selling
-- price before profit, ROI and margin are worked out.
--
-- Same reason as 0012 for needing a column: master_products is rebuilt from named columns, so a
-- field without one is silently dropped on the way through the shared copy and every browser
-- that loads it would lose the figure.
--
-- Safe to run at any time: one nullable column, no policy or function changes, nothing dropped.

alter table instasales.master_products
  add column if not exists buyer_shipping_per_unit numeric;

-- After running this, re-upload the master sheet once from the account that has it, so the
-- shared copy carries the column for every other browser.
