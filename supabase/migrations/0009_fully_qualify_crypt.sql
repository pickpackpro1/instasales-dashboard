-- pgcrypto is confirmed to live in the "extensions" schema (checked directly via
-- pg_extension), yet the search_path-based fix in 0008 still didn't resolve crypt().
-- Stop relying on search_path resolution entirely - call extensions.crypt(...) with
-- the schema written directly, which removes any ambiguity.

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
  ok := (stored = extensions.crypt(attempt, stored));
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
