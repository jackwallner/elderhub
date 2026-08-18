-- Med List (Aging) — refill tracking columns (plan82 slice B, migration 0009).
--
-- Column-level only. RLS on `medications` itself is exercised in rls_test.sql;
-- this just checks the new columns default the way the client relies on (0 on
-- hand means "not tracked", not "empty") and that an ordinary staff write can
-- set them.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _rf (k text primary key, v uuid);
grant select, insert on _rf to authenticated;

insert into _rf (k, v) values ('owner', public.make_user('Refill Owner'));

insert into public.groups (id, name, created_by)
values (gen_random_uuid(), 'Refill Family', (select v from _rf where k = 'owner'))
returning id \gset g_
insert into _rf (k, v) values ('group', :'g_id');

insert into public.group_members (group_id, user_id, role)
values ((select v from _rf where k = 'group'), (select v from _rf where k = 'owner'), 'owner');

insert into public.care_recipients (id, group_id, name)
values (gen_random_uuid(), (select v from _rf where k = 'group'), 'Recipient')
returning id \gset r_
insert into _rf (k, v) values ('recipient', :'r_id');

insert into public.medications (id, group_id, care_recipient_id, name)
values (gen_random_uuid(), (select v from _rf where k = 'group'),
        (select v from _rf where k = 'recipient'), 'Metformin')
returning id \gset m_
insert into _rf (k, v) values ('med', :'m_id');

select public.ok(
    (select quantity_remaining = 0 and units_per_dose = 1 and refill_threshold_days = 7
       and last_filled_at is null
       from public.medications where id = (select v from _rf where k = 'med')),
    '0 on hand, 1 per dose, 7-day warning: the untracked defaults the client relies on');

-- ============================================================
set role authenticated;
-- ============================================================

select public.act_as((select v from _rf where k = 'owner'));

update public.medications
   set quantity_remaining = 30, units_per_dose = 2, refill_threshold_days = 5,
       last_filled_at = current_date
 where id = (select v from _rf where k = 'med');

select public.ok(
    (select quantity_remaining = 30 and units_per_dose = 2 and refill_threshold_days = 5
       and last_filled_at = current_date
       from public.medications where id = (select v from _rf where k = 'med')),
    'group staff can turn on refill tracking for a medication they own');

reset role;
