-- TEST-ONLY. Mirrors the table grants Supabase gives the `authenticated` role
-- by default, applied after the migrations so RLS (not a missing GRANT) is what
-- the tests are actually exercising.
--
-- Real Supabase grants these through default privileges on the public schema.
-- If a test passes here but fails in production, suspect this file first.

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
