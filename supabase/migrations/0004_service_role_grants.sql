-- service_role bypasses Row Level Security, but it still needs plain Postgres GRANT
-- privileges on the schema/tables/sequences to be usable via PostgREST at all
-- (RLS bypass and object-level grants are two separate things). 0003 only granted
-- to `authenticated` - this fills in `service_role` too (used for admin/verification
-- work, never exposed to the browser).

grant usage on schema instasales to service_role;
grant select, insert, update, delete on all tables in schema instasales to service_role;
grant usage, select on all sequences in schema instasales to service_role;

alter default privileges in schema instasales
  grant select, insert, update, delete on tables to service_role;
alter default privileges in schema instasales
  grant usage, select on sequences to service_role;
