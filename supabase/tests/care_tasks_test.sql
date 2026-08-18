-- Med List (Aging) — care tasks RLS boundary tests (migration 0012).
--
-- Same shape as care_events_test.sql: the column defaults the client relies on,
-- the constrained enums, and the security boundary. The one extra thing checked
-- here is the subject's read-but-not-write access, which is the only place this
-- table's policies differ from care_events.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _ct (k text primary key, v uuid);
grant select on _ct to authenticated;

-- ============================================================
-- Fixture
--   Group 1 "Wallner"     : Sarah owner, Mom the recipient (Mom has an account)
--   Group 2 "Other family": Stranger owner, recipient Someone
-- ============================================================
insert into _ct (k, v) values
    ('sarah',    public.make_user('Sarah')),
    ('mom',      public.make_user('Mom')),
    ('stranger', public.make_user('Stranger'));

insert into _ct (k, v) values ('g1', gen_random_uuid()), ('g2', gen_random_uuid());

insert into public.groups (id, name, created_by)
values ((select v from _ct where k = 'g1'), 'Wallner',      (select v from _ct where k = 'sarah')),
       ((select v from _ct where k = 'g2'), 'Other family', (select v from _ct where k = 'stranger'));

insert into public.group_members (group_id, user_id, role) values
    ((select v from _ct where k = 'g1'), (select v from _ct where k = 'sarah'),    'owner'),
    ((select v from _ct where k = 'g1'), (select v from _ct where k = 'mom'),      'subject'),
    ((select v from _ct where k = 'g2'), (select v from _ct where k = 'stranger'), 'owner');

insert into public.care_recipients (id, group_id, name, linked_user_id) values
    (gen_random_uuid(), (select v from _ct where k = 'g1'), 'Mom', (select v from _ct where k = 'mom'))
    returning id \gset mom_
insert into _ct (k, v) values ('r_mom', :'mom_id');

insert into public.care_recipients (id, group_id, name) values
    (gen_random_uuid(), (select v from _ct where k = 'g2'), 'Someone')
    returning id \gset other_
insert into _ct (k, v) values ('r_other', :'other_id');

insert into public.care_tasks (
    id, group_id, care_recipient_id, title, assignee_name, created_by_name
) values (
    gen_random_uuid(), (select v from _ct where k = 'g1'), (select v from _ct where k = 'r_mom'),
    'Refill the blood pressure prescription', 'Sarah', 'Sarah'
) returning id \gset t1_
insert into _ct (k, v) values ('task_mom', :'t1_id');

insert into public.care_tasks (
    id, group_id, care_recipient_id, title
) values (
    gen_random_uuid(), (select v from _ct where k = 'g2'), (select v from _ct where k = 'r_other'),
    'Book the dentist'
) returning id \gset t2_
insert into _ct (k, v) values ('task_other', :'t2_id');

select public.ok(
    (select priority = 'normal' and recurrence = 'never'
        and completed_at is null and assignee_name = 'Sarah'
       from public.care_tasks where id = (select v from _ct where k = 'task_mom')),
    'the untracked defaults (priority, recurrence, completed_at) are what the client relies on');

select public.throws(
    format('insert into public.care_tasks (group_id, care_recipient_id, title, priority)
            values (%L, %L, ''x'', ''urgent'')',
           (select v from _ct where k = 'g1'), (select v from _ct where k = 'r_mom')),
    'an unrecognized priority is rejected at the database, matching the client fallback to normal');

select public.throws(
    format('insert into public.care_tasks (group_id, care_recipient_id, title, recurrence)
            values (%L, %L, ''x'', ''fortnightly'')',
           (select v from _ct where k = 'g1'), (select v from _ct where k = 'r_mom')),
    'an unrecognized recurrence is rejected at the database, matching the client fallback to never');

-- ============================================================
set role authenticated;
-- ============================================================

\echo ''
\echo '-- owner (Sarah) --'
select public.act_as((select v from _ct where k = 'sarah'));

select public.ok(
    public.rows_visible('select 1 from public.care_tasks') = 1,
    'a group member sees only their own group''s tasks');

update public.care_tasks
   set completed_at = now(), completed_by_name = 'Sarah'
 where id = (select v from _ct where k = 'task_mom');
select public.ok(
    (select completed_at is not null from public.care_tasks
      where id = (select v from _ct where k = 'task_mom')),
    'group staff can tick off a task they own');

select public.throws(
    format('insert into public.care_tasks (group_id, care_recipient_id, title)
            values (%L, %L, ''Sneaky'')',
           (select v from _ct where k = 'g1'), (select v from _ct where k = 'r_other')),
    'staff cannot attach a task to another group''s recipient');

select public.throws(
    format('insert into public.care_tasks (group_id, care_recipient_id, title)
            values (%L, %L, ''Sneaky'')',
           (select v from _ct where k = 'g2'), (select v from _ct where k = 'r_other')),
    'staff cannot write into a group they do not belong to');

\echo ''
\echo '-- subject (Mom, the recipient herself) --'
select public.act_as((select v from _ct where k = 'mom'));

select public.ok(
    public.rows_visible(format('select 1 from public.care_tasks where id = %L',
                               (select v from _ct where k = 'task_mom'))) = 1,
    'a subject can read the tasks the family lined up for them');

-- No policy grants the subject `update`, so this matches zero rows rather than
-- raising. The proof is that the row is unchanged afterwards.
update public.care_tasks set title = 'Nope'
 where id = (select v from _ct where k = 'task_mom');
select public.ok(
    public.rows_visible(format('select 1 from public.care_tasks where id = %L and title = ''Nope''',
                               (select v from _ct where k = 'task_mom'))) = 0,
    'a subject cannot edit a task: staff writes, subject reads, as everywhere else');

select public.throws(
    format('insert into public.care_tasks (group_id, care_recipient_id, title)
            values (%L, %L, ''Mine now'')',
           (select v from _ct where k = 'g1'), (select v from _ct where k = 'r_mom')),
    'a subject cannot create a task');

\echo ''
\echo '-- outsider (Stranger, member of group 2) --'
select public.act_as((select v from _ct where k = 'stranger'));

select public.ok(
    public.rows_visible(format('select 1 from public.care_tasks where id = %L',
                               (select v from _ct where k = 'task_mom'))) = 0,
    'a non-member cannot read another group''s task by id');

\echo ''
\echo '-- signed out --'
select public.act_as(null);

select public.ok(
    public.rows_visible('select 1 from public.care_tasks') = 0,
    'anonymous access is blocked: a signed-out caller sees no tasks');

select public.throws(
    format('insert into public.care_tasks (group_id, care_recipient_id, title)
            values (%L, %L, ''Sneaky'')',
           (select v from _ct where k = 'g1'), (select v from _ct where k = 'r_mom')),
    'anonymous access is blocked: a signed-out caller cannot insert a task');

reset role;

\echo ''
\echo 'care_tasks: all assertions passed'
