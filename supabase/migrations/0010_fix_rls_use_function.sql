-- Bug: every table's RLS policy checked
--   auth.uid() in (select user_id from instasales.verified_users)
-- as an inline subquery. That subquery runs AS the querying role (authenticated), which
-- has zero grants/policies on verified_users (intentionally, so only the security-definer
-- functions could touch it) - so the subquery itself gets blocked, and the whole policy
-- check fails, blocking ALL writes/reads on every table even for a verified user.
--
-- Fix: use instasales.am_i_verified() itself (SECURITY DEFINER, bypasses RLS internally)
-- as the policy condition instead of an inline subquery against the locked-down table.

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'accounts','master_products','sku_map','stock','opex','tasks',
    'history_daily','history_snapshots','settings','uploaded_files'
  ])
  loop
    execute format('drop policy if exists "password_verified_full_access" on instasales.%I;', t);
    execute format(
      $f$create policy "password_verified_full_access" on instasales.%I
        for all to authenticated
        using (instasales.am_i_verified())
        with check (instasales.am_i_verified());$f$,
      t
    );
  end loop;
end $$;
