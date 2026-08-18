-- Med List (Aging) — audit trail.
--
-- Proportionate, not HIPAA-grade. Aging is a consumer app and is neither a
-- covered entity nor a business associate, so this is about being able to
-- answer "who changed Mom's dosage?" and "who took Sarah out of the group?",
-- which are real questions families ask each other.
--
-- Triggers are attached only to the four tables where the answer matters:
-- medications, dose_logs, group_members, care_recipients. Vitals and visits
-- carry created_by/updated_by columns and that is enough for them.

create table public.audit_log (
    id          uuid primary key default gen_random_uuid(),
    -- Also deliberately not a foreign key, for the same reason as actor_id
    -- below: deleting a group cascades into the audited tables, whose triggers
    -- then try to write an audit row pointing at the group being deleted in the
    -- same transaction. The three places that delete a group clean up their own
    -- audit rows explicitly instead (see 0004).
    group_id    uuid not null,
    table_name  text not null,
    row_id      uuid not null,
    operation   text not null check (operation in ('insert', 'update', 'delete')),
    -- Deliberately NOT a foreign key. An audit row is a historical fact that
    -- outlives the account it describes, and constraining it to a mutable table
    -- breaks in the exact case it is most needed: deleting an account cascades
    -- into group_members, fires this trigger, and the profile row the FK points
    -- at is already gone inside the same transaction. That is a hard failure
    -- that would make account deletion impossible, which is an App Review 5.1.1(v)
    -- requirement. The name snapshot below is what carries the meaning anyway.
    actor_id    uuid,
    -- Snapshot, so the record still reads "Sarah" after Sarah deletes her account.
    actor_name  text not null default '',
    old_data    jsonb,
    new_data    jsonb,
    occurred_at timestamptz not null default now()
);

create index audit_log_group_idx on public.audit_log(group_id, occurred_at desc);
create index audit_log_row_idx   on public.audit_log(row_id, occurred_at desc);

alter table public.audit_log enable row level security;

create policy "audit_log_staff_select"
    on public.audit_log for select
    using (public.is_group_staff(group_id));

-- No client write policies. Rows are written only by the trigger below, which
-- runs as the table owner and is not subject to RLS.

create or replace function public.record_audit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
    v_uid      uuid := (select auth.uid());
    v_name     text := '';
    v_group_id uuid;
    v_row_id   uuid;
begin
    if tg_op = 'DELETE' then
        v_group_id := old.group_id;
        v_row_id   := old.id;
    else
        v_group_id := new.group_id;
        v_row_id   := new.id;
    end if;

    if v_uid is not null then
        select coalesce(display_name, '') into v_name from public.profiles where id = v_uid;
        -- During delete_account() the profile is already gone by the time the
        -- cascade reaches group_members, so fall back to the name that function
        -- stashed before it started deleting.
        if v_name is null or v_name = '' then
            v_name := coalesce(current_setting('app.actor_name', true), '');
        end if;
    end if;

    insert into public.audit_log (
        group_id, table_name, row_id, operation, actor_id, actor_name, old_data, new_data
    )
    values (
        v_group_id,
        tg_table_name,
        v_row_id,
        lower(tg_op),
        v_uid,
        coalesce(v_name, ''),
        case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
        case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
    );

    return null;
end;
$$;

create trigger medications_audit
    after insert or update or delete on public.medications
    for each row execute function public.record_audit();

create trigger dose_logs_audit
    after insert or update or delete on public.dose_logs
    for each row execute function public.record_audit();

create trigger care_recipients_audit
    after insert or update or delete on public.care_recipients
    for each row execute function public.record_audit();

create trigger group_members_audit
    after insert or update or delete on public.group_members
    for each row execute function public.record_audit();

notify pgrst, 'reload schema';
