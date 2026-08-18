-- Med List (Aging) — care events RLS boundary tests (plan82 slice D, migration 0011).
--
-- Column-level defaults are exercised in the app's own tests; this file is
-- about the security boundary: an anonymous caller sees nothing, and a
-- non-member cannot read another group's care events, matching
-- providers_test.sql's shape for the other leaf tables added post-launch.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _ce (k text primary key, v uuid);
grant select on _ce to authenticated;

-- ============================================================
-- Fixture
--   Group 1 "Wallner"     : Sarah owner, recipient Mom, a logged fall
--   Group 2 "Other family": Stranger owner, recipient Someone, a logged fall
-- ============================================================
insert into _ce (k, v) values
    ('sarah',    public.make_user('Sarah')),
    ('stranger', public.make_user('Stranger'));

insert into _ce (k, v) values ('g1', gen_random_uuid()), ('g2', gen_random_uuid());

insert into public.groups (id, name, created_by)
values ((select v from _ce where k = 'g1'), 'Wallner',      (select v from _ce where k = 'sarah')),
       ((select v from _ce where k = 'g2'), 'Other family', (select v from _ce where k = 'stranger'));

insert into public.group_members (group_id, user_id, role) values
    ((select v from _ce where k = 'g1'), (select v from _ce where k = 'sarah'),    'owner'),
    ((select v from _ce where k = 'g2'), (select v from _ce where k = 'stranger'), 'owner');

insert into public.care_recipients (id, group_id, name) values
    (gen_random_uuid(), (select v from _ce where k = 'g1'), 'Mom')
    returning id \gset mom_
insert into _ce (k, v) values ('r_mom', :'mom_id');

insert into public.care_recipients (id, group_id, name) values
    (gen_random_uuid(), (select v from _ce where k = 'g2'), 'Someone')
    returning id \gset other_
insert into _ce (k, v) values ('r_other', :'other_id');

insert into public.care_events (
    id, group_id, care_recipient_id, kind, severity, note, recorded_by, recorded_by_name
) values (
    gen_random_uuid(), (select v from _ce where k = 'g1'), (select v from _ce where k = 'r_mom'),
    'fall', 2, 'Slipped getting out of the chair', (select v from _ce where k = 'sarah'), 'Sarah'
) returning id \gset e1_
insert into _ce (k, v) values ('event_mom', :'e1_id');

insert into public.care_events (
    id, group_id, care_recipient_id, kind, note, recorded_by_name
) values (
    gen_random_uuid(), (select v from _ce where k = 'g2'), (select v from _ce where k = 'r_other'),
    'symptom', 'Headache', 'Stranger'
) returning id \gset e2_
insert into _ce (k, v) values ('event_other', :'e2_id');

select public.ok(
    (select kind = 'fall' and recorded_by_name = 'Sarah' and severity = 2
       from public.care_events where id = (select v from _ce where k = 'event_mom')),
    'the untracked defaults (severity, recorded_by_name) are what the client relies on');

select public.throws(
    format('insert into public.care_events (group_id, care_recipient_id, kind, note)
            values (%L, %L, ''not_a_real_kind'', ''x'')',
           (select v from _ce where k = 'g1'), (select v from _ce where k = 'r_mom')),
    'an unrecognized kind is rejected at the database, matching the client fallback to .other');

-- ============================================================
set role authenticated;
-- ============================================================

\echo ''
\echo '-- owner (Sarah) --'
select public.act_as((select v from _ce where k = 'sarah'));

select public.ok(
    public.rows_visible('select 1 from public.care_events') = 1,
    'a group member sees only their own group''s care events');

select public.ok(
    public.rows_visible(format('select 1 from public.care_events where id = %L',
                               (select v from _ce where k = 'event_other'))) = 0,
    'a group member cannot read another group''s care event by id');

update public.care_events set note = 'Slipped, no injury, watched for the rest of the evening'
 where id = (select v from _ce where k = 'event_mom');
select public.ok(
    (select note = 'Slipped, no injury, watched for the rest of the evening' from public.care_events
      where id = (select v from _ce where k = 'event_mom')),
    'group staff can edit a care event they own');

select public.throws(
    format('insert into public.care_events (group_id, care_recipient_id, kind, note)
            values (%L, %L, ''fall'', ''Sneaky'')',
           (select v from _ce where k = 'g1'), (select v from _ce where k = 'r_other')),
    'staff cannot attach a care event to another group''s recipient');

select public.throws(
    format('insert into public.care_events (group_id, care_recipient_id, kind, note)
            values (%L, %L, ''fall'', ''Sneaky'')',
           (select v from _ce where k = 'g2'), (select v from _ce where k = 'r_other')),
    'staff cannot write into a group they do not belong to');

\echo ''
\echo '-- outsider (Stranger, member of group 2) --'
select public.act_as((select v from _ce where k = 'stranger'));

select public.ok(
    public.rows_visible('select 1 from public.care_events') = 1,
    'a non-member of group 1 sees none of the Wallners'' care events');

select public.ok(
    public.rows_visible(format('select 1 from public.care_events where id = %L',
                               (select v from _ce where k = 'event_mom'))) = 0,
    'a non-member cannot read another group''s care event by id');

\echo ''
\echo '-- signed out --'
select public.act_as(null);

select public.ok(
    public.rows_visible('select 1 from public.care_events') = 0,
    'anonymous access is blocked: a signed-out caller sees no care events');

select public.throws(
    format('insert into public.care_events (group_id, care_recipient_id, kind, note)
            values (%L, %L, ''fall'', ''Sneaky'')',
           (select v from _ce where k = 'g1'), (select v from _ce where k = 'r_mom')),
    'anonymous access is blocked: a signed-out caller cannot insert a care event');

reset role;

\echo ''
\echo 'care_events: all assertions passed'
