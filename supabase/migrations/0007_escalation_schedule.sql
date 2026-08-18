-- Med List (Aging) — the scheduled half of the check-in.
--
-- 0003 built the tables, the policies and recipients_due_for_escalation(). This
-- file is what actually makes the family hear about it.
--
-- Escalation is entirely server-driven (D25) and that is not an optimisation.
-- The whole point of the feature is that nobody's phone had to do anything: if
-- Mom's phone is flat, off, or in a drawer, a client-scheduled job on her device
-- is exactly as silent as she is. iOS background refresh is granted
-- unpredictably even on a healthy device, so anything that must be reliable
-- either runs on the server or is a local notification the OS guarantees.
--
-- Language boundary, restated because this is the file where it would get
-- broken: nothing here detects an emergency, assesses anyone, or summons help.
-- It reports that a button was not pressed. See I6.

-- ============================================================
-- Extensions
--
-- Guarded, because scripts/test-db.sh applies every migration to a bare local
-- PostgreSQL that has neither of these. The scheduling below is skipped there
-- too; the RLS and RPC tests do not exercise cron.
-- ============================================================
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        create extension if not exists pg_cron;
    end if;
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
        create extension if not exists pg_net;
    end if;
end
$$;

-- ============================================================
-- Notices: things the family has to be told, queued for the pusher.
--
-- A table rather than a direct push from the client, for two reasons. A subject
-- leaving the group (D27) must be announced even if their phone dies the moment
-- after they tap it, and the announcement must not depend on the leaving
-- device's goodwill. And a queue is retryable; a fire-and-forget push is not.
-- ============================================================
create table if not exists public.group_notices (
    id           uuid primary key default gen_random_uuid(),
    group_id     uuid not null,
    kind         text not null check (kind in (
        'no_check_in', 'subject_left', 'member_removed', 'subject_joined'
    )),
    -- Rendered server-side so the push body is identical on every device and
    -- cannot drift between app versions.
    title        text not null default '',
    body         text not null default '',
    -- Who it is about, for deep-linking. Nullable: not every notice is about a
    -- recipient.
    subject_name text not null default '',
    -- Never delivered to this member; they are the one who caused it.
    exclude_user uuid,
    created_at   timestamptz not null default now(),
    delivered_at timestamptz
);

create index if not exists group_notices_pending_idx
    on public.group_notices(created_at) where delivered_at is null;

alter table public.group_notices enable row level security;

create policy "group_notices_member_select"
    on public.group_notices for select
    using (public.is_group_member(group_id));

-- No client write policies at all. Rows are written by the security-definer
-- functions below and drained by the escalation function running as the service
-- role. A client that could insert here could push arbitrary text to a family.

-- ============================================================
-- leave_group, replaced so leaving announces itself.
--
-- Fix-forward rather than editing 0004: migrations are append-only once applied
-- anywhere (D13). Bond's 0012 exists because 0005 was edited after the fact.
--
-- The behaviour is otherwise identical to 0004's, including the deliberate
-- refusal to block a subject from leaving. An app a parent cannot walk away
-- from is a surveillance tool their children installed on them; the safety net
-- is the announcement, not a lock on the door.
-- ============================================================
create or replace function public.leave_group(p_group_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
    v_uid      uuid := (select auth.uid());
    v_role     text;
    v_owners   int;
    v_others   int;
    v_name     text;
begin
    select role into v_role
      from public.group_members
     where group_id = v_group_id and user_id = v_uid and removed_at is null;

    if v_role is null then
        raise exception 'not a member' using errcode = '22023';
    end if;

    select count(*) into v_others
      from public.group_members
     where group_id = v_group_id and user_id <> v_uid and removed_at is null;

    if v_role = 'owner' and v_others > 0 then
        select count(*) into v_owners
          from public.group_members
         where group_id = v_group_id and role = 'owner' and removed_at is null;
        if v_owners <= 1 then
            raise exception 'transfer ownership before leaving' using errcode = '23514';
        end if;
    end if;

    select coalesce(nullif(display_name, ''), 'Someone')
      into v_name
      from public.profiles where id = v_uid;

    -- Queued before the membership row is cleared, while we can still name them.
    if v_others > 0 then
        insert into public.group_notices (
            group_id, kind, title, body, subject_name, exclude_user
        )
        values (
            v_group_id,
            case when v_role = 'subject' then 'subject_left' else 'member_removed' end,
            'Someone left the group',
            coalesce(v_name, 'Someone') || ' left ' ||
                coalesce((select name from public.groups where id = v_group_id), 'the group') || '.',
            coalesce(v_name, ''),
            v_uid
        );
    end if;

    update public.group_members
       set removed_at = now()
     where group_id = v_group_id and user_id = v_uid;

    update public.care_recipients
       set linked_user_id = null
     where group_id = v_group_id and linked_user_id = v_uid;

    if v_others = 0 then
        delete from public.group_notices where group_id = v_group_id;
        delete from public.audit_log where group_id = v_group_id;
        delete from public.groups where id = v_group_id;
    end if;
end;
$$;

-- ============================================================
-- What the pusher needs, in one call.
--
-- Security definer and granted only to service_role: it reads other people's
-- APNs tokens, which no client has any business seeing.
-- ============================================================
create or replace function public.pending_notices_with_targets()
returns table (
    notice_id  uuid,
    title      text,
    body       text,
    apns_token text
)
language sql stable security definer set search_path = public
as $$
    select n.id, n.title, n.body, p.apns_token
      from public.group_notices n
      join public.group_members m
        on m.group_id = n.group_id
       and m.removed_at is null
       -- Only staff are told. A subject is not a supervisor of the family.
       and m.role in ('owner', 'caregiver')
       and (n.exclude_user is null or m.user_id <> n.exclude_user)
      join public.profiles p
        on p.id = m.user_id
       and p.apns_token is not null
     where n.delivered_at is null
       and n.created_at > now() - interval '2 days';
$$;

revoke execute on function public.pending_notices_with_targets() from public, authenticated, anon;
grant execute on function public.pending_notices_with_targets() to service_role;

-- ============================================================
-- Queue today's missed check-ins, and stamp them so the 15-minute cadence
-- cannot send the same family the same sentence four times an hour.
--
-- The stamp and the insert are one statement for that reason.
-- ============================================================
create or replace function public.queue_check_in_notices()
returns int
language plpgsql security definer set search_path = public
as $$
declare
    v_count int := 0;
begin
    with due as (
        select * from public.recipients_due_for_escalation()
    ), stamped as (
        update public.check_in_settings s
           set last_escalated_on = d.local_date
          from due d
         where s.care_recipient_id = d.care_recipient_id
        returning s.care_recipient_id, s.group_id
    )
    insert into public.group_notices (group_id, kind, title, body, subject_name)
    select
        d.group_id,
        'no_check_in',
        -- Statement of fact, never an assessment. "Alert", "emergency",
        -- "monitoring" and anything implying help is coming are out of bounds
        -- here for the reasons in I6 and 03 §2.
        'No check-in today',
        d.recipient_name || ' has not checked in today.',
        d.recipient_name
      from due d
      join stamped st on st.care_recipient_id = d.care_recipient_id;

    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

revoke execute on function public.queue_check_in_notices() from public, authenticated, anon;
grant execute on function public.queue_check_in_notices() to service_role;

create or replace function public.mark_notices_delivered(p_ids uuid[])
returns void
language sql security definer set search_path = public
as $$
    update public.group_notices
       set delivered_at = now()
     where id = any(p_ids) and delivered_at is null;
$$;

revoke execute on function public.mark_notices_delivered(uuid[]) from public, authenticated, anon;
grant execute on function public.mark_notices_delivered(uuid[]) to service_role;

-- A device that has been reinstalled or had notifications turned off leaves a
-- token that APNs rejects permanently. Clearing it stops us retrying forever.
create or replace function public.clear_apns_token(p_token text)
returns void
language sql security definer set search_path = public
as $$
    update public.profiles set apns_token = null where apns_token = p_token;
$$;

revoke execute on function public.clear_apns_token(text) from public, authenticated, anon;
grant execute on function public.clear_apns_token(text) to service_role;

-- ============================================================
-- Surrogate attestation (D28).
--
-- The client sends only the timestamp. Who attested is stamped here, so a
-- device cannot claim the attestation was someone else's, and a later sync that
-- omits the column cannot quietly blank out the answer.
--
-- Note what this does not do: it does not assess whether the recipient could
-- have consented themselves. The app never assesses capacity (D29). It asks a
-- caregiver a plain question and records that they answered it.
-- ============================================================
create or replace function public.stamp_surrogate_attestation()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
    -- Once recorded, it stays recorded, and it keeps the attester it was
    -- recorded with. Checked first so an existing attestation wins outright.
    if tg_op = 'UPDATE' and old.surrogate_attested_at is not null then
        new.surrogate_attested_at := old.surrogate_attested_at;
        new.surrogate_attested_by := old.surrogate_attested_by;
        return new;
    end if;

    if new.surrogate_attested_at is not null then
        -- Overwritten, not defaulted. A client that names someone else as the
        -- attester is claiming a surrogate decision on their behalf, which is
        -- the one thing this column exists to make impossible.
        new.surrogate_attested_by := (select auth.uid());
    else
        new.surrogate_attested_by := null;
    end if;
    return new;
end;
$$;

drop trigger if exists care_recipients_attestation on public.care_recipients;
create trigger care_recipients_attestation
    before insert or update on public.care_recipients
    for each row execute function public.stamp_surrogate_attestation();

-- ============================================================
-- The schedule.
--
-- Every 15 minutes rather than once a day, because "the window plus grace has
-- passed" happens at a different wall-clock instant for every time zone in the
-- table, and a family in Auckland should not wait for midnight in Los Angeles.
--
-- The two secrets are read from Vault at call time and are deliberately not in
-- this file. Insert them once per environment:
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/escalate-check-ins',
--                              'escalation_function_url');
--   select vault.create_secret('<service-role-key>', 'escalation_service_key');
-- ============================================================
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
        $job$
        select net.http_post(
            url := (select decrypted_secret from vault.decrypted_secrets
                     where name = 'escalation_function_url'),
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                                where name = 'escalation_service_key')
            ),
            body := '{}'::jsonb,
            timeout_milliseconds := 20000
        );
        $job$
    );
end
$$;

notify pgrst, 'reload schema';
