-- Two-layer access control:
-- 1) Google sign-in only grants real data access if the signed-in email is on the
--    allow-list below (this REPLACES the old "any authenticated user" policy - Google
--    login alone is not enough, the email must be pre-approved).
-- 2) A separate PIN/password gate, checked server-side via a SECURITY DEFINER function
--    so the stored hash is never sent to the browser and never readable directly even
--    by an allowed, logged-in user. This is the "type a password, hit enter, the app
--    checks the database, then grants access" screen.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1) Email allow-list
-- ---------------------------------------------------------------------------

create table if not exists instasales.allowed_emails (
  email text primary key
);
alter table instasales.allowed_emails enable row level security;
-- no policies on this table at all - nobody can read/write it via the API, only
-- managed by you directly in the SQL Editor (or by a service-role admin task).

-- swap every table's policy from "any authenticated user" to "authenticated AND
-- their email is on the allow-list"
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
      $f$create policy "allowed_email_full_access" on instasales.%I
        for all to authenticated
        using (auth.jwt() ->> 'email' in (select email from instasales.allowed_emails))
        with check (auth.jwt() ->> 'email' in (select email from instasales.allowed_emails));$f$,
      t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Password/PIN gate - checked entirely server-side
-- ---------------------------------------------------------------------------

create table if not exists instasales.access_gate (
  id int primary key default 1,
  password_hash text not null,
  check (id = 1)
);
alter table instasales.access_gate enable row level security;
-- no policies here either - the raw hash is never directly readable via the API,
-- only through the function below (which runs as the function owner, bypassing RLS).

create or replace function instasales.verify_access_password(attempt text)
returns boolean
language plpgsql
security definer
set search_path = instasales, pg_temp
as $$
declare
  stored text;
begin
  select password_hash into stored from instasales.access_gate where id = 1;
  if stored is null then
    return false;
  end if;
  return stored = crypt(attempt, stored);
end;
$$;

-- only a logged-in (Google) user may even attempt the password check
revoke all on function instasales.verify_access_password(text) from public, anon;
grant execute on function instasales.verify_access_password(text) to authenticated;
