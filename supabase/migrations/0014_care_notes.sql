-- Med List (Aging) — free-form notes kept against one recipient.
--
-- The table that exists because no schema can anticipate what a family needs
-- written down about a parent: the gate code, the policy number, which option
-- to press on the pharmacy line, what to ask the neurologist next time. Every
-- attempt to model those as columns produces a form most people leave empty.
--
-- Shape and RLS follow `care_tasks` (0012). Two deliberate differences:
--
--   * Both text columns are nullable-free but may be empty. A note with a body
--     and no title is ordinary; the client falls back to the first line.
--   * There is no `assignee`, no `due_at` and no completion. This is storage,
--     not work: nothing here sorts by urgency and nothing here notifies (I6).
--
-- Not a credential vault. The body is ordinary text under the same RLS as the
-- medication list, with no client-side encryption, and the app's copy never
-- invites passwords into it. If that ever changes, this table's `body` becomes
-- ciphertext and the key never touches Postgres.

create table public.care_notes (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    title             text not null default '',
    body              text not null default '',
    -- Two notes out of twenty matter more than the rest. This is the whole of
    -- the organisation this screen offers, on purpose.
    is_pinned         boolean not null default false,
    created_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index care_notes_group_idx on public.care_notes(group_id);
-- The list's own query: this recipient's live notes, pinned first.
create index care_notes_live_idx  on public.care_notes(care_recipient_id, is_pinned, updated_at desc)
    where deleted_at is null;
create index care_notes_sync_idx  on public.care_notes(group_id, updated_at, id);

alter table public.care_notes enable row level security;

create trigger care_notes_touch
    before insert or update on public.care_notes
    for each row execute function public.touch_updated_at();

create policy "care_notes_staff_select"
    on public.care_notes for select
    using (public.is_group_staff(group_id));

-- Deliberately no subject-select policy, unlike `care_tasks`.
--
-- A task list is written *for* the recipient and reads fine to them. A notes
-- pile is written *about* them by the family, in the family's own shorthand,
-- and "Mom repeats herself about Dad, do not correct her" is exactly the kind
-- of line that ends up in it. Staff-only is the honest default; a family that
-- wants the recipient to read something has every other screen to put it on.

create policy "care_notes_staff_insert"
    on public.care_notes for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "care_notes_staff_update"
    on public.care_notes for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

notify pgrst, 'reload schema';
