-- Med List (Aging) — providers as a first-class synced record (plan82 slice C).
--
-- One row per doctor, specialist, dentist, pharmacy or therapist. Same shape
-- as `emergency_contacts` (0002), with the extra columns a paper list has:
-- specialty, address, a patient-portal bookmark, notes, and whether this row
-- is a pharmacy rather than a prescriber.

create table public.providers (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    name              text not null,
    specialty         text not null default '',
    phone             text not null default '',
    address           text not null default '',
    -- A bookmark to the patient portal, nothing more. Never a username or
    -- password: that is the password vault, and it is refused (Appendix B).
    portal_url        text not null default '',
    notes             text not null default '',
    is_pharmacy       boolean not null default false,
    created_by        uuid references public.profiles(id) on delete set null,
    created_by_name   text not null default '',
    updated_by        uuid references public.profiles(id) on delete set null,
    updated_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index providers_group_idx     on public.providers(group_id);
create index providers_recipient_idx on public.providers(care_recipient_id);
create index providers_sync_idx      on public.providers(group_id, updated_at, id);

alter table public.providers enable row level security;

create trigger providers_touch
    before insert or update on public.providers
    for each row execute function public.touch_updated_at();

create policy "providers_staff_select"
    on public.providers for select
    using (public.is_group_staff(group_id));

create policy "providers_subject_self_select"
    on public.providers for select
    using (public.is_my_recipient(care_recipient_id));

create policy "providers_staff_insert"
    on public.providers for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "providers_staff_update"
    on public.providers for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

-- ============================================================
-- Additive references onto medications and visits.
--
-- The existing free-text prescriber, pharmacy and provider columns are left
-- in place: they hold real user data on shipped devices and there is no safe
-- backfill. A new record may set an id; an old one keeps displaying its text.
-- ============================================================
alter table public.medications
    add column provider_id uuid references public.providers(id) on delete set null,
    add column pharmacy_id uuid references public.providers(id) on delete set null;

alter table public.visits
    add column provider_id uuid references public.providers(id) on delete set null;

create index medications_provider_idx on public.medications(provider_id) where provider_id is not null;
create index medications_pharmacy_idx on public.medications(pharmacy_id) where pharmacy_id is not null;
create index visits_provider_id_idx   on public.visits(provider_id) where provider_id is not null;

notify pgrst, 'reload schema';
