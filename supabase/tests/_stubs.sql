-- Minimal Supabase stand-ins so the migrations can be applied and the RLS/RPC
-- tests can run on a plain PostgreSQL, with no Docker and no Supabase platform.
-- TEST-ONLY. Never applied to a real database.
--
--   * auth.users           : profiles.id FKs to it; delete_account() deletes from it
--   * auth.uid()           : real Supabase reads the JWT; here it reads a GUC set
--                            per-actor via set_config('test.uid', <uuid>, false)
--   * role "authenticated" : the migrations grant EXECUTE on the RPCs to it, and
--                            RLS only bites for a role that does not own the tables
--
-- Borrowed wholesale from ~/bond/supabase/tests/_stubs.sql, extended with the
-- role grants and assertion helpers the RLS tests need.

create extension if not exists pgcrypto;

create schema if not exists auth;

create table if not exists auth.users (
    id                 uuid primary key default gen_random_uuid(),
    email              text,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at         timestamptz not null default now()
);

create or replace function auth.uid()
returns uuid
language sql stable
as $$
    select nullif(current_setting('test.uid', true), '')::uuid;
$$;

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role;
    end if;
end
$$;

grant usage on schema public to authenticated, anon, service_role;
grant usage on schema auth   to authenticated, service_role;

-- ============================================================
-- Assertion helpers
-- ============================================================
create or replace function public.ok(p_cond boolean, p_msg text)
returns void
language plpgsql
as $$
begin
    if p_cond then
        raise notice '  ok   %', p_msg;
    else
        raise exception 'FAIL  %', p_msg;
    end if;
end;
$$;

-- Asserts that the statement raises. Security INVOKER on purpose, so the inner
-- statement runs as whatever role the test has assumed and RLS applies.
create or replace function public.throws(p_sql text, p_msg text)
returns void
language plpgsql
as $$
begin
    begin
        execute p_sql;
    exception when others then
        raise notice '  ok   % [%]', p_msg, sqlerrm;
        return;
    end;
    raise exception 'FAIL  % (expected an error, none was raised)', p_msg;
end;
$$;

-- Asserts that the statement raises with a specific SQLSTATE. `throws` alone is
-- not enough where the *reason* is the point: an authorization refusal (42501)
-- and a malformed-argument refusal (22023) are both "it raised", and the invite
-- role ceiling is only enforced if it is the first one.
create or replace function public.throws_code(p_sql text, p_code text, p_msg text)
returns void
language plpgsql
as $$
begin
    begin
        execute p_sql;
    exception when others then
        if sqlstate = p_code then
            raise notice '  ok   % [%]', p_msg, sqlstate;
            return;
        end if;
        raise exception 'FAIL  % (expected %, got %: %)', p_msg, p_code, sqlstate, sqlerrm;
    end;
    raise exception 'FAIL  % (expected %, no error was raised)', p_msg, p_code;
end;
$$;

-- Act as a given user. Pair with `set role authenticated` so RLS is enforced;
-- `reset role` goes back to the superuser for fixture setup.
create or replace function public.act_as(p_uid uuid)
returns void
language plpgsql
as $$
begin
    perform set_config('test.uid', coalesce(p_uid::text, ''), false);
end;
$$;

create or replace function public.rows_visible(p_sql text)
returns bigint
language plpgsql
as $$
declare
    v_count bigint;
begin
    execute 'select count(*) from (' || p_sql || ') t' into v_count;
    return v_count;
end;
$$;

-- A signup, including the profile row the real handle_new_user() trigger makes.
create or replace function public.make_user(p_name text)
returns uuid
language plpgsql
as $$
declare
    v_id uuid;
begin
    insert into auth.users (raw_user_meta_data)
    values (jsonb_build_object('display_name', p_name))
    returning id into v_id;
    return v_id;
end;
$$;
