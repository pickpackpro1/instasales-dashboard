-- Lets the app check "has THIS browser session already passed the password check"
-- without needing to read verified_users directly (which stays fully locked down).
-- Used on page load so returning visitors who already entered the password once
-- don't have to type it again every time.

create or replace function instasales.am_i_verified()
returns boolean
language sql
security definer
set search_path = instasales, pg_temp
as $$
  select exists(select 1 from instasales.verified_users where user_id = auth.uid());
$$;

revoke all on function instasales.am_i_verified() from public, anon;
grant execute on function instasales.am_i_verified() to authenticated;
