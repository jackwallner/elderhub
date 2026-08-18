-- Med List (Aging) — the proof-of-life check-in.
--
-- Product framing, which the schema is built to keep honest: this is a
-- notification that a person pressed a button, or did not. It is not an
-- emergency detection system, it does not summon help, and nothing here may be
-- described to the user in those terms. See docs/architecture.md I6.
--
-- Write authorization is keyed off care_recipients.linked_user_id, never off
-- role. That is what lets the same account press their own button as a subject
-- in one group and press Dad's on his behalf as a caregiver in another.
--
-- There is deliberately no billing check anywhere on this path (I2). The
-- parent was told to press this button; a paywall must be structurally
-- impossible here, not merely absent from the UI.

-- ============================================================
-- Check-ins
-- ============================================================
create table public.check_ins (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    source            text not null check (source in ('self', 'caregiver_manual')),
    pressed_by        uuid references public.profiles(id) on delete set null,
    pressed_by_name   text not null default '',
    -- Set on the device. A check-in pressed offline and synced hours later is
    -- still a check-in from when it was pressed, so this is client-supplied and
    -- distinct from created_at.
    pressed_at        timestamptz not null default now(),
    note              text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now()
);

create index check_ins_recipient_idx on public.check_ins(care_recipient_id, pressed_at desc);
create index check_ins_group_idx     on public.check_ins(group_id);
create index check_ins_sync_idx      on public.check_ins(group_id, updated_at, id);

alter table public.check_ins enable row level security;

create trigger check_ins_touch
    before insert or update on public.check_ins
    for each row execute function public.touch_updated_at();

create policy "check_ins_staff_select"
    on public.check_ins for select
    using (public.is_group_staff(group_id));

create policy "check_ins_subject_self_select"
    on public.check_ins for select
    using (public.is_my_recipient(care_recipient_id));

create policy "check_ins_self_insert"
    on public.check_ins for insert
    with check (
        source = 'self'
        and pressed_by = (select auth.uid())
        and public.is_my_recipient(care_recipient_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "check_ins_staff_manual_insert"
    on public.check_ins for insert
    with check (
        source = 'caregiver_manual'
        and pressed_by = (select auth.uid())
        and public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

-- No update or delete policy. A check-in is a historical fact.

-- Keep the denormalized pointer on the recipient current, so the escalation
-- job and the family's home screen never have to scan the log.
create or replace function public.touch_last_check_in()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    update public.care_recipients
       set last_check_in_at = greatest(coalesce(last_check_in_at, new.pressed_at), new.pressed_at)
     where id = new.care_recipient_id;
    return new;
end;
$$;

create trigger check_ins_update_recipient
    after insert on public.check_ins
    for each row execute function public.touch_last_check_in();

-- ============================================================
-- Check-in settings — one row per recipient, opt-in.
--
-- The window is stored as minutes from midnight plus an IANA time zone, the
-- same convention as Medication.scheduleMinutes, so it survives travel and DST
-- rather than drifting like a stored absolute time would.
-- ============================================================
create table public.check_in_settings (
    care_recipient_id   uuid primary key references public.care_recipients(id) on delete cascade,
    group_id            uuid not null references public.groups(id) on delete cascade,
    enabled             boolean not null default false,
    -- Default window 08:00 to 20:00 local.
    window_start_minute int not null default 480  check (window_start_minute between 0 and 1439),
    window_end_minute   int not null default 1200 check (window_end_minute   between 0 and 1439),
    grace_minutes       int not null default 60   check (grace_minutes between 0 and 720),
    timezone            text not null default 'UTC',
    -- Guards against sending the family the same notice repeatedly; the cron
    -- job runs every 15 minutes but must escalate at most once per local day.
    last_escalated_on   date,
    updated_at          timestamptz not null default now(),
    constraint check_in_window_ordered check (window_end_minute > window_start_minute)
);

create index check_in_settings_group_idx on public.check_in_settings(group_id);
create index check_in_settings_enabled_idx on public.check_in_settings(enabled) where enabled;

alter table public.check_in_settings enable row level security;

create trigger check_in_settings_touch
    before insert or update on public.check_in_settings
    for each row execute function public.touch_updated_at();

create policy "check_in_settings_staff_select"
    on public.check_in_settings for select
    using (public.is_group_staff(group_id));

-- The subject must be able to read their own window: their device schedules the
-- local reminder from it.
create policy "check_in_settings_subject_self_select"
    on public.check_in_settings for select
    using (public.is_my_recipient(care_recipient_id));

create policy "check_in_settings_staff_insert"
    on public.check_in_settings for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "check_in_settings_staff_update"
    on public.check_in_settings for update
    using (public.is_group_staff(group_id))
    with check (public.is_group_staff(group_id));

-- ============================================================
-- Escalation query, used by the scheduled job (0006).
--
-- Runs as the caller; the cron job invokes it with the service role, which is
-- not subject to RLS. Returns one row per recipient whose window plus grace has
-- passed today with no check-in and no escalation already sent today.
-- ============================================================
create or replace function public.recipients_due_for_escalation()
returns table (
    care_recipient_id uuid,
    group_id          uuid,
    recipient_name    text,
    local_date        date
)
language sql stable security definer set search_path = public
as $$
    select
        s.care_recipient_id,
        s.group_id,
        cr.name,
        (now() at time zone s.timezone)::date as local_date
    from public.check_in_settings s
    join public.care_recipients cr on cr.id = s.care_recipient_id
    where s.enabled
      and cr.deleted_at is null
      -- Local wall-clock is past the end of the window plus grace.
      and extract(epoch from (now() at time zone s.timezone)::time) / 60
          > (s.window_end_minute + s.grace_minutes)
      -- Nothing already sent for this local day.
      and (s.last_escalated_on is distinct from (now() at time zone s.timezone)::date)
      -- No check-in since the start of the local day.
      and not exists (
          select 1 from public.check_ins ci
          where ci.care_recipient_id = s.care_recipient_id
            and (ci.pressed_at at time zone s.timezone)::date
                = (now() at time zone s.timezone)::date
      );
$$;

notify pgrst, 'reload schema';
