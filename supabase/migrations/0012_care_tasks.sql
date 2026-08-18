-- Med List (Aging) — the family's shared to-do list.
--
-- The one table that exists because the account is a family rather than a
-- person: "who is doing this, and has anyone done it yet" is the question a
-- shared spreadsheet answers badly and a text thread answers worse.
--
-- Modeled on `care_events` (0011) for shape and RLS, with two deliberate
-- differences:
--
--   * `assignee_user_id` references `profiles` but is nullable and is never
--     required, because the assignee is very often typed offline before the
--     member list has ever loaded. The name is the load-bearing field; the id
--     is an optimisation.
--   * A repeating task is completed by writing a *new* row for the next
--     occurrence, never by moving `due_at` on this one. The completed row is
--     the history the family came for.
--
-- I6: nothing here escalates or notifies. A task going overdue changes how it
-- sorts in a list a human is reading, and nothing else.

create table public.care_tasks (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    title             text not null default '',
    notes             text not null default '',
    -- Nullable on purpose. Most of what a caregiver writes down is "at some
    -- point", and a forced date turns the list into a wall of things that are
    -- technically late.
    due_at            timestamptz,
    priority          text not null default 'normal'
                          check (priority in ('low', 'normal', 'high')),
    recurrence        text not null default 'never'
                          check (recurrence in ('never', 'daily', 'weekly', 'monthly', 'yearly')),
    assignee_user_id  uuid references public.profiles(id) on delete set null,
    assignee_name     text not null default '',
    completed_at      timestamptz,
    completed_by_name text not null default '',
    created_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index care_tasks_group_idx     on public.care_tasks(group_id);
-- The list's own query: this recipient's open work, soonest first.
create index care_tasks_open_idx      on public.care_tasks(care_recipient_id, due_at)
    where completed_at is null and deleted_at is null;
create index care_tasks_sync_idx      on public.care_tasks(group_id, updated_at, id);

alter table public.care_tasks enable row level security;

create trigger care_tasks_touch
    before insert or update on public.care_tasks
    for each row execute function public.touch_updated_at();

create policy "care_tasks_staff_select"
    on public.care_tasks for select
    using (public.is_group_staff(group_id));

-- A recipient with their own account can see what the family has lined up for
-- them. They cannot write: the capability split everywhere else in this schema
-- is staff-writes / subject-reads, and a task list is not the place to break it.
create policy "care_tasks_subject_self_select"
    on public.care_tasks for select
    using (public.is_my_recipient(care_recipient_id));

create policy "care_tasks_staff_insert"
    on public.care_tasks for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "care_tasks_staff_update"
    on public.care_tasks for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

notify pgrst, 'reload schema';
