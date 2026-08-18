-- Elderhub (Aging) — the bills the family looks after for one recipient.
--
-- The care-home invoice, the electricity, the Medicare supplement, the property
-- tax. This lived in `care_notes` until now, and a note cannot answer the two
-- questions a family actually asks each other: what is due, and did anyone pay
-- it. Those need an amount, a date, a recurrence and a paid-by, which is a
-- table.
--
-- Shape and RLS follow `care_notes` (0014) and `care_tasks` (0012). Paying is
-- recorded, never performed: `paid_at` is a human saying they paid it, exactly
-- as `dose_logs.status` is a human saying a tablet was swallowed. Nothing here
-- talks to a bank, and nothing in this schema or the app chases a payment.
--
-- Not a credential store, and this table is where that rule earns its keep: a
-- screen called Bills is precisely where a family would otherwise write the
-- online banking login. There is no account-number column, no card column and
-- no login column, the client's editor says so at the point of entry, and
-- `notes` is ordinary text under the same RLS as the medication list. If that
-- ever changes, `notes` becomes ciphertext and the key never touches Postgres.

create table public.bills (
    id                uuid primary key default gen_random_uuid(),
    group_id          uuid not null references public.groups(id) on delete cascade,
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    payee             text not null default '',
    -- One currency, the device's. Not converted and not summed across
    -- currencies anywhere: this is an aid to reading a list somebody typed.
    amount            double precision not null default 0,
    notes             text not null default '',
    -- text + check rather than a Postgres enum (D6): `ALTER TYPE ADD VALUE`
    -- has a transaction-boundary trap in CLI migrations.
    category          text not null default 'other'
                      check (category in ('care','housing','utilities','insurance','medical','other')),
    recurrence        text not null default 'monthly'
                      check (recurrence in ('never','weekly','monthly','quarterly','halfYearly','yearly')),
    -- Nullable: "we owe them something at some point" is an ordinary state for
    -- a bill just written down, and a bill with no date never reads as late.
    due_at            timestamptz,
    -- Handled by the bank already. Worth having written down, never a job
    -- anyone is behind on.
    is_auto_pay       boolean not null default false,
    paid_at           timestamptz,
    paid_by_name      text not null default '',
    created_by_name   text not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

create index bills_group_idx on public.bills(group_id);
-- The list's own query: this recipient's open bills, soonest first.
create index bills_open_idx  on public.bills(care_recipient_id, due_at)
    where deleted_at is null and paid_at is null;
create index bills_sync_idx  on public.bills(group_id, updated_at, id);

alter table public.bills enable row level security;

create trigger bills_touch
    before insert or update on public.bills
    for each row execute function public.touch_updated_at();

create policy "bills_staff_select"
    on public.bills for select
    using (public.is_group_staff(group_id));

-- Deliberately no subject-select policy, following `care_notes` rather than
-- `care_tasks`. What a family spends looking after someone is a conversation
-- that family gets to choose to have, and an itemised total of what your care
-- costs, appearing unasked on your own phone, is not a kindness. A family that
-- wants the recipient in on it has the tasks list and the notes to say so.

create policy "bills_staff_insert"
    on public.bills for insert
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

create policy "bills_staff_update"
    on public.bills for update
    using (public.is_group_staff(group_id))
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
    );

notify pgrst, 'reload schema';
