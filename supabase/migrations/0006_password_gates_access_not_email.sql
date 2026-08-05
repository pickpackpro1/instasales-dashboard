-- Revised access model: Google sign-in is open to ANY Google account (no email
-- allow-list) - it just proves you're a real authenticated person. The actual gate
-- to real data is the password check: only a signed-in user who has successfully
-- called verify_access_password() with the correct password gets data access.
-- This replaces the email-allow-list model from 0005.

-- Tracks which signed-in users have passed the password check. Not directly
-- readable/writable by anyone via the API (RLS on, zero policies) - only the
-- SECURITY DEFINER function below can write to it.
create table if not exists instasales.verified_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  verified_at timestamptz not null default now()
);
alter table instasales.verified_users enable row level security;

-- Replaces the 0005 version: on a correct password, marks the CURRENT signed-in
-- user (auth.uid()) as verified. From then on, that Google account has access -
-- no re-entry needed on future visits/sign-ins with the same account.
create or replace function instasales.verify_access_password(attempt text)
returns boolean
language plpgsql
security definer
set search_path = instasales, pg_temp
as $$
declare
  stored text;
  ok boolean;
begin
  select password_hash into stored from instasales.access_gate where id = 1;
  if stored is null then
    return false;
  end if;
  ok := (stored = crypt(attempt, stored));
  if ok then
    insert into instasales.verified_users (user_id)
    values (auth.uid())
    on conflict (user_id) do update set verified_at = now();
  end if;
  return ok;
end;
$$;

revoke all on function instasales.verify_access_password(text) from public, anon;
grant execute on function instasales.verify_access_password(text) to authenticated;

-- Swap every table's policy: authenticated AND already password-verified (instead
-- of authenticated AND email-allow-listed).
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'accounts','master_products','sku_map','stock','opex','tasks',
    'history_daily','history_snapshots','settings','uploaded_files'
  ])
  loop
    execute format('drop policy if exists "allowed_email_full_access" on instasales.%I;', t);
    execute format('drop policy if exists "authenticated_full_access" on instasales.%I;', t);
    execute format(
      $f$create policy "password_verified_full_access" on instasales.%I
        for all to authenticated
        using (auth.uid() in (select user_id from instasales.verified_users))
        with check (auth.uid() in (select user_id from instasales.verified_users));$f$,
      t
    );
  end loop;
end $$;

-- The email allow-list from 0005 is no longer part of the access model - drop it.
drop table if exists instasales.allowed_emails;
