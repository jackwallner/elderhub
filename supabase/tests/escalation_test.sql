-- Migration 0007: notices, attestation, and the escalation queue.
--
-- The pg_cron schedule itself is not exercised here (the local cluster has no
-- pg_cron). What is exercised is everything the scheduled call actually does,
-- which is where the bugs would be: who gets told, who does not, and whether a
-- 15-minute cadence can tell the same family the same thing four times an hour.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

-- Plain tables, granted to `authenticated`, matching lifecycle_test.sql. A temp
-- table is owned by the superuser session and is unreadable once the test
-- assumes the `authenticated` role.
create table _e (k text primary key, v uuid);
create table _ec (k text primary key, v text);
grant select, insert, update on _e, _ec to authenticated;

insert into _e (k, v) values
    ('owner',    public.make_user('Anna')),
    ('cg',       public.make_user('Ben')),
    ('mom',      public.make_user('Mom')),
    ('stranger', public.make_user('Stranger'));

set role authenticated;

-- ============================================================
\echo ''
\echo '-- setup --'
select public.act_as((select v from _e where k = 'owner'));
insert into _e (k, v) select 'g', public.create_group('Family');

insert into public.care_recipients (group_id, name, relationship)
values ((select v from _e where k = 'g'), 'Mom', 'Mom');
insert into _e (k, v)
select 'r_mom', id from public.care_recipients where name = 'Mom';

insert into _ec (k, v)
select 'cg_code', public.generate_invite_code((select v from _e where k = 'g')::text, 'caregiver');
insert into _ec (k, v)
select 'mom_code', public.generate_invite_code(
    (select v from _e where k = 'g')::text, 'subject',
    (select v from _e where k = 'r_mom')::text);

select public.act_as((select v from _e where k = 'cg'));
select public.ok((select ok from public.accept_invite((select v from _ec where k = 'cg_code'))),
                 'Ben joins as a caregiver');

select public.act_as((select v from _e where k = 'mom'));
select public.ok((select ok from public.accept_invite((select v from _ec where k = 'mom_code'))),
                 'Mom joins as the subject and is linked to her own record');

-- ============================================================
\echo ''
\echo '-- surrogate attestation is stamped by the server, not the client --'
select public.act_as((select v from _e where k = 'owner'));

insert into public.care_recipients (group_id, name, surrogate_attested_at, surrogate_attested_by)
values ((select v from _e where k = 'g'), 'Dad', now(),
        -- A client claiming someone else made the attestation.
        (select v from _e where k = 'cg'));

select public.ok(
    (select surrogate_attested_by from public.care_recipients where name = 'Dad')
        = (select v from _e where k = 'owner'),
    'the attester is whoever was authenticated, not whoever the client named');

update public.care_recipients set surrogate_attested_at = null where name = 'Dad';
select public.ok(
    (select surrogate_attested_at is not null from public.care_recipients where name = 'Dad'),
    'an attestation cannot be un-recorded by a later write');

-- ============================================================
\echo ''
\echo '-- the escalation queue --'
reset role;

-- A window that ended hours ago, in a fixed zone so the assertion does not
-- depend on when the suite happens to run.
insert into public.check_in_settings (
    care_recipient_id, group_id, enabled,
    window_start_minute, window_end_minute, grace_minutes, timezone
)
values ((select v from _e where k = 'r_mom'), (select v from _e where k = 'g'),
        true, 0, 1, 0, 'UTC');

select public.ok(
    (select count(*) from public.recipients_due_for_escalation()) = 1,
    'a recipient whose window has passed with no check-in is due');

select public.ok(public.queue_check_in_notices() = 1, 'one notice is queued');

select public.ok(
    (select body from public.group_notices where kind = 'no_check_in')
        = 'Mom has not checked in today.',
    'the notice states a fact and does not assess anyone');

-- The cron job fires every 15 minutes. Running it again must be silent.
select public.ok(public.queue_check_in_notices() = 0,
                 'a second run the same day queues nothing');

select public.ok(
    (select count(*) from public.pending_notices_with_targets()) = 0,
    'nobody is pushed until they have an APNs token');

update public.profiles set apns_token = 'token-anna' where id = (select v from _e where k = 'owner');
update public.profiles set apns_token = 'token-ben'  where id = (select v from _e where k = 'cg');
update public.profiles set apns_token = 'token-mom'  where id = (select v from _e where k = 'mom');

select public.ok(
    (select count(*) from public.pending_notices_with_targets()) = 2,
    'both caregivers are told, and the subject is not');

-- ============================================================
\echo ''
\echo '-- a check-in stops the escalation --'
set role authenticated;
select public.act_as((select v from _e where k = 'mom'));
insert into public.check_ins (group_id, care_recipient_id, source, pressed_by, pressed_at)
values ((select v from _e where k = 'g'), (select v from _e where k = 'r_mom'),
        'self', (select v from _e where k = 'mom'), now());

reset role;
update public.check_in_settings set last_escalated_on = null
 where care_recipient_id = (select v from _e where k = 'r_mom');

select public.ok(
    (select count(*) from public.recipients_due_for_escalation()) = 0,
    'a press today clears the escalation, even with the stamp reset');

select public.ok(
    (select last_check_in_at is not null from public.care_recipients
      where id = (select v from _e where k = 'r_mom')),
    'the denormalized pointer on the recipient is kept current by the trigger');

-- ============================================================
\echo ''
\echo '-- leaving announces itself --'
set role authenticated;
select public.act_as((select v from _e where k = 'mom'));
select public.leave_group((select v from _e where k = 'g')::text);

reset role;
select public.ok(
    (select count(*) from public.group_notices where kind = 'subject_left') = 1,
    'a subject leaving queues a notice to the group (D27)');

select public.ok(
    (select exclude_user from public.group_notices where kind = 'subject_left')
        = (select v from _e where k = 'mom'),
    'the person who left is not sent their own announcement');

select public.ok(
    (select linked_user_id is null from public.care_recipients
      where id = (select v from _e where k = 'r_mom')),
    'leaving unlinks the account but leaves the medical record standing (I5)');

-- ============================================================
\echo ''
\echo '-- a stranger sees none of it --'
set role authenticated;
select public.act_as((select v from _e where k = 'stranger'));
select public.ok(public.rows_visible('select 1 from public.group_notices') = 0,
                 'notices are invisible outside the group');
select public.throws(
    'select * from public.pending_notices_with_targets()',
    'a client cannot enumerate the family''s device tokens');
select public.throws(
    'select public.queue_check_in_notices()',
    'a client cannot queue notices of its own');

\echo ''
\echo 'Escalation: all assertions passed'
