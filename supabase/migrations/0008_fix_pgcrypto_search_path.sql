-- Fix: verify_access_password() couldn't find crypt()/gen_salt() because pgcrypto's
-- functions live in Supabase's "extensions" (or "public") schema, and the function's
-- search_path was deliberately narrowed to just instasales+pg_temp for security. Widen
-- it to also include public/extensions so the extension functions resolve, while every
-- table reference inside the function stays fully schema-qualified (instasales.xxx) so
-- this doesn't reopen any table-hijacking risk - only extension FUNCTION lookup changes.

create or replace function instasales.verify_access_password(attempt text)
returns boolean
language plpgsql
security definer
set search_path = instasales, public, extensions, pg_temp
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
