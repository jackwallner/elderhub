-- Med List (Aging) — RLS boundary tests.
--
-- These are the tests that matter most in the whole repo. The subject's reduced
-- view is a security boundary, not a UI state (architecture.md I4): if any of
-- these go green in the app but red here, a scripted client can read a family's
-- medical records.
--
-- Fixtures are inserted as the superuser on purpose, so these tests exercise
-- the policies and not the RPCs. The RPCs get their own file.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _t (k text primary key, v uuid);
grant select on _t to authenticated;

-- ============================================================
-- Fixture
--   Group 1 "Wallner"     : Sarah owner, Mike caregiver, Mom subject
--                           recipients: Mom (linked), Dad (no account)
--   Group 2 "Other family": Stranger owner, recipient Someone
-- ============================================================
insert into _t (k, v) values
    ('sarah',    public.make_user('Sarah')),
    ('mike',     public.make_user('Mike')),
    ('mom',      public.make_user('Mom')),
    ('stranger', public.make_user('Stranger'));

insert into _t (k, v) values ('g1', gen_random_uuid()), ('g2', gen_random_uuid());

insert into public.groups (id, name, created_by)
values ((select v from _t where k = 'g1'), 'Wallner',      (select v from _t where k = 'sarah')),
       ((select v from _t where k = 'g2'), 'Other family', (select v from _t where k = 'stranger'));

insert into public.group_members (group_id, user_id, role) values
    ((select v from _t where k = 'g1'), (select v from _t where k = 'sarah'),    'owner'),
    ((select v from _t where k = 'g1'), (select v from _t where k = 'mike'),     'caregiver'),
    ((select v from _t where k = 'g1'), (select v from _t where k = 'mom'),      'subject'),
    ((select v from _t where k = 'g2'), (select v from _t where k = 'stranger'), 'owner');

insert into _t (k, v) values
    ('r_mom', gen_random_uuid()),
    ('r_dad', gen_random_uuid()),
    ('r_other', gen_random_uuid());

insert into public.care_recipients (id, group_id, linked_user_id, name) values
    ((select v from _t where k = 'r_mom'),   (select v from _t where k = 'g1'),
     (select v from _t where k = 'mom'), 'Mom'),
    ((select v from _t where k = 'r_dad'),   (select v from _t where k = 'g1'), null, 'Dad'),
    ((select v from _t where k = 'r_other'), (select v from _t where k = 'g2'), null, 'Someone');

insert into _t (k, v) values ('m_mom', gen_random_uuid()), ('m_dad', gen_random_uuid());

insert into public.medications (id, group_id, care_recipient_id, name) values
    ((select v from _t where k = 'm_mom'), (select v from _t where k = 'g1'),
     (select v from _t where k = 'r_mom'), 'Lisinopril'),
    ((select v from _t where k = 'm_dad'), (select v from _t where k = 'g1'),
     (select v from _t where k = 'r_dad'), 'Donepezil');

insert into public.check_in_settings (care_recipient_id, group_id, enabled)
values ((select v from _t where k = 'r_mom'), (select v from _t where k = 'g1'), true);

-- ============================================================
set role authenticated;
-- ============================================================

\echo ''
\echo '-- caregiver (Mike) --'
select public.act_as((select v from _t where k = 'mike'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 2,
    'caregiver sees both recipients in their group and none from the other');

select public.ok(
    public.rows_visible('select 1 from public.medications') = 2,
    'caregiver sees every medication in their group');

select public.throws(
    format('insert into public.medications (group_id, care_recipient_id, name)
            values (%L, %L, ''Sneaky'')',
           (select v from _t where k = 'g1'), (select v from _t where k = 'r_other')),
    'caregiver cannot attach a medication to a recipient in another group');

select public.throws(
    format('insert into public.medications (group_id, care_recipient_id, name)
            values (%L, %L, ''Sneaky'')',
           (select v from _t where k = 'g2'), (select v from _t where k = 'r_other')),
    'caregiver cannot write into a group they do not belong to');

-- group_members has no update policy at all, so this silently affects 0 rows
-- rather than raising. That is the privilege-escalation case.
update public.group_members set role = 'owner'
 where user_id = (select v from _t where k = 'mike');
select public.ok(
    (select role from public.group_members
      where user_id = (select v from _t where k = 'mike')) = 'caregiver',
    'caregiver cannot promote themselves to owner by direct write');

select public.throws(
    format('insert into public.group_members (group_id, user_id, role)
            values (%L, %L, ''owner'')',
           (select v from _t where k = 'g1'), (select v from _t where k = 'stranger')),
    'caregiver cannot add a member by direct insert');

select public.throws(
    format('insert into public.group_billing (group_id, entitlement)
            values (%L, ''plus'')', (select v from _t where k = 'g1')),
    'a member cannot grant their own group Plus');

\echo ''
\echo '-- subject (Mom) --'
select public.act_as((select v from _t where k = 'mom'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 1,
    'subject sees only their own recipient row, not Dad');

select public.ok(
    public.rows_visible(format('select 1 from public.care_recipients where id = %L',
                               (select v from _t where k = 'r_mom'))) = 1,
    'subject can see their own recipient row');

select public.ok(
    public.rows_visible('select 1 from public.medications') = 1,
    'subject sees only their own medications, not Dad''s');

select public.ok(
    public.rows_visible(format('select 1 from public.medications where id = %L',
                               (select v from _t where k = 'm_dad'))) = 0,
    'subject cannot read another recipient''s medication by id');

select public.throws(
    format('insert into public.medications (group_id, care_recipient_id, name)
            values (%L, %L, ''Self-prescribed'')',
           (select v from _t where k = 'g1'), (select v from _t where k = 'r_mom')),
    'subject cannot add a medication, even to their own record');

-- architecture.md D32: the subject CAN log their own doses. This is the one
-- deliberate widening of the reduced surface.
insert into public.dose_logs (group_id, medication_id, scheduled_at, recorded_by, recorded_by_name)
values ((select v from _t where k = 'g1'), (select v from _t where k = 'm_mom'),
        now(), (select v from _t where k = 'mom'), 'Mom');
select public.ok(
    public.rows_visible('select 1 from public.dose_logs') = 1,
    'subject can log a dose for their own medication (D32)');

select public.throws(
    format('insert into public.dose_logs (group_id, medication_id, scheduled_at, recorded_by)
            values (%L, %L, now(), %L)',
           (select v from _t where k = 'g1'), (select v from _t where k = 'm_dad'),
           (select v from _t where k = 'mom')),
    'subject cannot log a dose against another recipient''s medication');

select public.throws(
    format('insert into public.dose_logs (group_id, medication_id, scheduled_at, recorded_by)
            values (%L, %L, now(), %L)',
           (select v from _t where k = 'g1'), (select v from _t where k = 'm_mom'),
           (select v from _t where k = 'sarah')),
    'subject cannot log a dose attributed to somebody else');

-- Check-ins: authorization is keyed off linked_user_id, never off role.
insert into public.check_ins (group_id, care_recipient_id, source, pressed_by, pressed_by_name)
values ((select v from _t where k = 'g1'), (select v from _t where k = 'r_mom'),
        'self', (select v from _t where k = 'mom'), 'Mom');
select public.ok(
    (select last_check_in_at is not null from public.care_recipients
      where id = (select v from _t where k = 'r_mom')),
    'a self check-in updates the recipient''s last_check_in_at');

select public.throws(
    format('insert into public.check_ins (group_id, care_recipient_id, source, pressed_by)
            values (%L, %L, ''self'', %L)',
           (select v from _t where k = 'g1'), (select v from _t where k = 'r_dad'),
           (select v from _t where k = 'mom')),
    'subject cannot press the button on another recipient''s behalf');

select public.throws(
    format('insert into public.check_ins (group_id, care_recipient_id, source, pressed_by)
            values (%L, %L, ''caregiver_manual'', %L)',
           (select v from _t where k = 'g1'), (select v from _t where k = 'r_mom'),
           (select v from _t where k = 'mom')),
    'subject cannot record a caregiver_manual check-in');

select public.ok(
    public.rows_visible('select 1 from public.check_in_settings') = 1,
    'subject can read their own check-in window, which their device schedules from');

select public.ok(
    public.rows_visible('select 1 from public.audit_log') = 0,
    'subject cannot read the audit log');

\echo ''
\echo '-- outsider (Stranger) --'
select public.act_as((select v from _t where k = 'stranger'));

select public.ok(
    public.rows_visible('select 1 from public.medications') = 0,
    'a non-member sees none of the family''s medications');

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 1,
    'a non-member sees only their own group''s recipients');

select public.ok(
    public.rows_visible('select 1 from public.check_ins') = 0,
    'a non-member sees no check-ins');

select public.ok(
    public.rows_visible('select 1 from public.groups') = 1,
    'a non-member sees only their own group');

\echo ''
\echo '-- signed out --'
select public.act_as(null);

select public.ok(
    public.rows_visible('select 1 from public.medications') = 0,
    'an unauthenticated caller sees nothing');

\echo ''
\echo '-- owner (Sarah) --'
select public.act_as((select v from _t where k = 'sarah'));

select public.ok(
    public.rows_visible('select 1 from public.dose_logs') = 1,
    'owner sees the dose the subject logged');

select public.ok(
    (select recorded_by_name from public.dose_logs limit 1) = 'Mom',
    'the log says who logged it');

select public.ok(
    public.rows_visible('select 1 from public.audit_log') > 0,
    'staff can read the audit log');

select public.ok(
    public.rows_visible('select 1 from public.profiles') = 3,
    'a member sees the profiles of their group and nobody else''s');

reset role;

\echo ''
\echo 'RLS: all assertions passed'
