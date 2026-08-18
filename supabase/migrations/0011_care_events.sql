-- Med List (Aging) — incident / symptom log (plan82 slice D).
--
-- One typed note entity for falls, ER visits, hospital stays, symptoms, mood,
-- appetite, sleep and pain: the rest of the care-journal ask, in one table
-- instead of eight. Modeled on `vital_readings` (0002) for shape, and on
-- `dose_logs` (0002) for `recorded_by`: "Sarah logged a fall on Tuesday" is
-- the sentence this table exists to answer.
--
-- I6: this table only ever holds what a human typed after the fact. Nothing
-- here escalates, notifies, or infers anything from a row landing in it.

create table public.care_events (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    kind              text not null check (kind in (
                          'fall', 'erVisit', 'hospitalStay', 'symptom',
                          'mood', 'appetite', 'sleep', 'pain', 'other')),
    occurred_at       timestamptz not null default now(),
    -- 0 means unset, not that severity was recorded as zero.
    severity          int not null default 0,
    note              text not null default '',
    recorded_by       uuid references public.profiles(id) on delete set null,
    recorded_by_name  text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index care_events_group_idx     on public.care_events(group_id);
create index care_events_recipient_idx on public.care_events(care_recipient_id, occurred_at desc);
create index care_events_sync_idx      on public.care_events(group_id, updated_at, id);

alter table public.care_events enable row level security;

create trigger care_events_touch
    before insert or update on public.care_events
    for each row execute function public.touch_updated_at();

create policy "care_events_staff_select"
    on public.care_events for select
    using (public.is_group_staff(group_id));

create policy "care_events_subject_self_select"
    on public.care_events for select
    using (public.is_my_recipient(care_recipient_id));

create policy "care_events_staff_insert"
    on public.care_events for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "care_events_staff_update"
    on public.care_events for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

notify pgrst, 'reload schema';
