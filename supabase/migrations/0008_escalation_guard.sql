-- Med List (Aging) — make the escalation schedule safe before its secrets exist.
--
-- 0007 scheduled the job with the Vault lookups inline. Applied to a project
-- where the two secrets have not been created yet, that is a `net.http_post`
-- with a null url every fifteen minutes, forever, each one a failed cron run in
-- the log. Nothing is broken by it, but a permanently red job is exactly the
-- kind of noise that gets ignored right up until it matters.
--
-- Fixed forward rather than by editing 0007, because migrations are append-only
-- once applied anywhere (D13). Bond's 0012 exists because 0005 was edited after
-- the fact, and the two databases disagreed about what had run.

create or replace function public.run_check_in_escalation()
returns void
language plpgsql security definer set search_path = public, extensions, vault
as $$
declare
    v_url text;
    v_key text;
begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'escalation_function_url';
    select decrypted_secret into v_key
      from vault.decrypted_secrets where name = 'escalation_service_key';

    -- Not configured yet. Say so once per run and stop, rather than failing.
    if v_url is null or v_key is null then
        raise notice 'escalation secrets not set; skipping';
        return;
    end if;

    perform net.http_post(
        url     := v_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_key
        ),
        body    := '{}'::jsonb,
        timeout_milliseconds := 20000
    );
end;
$$;

revoke execute on function public.run_check_in_escalation() from public, authenticated, anon;

do $$
begin
    if not exists (select 1 from pg_extension where extname = 'pg_cron') then
        raise notice 'pg_cron not present; skipping schedule';
        return;
    end if;

    perform cron.unschedule('aging-escalate-check-ins')
      where exists (select 1 from cron.job where jobname = 'aging-escalate-check-ins');

    perform cron.schedule(
        'aging-escalate-check-ins',
        '*/15 * * * *',
        'select public.run_check_in_escalation();'
    );
end
$$;

notify pgrst, 'reload schema';
