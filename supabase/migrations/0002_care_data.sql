-- Med List (Aging) — the care record: recipients, medications, dose logs,
-- visits, vitals, emergency contacts.
--
-- Two structural rules apply to every table in this file.
--
-- 1. `group_id` is denormalized onto every leaf table so a policy never has to
--    join through care_recipients per row.
-- 2. Every FK chain that could delete a row cascades from `group_id -> groups`,
--    never from an individual member's profile. Bond's 0008 deleted a partner's
--    data on account deletion because a cascade ran through a shared row; the
--    blast radius here is larger, because a recipient's medical history belongs
--    to the whole family rather than to two people.
--
-- Deletion is a tombstone (`deleted_at`), never a hard delete, so a delete on
-- one device propagates to the others. There are deliberately no DELETE
-- policies on these tables.

-- ============================================================
-- Care recipients — the cloud counterpart of the local `Person` model.
--
-- Separate from profiles, optionally linked. Dad has dementia and no phone and
-- must be fully trackable with no auth identity at all; Mom has an account and
-- presses the check-in button. One table, optionally linked, avoids two
-- divergent representations of "a person being cared for".
-- ============================================================
create table public.care_recipients (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    linked_user_id    uuid references public.profiles(id) on delete set null,
    name              text not null,
    relationship      text not null default '',
    birth_date        date,
    blood_type        text not null default '',
    color_index       int not null default 0,
    allergies         text[] not null default '{}',
    conditions        text[] not null default '{}',
    notes             text not null default '',
    -- Set by a caregiver adding someone who will never use the app themselves.
    -- Recorded because it is a surrogate decision, not the recipient's consent.
    surrogate_attested_by   uuid references public.profiles(id) on delete set null,
    surrogate_attested_at   timestamptz,
    last_check_in_at  timestamptz,
    created_by        uuid references public.profiles(id) on delete set null,
    created_by_name   text not null default '',
    updated_by        uuid references public.profiles(id) on delete set null,
    updated_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

-- `on delete set null` on linked_user_id is deliberate: Mom deleting her account
-- must unlink her, not delete the medication history the family depends on.

create unique index care_recipients_group_linked_user_idx
    on public.care_recipients(group_id, linked_user_id)
    where linked_user_id is not null;
create index care_recipients_group_idx on public.care_recipients(group_id);
create index care_recipients_sync_idx  on public.care_recipients(group_id, updated_at, id);

alter table public.care_recipients enable row level security;

create trigger care_recipients_touch
    before insert or update on public.care_recipients
    for each row execute function public.touch_updated_at();

-- ============================================================
-- Recipient-scoped helpers, used by every leaf table below.
-- Security definer, so leaf policies do not re-enter care_recipients' RLS.
-- ============================================================
create or replace function public.recipient_in_group(p_recipient_id uuid, p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.care_recipients
        where id = p_recipient_id and group_id = p_group_id
    );
$$;

-- "Is this recipient row me?" This is the check that makes the sandwich
-- generation work with no special-casing: it asks about a specific row, never
-- about the caller's global role.
create or replace function public.is_my_recipient(p_recipient_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.care_recipients
        where id = p_recipient_id
          and linked_user_id = (select auth.uid())
    );
$$;

grant execute on function public.recipient_in_group(uuid, uuid) to authenticated;
grant execute on function public.is_my_recipient(uuid)          to authenticated;

-- ============================================================
-- care_recipients policies
-- ============================================================
create policy "care_recipients_staff_select"
    on public.care_recipients for select
    using (public.is_group_staff(group_id));

create policy "care_recipients_subject_self_select"
    on public.care_recipients for select
    using (linked_user_id = (select auth.uid()));

create policy "care_recipients_staff_insert"
    on public.care_recipients for insert
    with check (public.is_group_staff(group_id));

create policy "care_recipients_staff_update"
    on public.care_recipients for update
    using (public.is_group_staff(group_id))
    with check (public.is_group_staff(group_id));

-- ============================================================
-- Medications
-- ============================================================
create table public.medications (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    name              text not null,
    strength          text not null default '',
    form              text not null default 'tablet',
    purpose           text not null default '',
    prescriber        text not null default '',
    pharmacy          text not null default '',
    instructions      text not null default '',
    -- Minutes from midnight, matching the local model, so a dose time survives
    -- a time-zone change.
    schedule_minutes  int[] not null default '{}',
    -- Calendar weekday numbers, 1 = Sunday. Empty means every day.
    weekdays          int[] not null default '{}',
    is_as_needed      boolean not null default false,
    is_active         boolean not null default true,
    start_date        date not null default current_date,
    end_date          date,
    -- Storage object path. Photo bytes are not stored in Postgres.
    label_photo_path  text,
    created_by        uuid references public.profiles(id) on delete set null,
    created_by_name   text not null default '',
    updated_by        uuid references public.profiles(id) on delete set null,
    updated_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index medications_group_idx     on public.medications(group_id);
create index medications_recipient_idx on public.medications(care_recipient_id);
create index medications_sync_idx      on public.medications(group_id, updated_at, id);

alter table public.medications enable row level security;

create trigger medications_touch
    before insert or update on public.medications
    for each row execute function public.touch_updated_at();

create policy "medications_staff_select"
    on public.medications for select
    using (public.is_group_staff(group_id));

create policy "medications_subject_self_select"
    on public.medications for select
    using (public.is_my_recipient(care_recipient_id));

create policy "medications_staff_insert"
    on public.medications for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "medications_staff_update"
    on public.medications for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

-- Defined here rather than with the other helpers because it reads
-- public.medications, which does not exist until the statement above.
create or replace function public.medication_is_mine(p_medication_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1
        from public.medications m
        join public.care_recipients cr on cr.id = m.care_recipient_id
        where m.id = p_medication_id
          and cr.linked_user_id = (select auth.uid())
    );
$$;

grant execute on function public.medication_is_mine(uuid) to authenticated;

-- ============================================================
-- Dose logs
--
-- Append-only event log. Two devices logging the same dose is a duplicate
-- problem, not a conflict problem, so the partial unique index below is the
-- resolution mechanism rather than any last-writer-wins rule.
--
-- The subject may log doses for their own recipient (architecture.md D32). A
-- parent who can press a proof-of-life button can tap "took my morning pills",
-- and if she cannot, the family has to phone and ask.
-- ============================================================
create table public.dose_logs (
    id               uuid primary key default gen_random_uuid(),
    group_id         uuid not null references public.groups(id) on delete cascade,
    medication_id    uuid not null references public.medications(id) on delete cascade,
    scheduled_at     timestamptz not null,
    recorded_at      timestamptz not null default now(),
    status           text not null default 'taken' check (status in ('taken', 'skipped', 'missed')),
    recorded_by      uuid references public.profiles(id) on delete set null,
    recorded_by_name text not null default '',
    note             text not null default '',
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    deleted_at       timestamptz
);

-- The de-duplication rule. Partial, so a tombstoned log does not block
-- re-logging the same dose after an undo.
create unique index dose_logs_dedupe_idx
    on public.dose_logs(medication_id, scheduled_at)
    where deleted_at is null;

create index dose_logs_group_idx  on public.dose_logs(group_id);
create index dose_logs_med_idx    on public.dose_logs(medication_id, scheduled_at desc);
create index dose_logs_sync_idx   on public.dose_logs(group_id, updated_at, id);

alter table public.dose_logs enable row level security;

create trigger dose_logs_touch
    before insert or update on public.dose_logs
    for each row execute function public.touch_updated_at();

create policy "dose_logs_staff_select"
    on public.dose_logs for select
    using (public.is_group_staff(group_id));

create policy "dose_logs_subject_self_select"
    on public.dose_logs for select
    using (public.medication_is_mine(medication_id));

create policy "dose_logs_staff_insert"
    on public.dose_logs for insert
    with check (public.is_group_staff(group_id));

create policy "dose_logs_subject_self_insert"
    on public.dose_logs for insert
    with check (
        public.medication_is_mine(medication_id)
        and recorded_by = (select auth.uid())
    );

create policy "dose_logs_staff_update"
    on public.dose_logs for update
    using (public.is_group_staff(group_id))
    with check (public.is_group_staff(group_id));

-- A subject may correct or undo a log they made themselves, nothing else.
create policy "dose_logs_subject_own_update"
    on public.dose_logs for update
    using (
        recorded_by = (select auth.uid())
        and public.medication_is_mine(medication_id)
    )
    with check (
        recorded_by = (select auth.uid())
        and public.medication_is_mine(medication_id)
    );

-- ============================================================
-- Visits
-- ============================================================
create table public.visits (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    date              timestamptz not null default now(),
    provider          text not null default '',
    specialty         text not null default '',
    reason            text not null default '',
    notes             text not null default '',
    follow_up         text not null default '',
    next_appointment  timestamptz,
    created_by        uuid references public.profiles(id) on delete set null,
    created_by_name   text not null default '',
    updated_by        uuid references public.profiles(id) on delete set null,
    updated_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index visits_group_idx     on public.visits(group_id);
create index visits_recipient_idx on public.visits(care_recipient_id, date desc);
create index visits_sync_idx      on public.visits(group_id, updated_at, id);

alter table public.visits enable row level security;

create trigger visits_touch
    before insert or update on public.visits
    for each row execute function public.touch_updated_at();

create policy "visits_staff_select"
    on public.visits for select
    using (public.is_group_staff(group_id));

create policy "visits_subject_self_select"
    on public.visits for select
    using (public.is_my_recipient(care_recipient_id));

create policy "visits_staff_insert"
    on public.visits for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "visits_staff_update"
    on public.visits for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

-- ============================================================
-- Vital readings
-- ============================================================
create table public.vital_readings (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    kind              text not null check (kind in (
                          'bloodPressure', 'weight', 'glucose',
                          'heartRate', 'temperature', 'oxygen')),
    primary_value     double precision not null,
    -- Diastolic, for blood pressure. Unused otherwise.
    secondary_value   double precision,
    recorded_at       timestamptz not null default now(),
    note              text not null default '',
    created_by        uuid references public.profiles(id) on delete set null,
    created_by_name   text not null default '',
    updated_by        uuid references public.profiles(id) on delete set null,
    updated_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index vital_readings_group_idx     on public.vital_readings(group_id);
create index vital_readings_recipient_idx on public.vital_readings(care_recipient_id, recorded_at desc);
create index vital_readings_sync_idx      on public.vital_readings(group_id, updated_at, id);

alter table public.vital_readings enable row level security;

create trigger vital_readings_touch
    before insert or update on public.vital_readings
    for each row execute function public.touch_updated_at();

create policy "vital_readings_staff_select"
    on public.vital_readings for select
    using (public.is_group_staff(group_id));

create policy "vital_readings_subject_self_select"
    on public.vital_readings for select
    using (public.is_my_recipient(care_recipient_id));

create policy "vital_readings_staff_insert"
    on public.vital_readings for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "vital_readings_staff_update"
    on public.vital_readings for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

-- ============================================================
-- Emergency contacts
-- ============================================================
create table public.emergency_contacts (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    name              text not null,
    relationship      text not null default '',
    phone             text not null default '',
    is_primary        boolean not null default false,
    created_by        uuid references public.profiles(id) on delete set null,
    created_by_name   text not null default '',
    updated_by        uuid references public.profiles(id) on delete set null,
    updated_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index emergency_contacts_group_idx     on public.emergency_contacts(group_id);
create index emergency_contacts_recipient_idx on public.emergency_contacts(care_recipient_id);
create index emergency_contacts_sync_idx      on public.emergency_contacts(group_id, updated_at, id);

alter table public.emergency_contacts enable row level security;

create trigger emergency_contacts_touch
    before insert or update on public.emergency_contacts
    for each row execute function public.touch_updated_at();

create policy "emergency_contacts_staff_select"
    on public.emergency_contacts for select
    using (public.is_group_staff(group_id));

create policy "emergency_contacts_subject_self_select"
    on public.emergency_contacts for select
    using (public.is_my_recipient(care_recipient_id));

create policy "emergency_contacts_staff_insert"
    on public.emergency_contacts for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "emergency_contacts_staff_update"
    on public.emergency_contacts for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

notify pgrst, 'reload schema';
