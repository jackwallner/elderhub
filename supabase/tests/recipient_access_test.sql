-- Per-recipient access (migration 0018).
--
-- The point of this file: Elderhub Plus is sold as "everyone you look after, in
-- one circle", and the moment a circle holds two people the neighbour who helps
-- with Mom must not be able to read Dad. That is a database boundary (I4), so
-- it is tested here and not in the app.
--
-- Fixtures go in as the superuser so these exercise the policies. The RPC gets
-- its own section at the bottom.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _a (k text primary key, v uuid);
grant select on _a to authenticated;

-- `rows_visible` wraps its argument in a subquery, so it cannot run a write.
-- RLS on UPDATE is silent by design: a row the USING clause rejects is simply
-- not matched, so the only way to assert "that write did nothing" is to count
-- what it touched.
create or replace function public.rows_written(p_sql text)
returns bigint
language plpgsql
as $$
declare
    v_count bigint;
begin
    execute p_sql;
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;
grant execute on function public.rows_written(text) to authenticated;

-- ============================================================
-- Fixture
--   Circle "Wallner": Sarah owner, Mike caregiver (unrestricted),
--                     Nina caregiver (to be restricted to Mom),
--                     Mom subject, linked to recipient Mom
--   Recipients: Mom (linked), Dad (no account)
-- ============================================================
insert into _a (k, v) values
    ('sarah', public.make_user('Sarah')),
    ('mike',  public.make_user('Mike')),
    ('nina',  public.make_user('Nina')),
    ('mom',   public.make_user('Mom'));

insert into _a (k, v) values ('g', gen_random_uuid());

insert into public.groups (id, name, created_by)
values ((select v from _a where k = 'g'), 'Wallner', (select v from _a where k = 'sarah'));

insert into public.group_members (group_id, user_id, role) values
    ((select v from _a where k = 'g'), (select v from _a where k = 'sarah'), 'owner'),
    ((select v from _a where k = 'g'), (select v from _a where k = 'mike'),  'caregiver'),
    ((select v from _a where k = 'g'), (select v from _a where k = 'nina'),  'caregiver'),
    ((select v from _a where k = 'g'), (select v from _a where k = 'mom'),   'subject');

insert into _a (k, v) values ('r_mom', gen_random_uuid()), ('r_dad', gen_random_uuid());

insert into public.care_recipients (id, group_id, linked_user_id, name) values
    ((select v from _a where k = 'r_mom'), (select v from _a where k = 'g'),
     (select v from _a where k = 'mom'), 'Mom'),
    ((select v from _a where k = 'r_dad'), (select v from _a where k = 'g'), null, 'Dad');

insert into _a (k, v) values ('m_mom', gen_random_uuid()), ('m_dad', gen_random_uuid());

insert into public.medications (id, group_id, care_recipient_id, name) values
    ((select v from _a where k = 'm_mom'), (select v from _a where k = 'g'),
     (select v from _a where k = 'r_mom'), 'Lisinopril'),
    ((select v from _a where k = 'm_dad'), (select v from _a where k = 'g'),
     (select v from _a where k = 'r_dad'), 'Donepezil');

insert into public.dose_logs (group_id, medication_id, scheduled_at) values
    ((select v from _a where k = 'g'), (select v from _a where k = 'm_mom'), now()),
    ((select v from _a where k = 'g'), (select v from _a where k = 'm_dad'), now());

insert into public.bills (group_id, care_recipient_id, payee, amount) values
    ((select v from _a where k = 'g'), (select v from _a where k = 'r_mom'), 'Pharmacy', 12.00),
    ((select v from _a where k = 'g'), (select v from _a where k = 'r_dad'), 'Audiologist', 99.00);

insert into public.care_notes (group_id, care_recipient_id, body) values
    ((select v from _a where k = 'g'), (select v from _a where k = 'r_mom'), 'gate code'),
    ((select v from _a where k = 'g'), (select v from _a where k = 'r_dad'), 'hearing aid battery');

-- ============================================================
set role authenticated;
-- ============================================================

\echo ''
\echo '-- default is unrestricted: nothing anyone could read yesterday disappears --'
select public.act_as((select v from _a where k = 'mike'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 2,
    'an unrestricted caregiver sees both people in the circle');

select public.ok(
    public.rows_visible('select 1 from public.medications') = 2,
    'and both peoples medications');

select public.ok(
    public.rows_visible('select 1 from public.dose_logs') = 2,
    'and both peoples dose logs');

-- ============================================================
\echo ''
\echo '-- restricting Nina to Mom --'
select public.act_as((select v from _a where k = 'sarah'));

select public.set_member_access(
    (select v from _a where k = 'g')::text,
    (select v from _a where k = 'nina')::text,
    'listed',
    array[(select v from _a where k = 'r_mom')::text]);

select public.act_as((select v from _a where k = 'nina'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 1,
    'a restricted caregiver sees only the person they were granted');

select public.ok(
    public.rows_visible(
        'select 1 from public.care_recipients where id = '''
        || (select v from _a where k = 'r_dad') || '''') = 0,
    'and cannot see Dad at all');

select public.ok(
    public.rows_visible('select 1 from public.medications') = 1,
    'medications are scoped the same way');

select public.ok(
    public.rows_visible('select 1 from public.dose_logs') = 1,
    'dose logs are scoped through the medication, not the group');

select public.ok(
    public.rows_visible('select 1 from public.bills') = 1,
    'bills are scoped');

select public.ok(
    public.rows_visible('select 1 from public.care_notes') = 1,
    'notes are scoped, which is where a family writes the gate code');

-- Reading is only half of it. A restricted member must not be able to write to
-- someone they cannot see, or the boundary is decorative.
select public.throws(
    'insert into public.medications (group_id, care_recipient_id, name) values ('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'r_dad') || ''',''Warfarin'')',
    'a restricted caregiver cannot write a medication for someone they cannot see');

select public.throws(
    'insert into public.bills (group_id, care_recipient_id, payee, amount) values ('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'r_dad') || ''',''Anything'',1.0)',
    'nor a bill');

-- RLS on UPDATE does not raise, it just matches nothing, so this asserts the
-- row count rather than an exception.
select public.ok(
    public.rows_written(
        'update public.care_recipients set name = ''Renamed'' where id = '''
        || (select v from _a where k = 'r_dad') || '''') = 0,
    'nor rename them');

-- A member scoped to Mom adding a whole new person would create a record they
-- could not then open.
select public.throws(
    'insert into public.care_recipients (group_id, name) values ('''
    || (select v from _a where k = 'g') || ''',''Aunt Vi'')',
    'a restricted caregiver cannot add a new person to the circle');

-- ============================================================
\echo ''
\echo '-- the restriction does not leak sideways --'
select public.act_as((select v from _a where k = 'mike'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 2,
    'restricting Nina changed nothing for Mike');

select public.act_as((select v from _a where k = 'sarah'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 2,
    'nor for the owner');

-- The whole point of the migration being safe to apply: an unrestricted member
-- keeps write access, including the RETURNING clause PostgREST puts on every
-- insert. This is the bug the first draft of 0018 had.
select public.ok(
    public.rows_written(
        'insert into public.care_recipients (group_id, name) values ('''
        || (select v from _a where k = 'g') || ''',''Aunt Vi'') returning id') = 1,
    'an unrestricted member can add a person and read back the inserted row');

-- ============================================================
\echo ''
\echo '-- the subject boundary is untouched --'
select public.act_as((select v from _a where k = 'mom'));

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 1,
    'the subject still sees only her own record');

select public.ok(
    public.rows_visible('select 1 from public.medications') = 1,
    'and only her own medications');

-- ============================================================
\echo ''
\echo '-- who may change access --'
select public.act_as((select v from _a where k = 'mike'));

select public.throws_code(
    'select public.set_member_access('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'nina') || ''',''all'',null)',
    '42501',
    'a caregiver cannot change who sees whom');

select public.act_as((select v from _a where k = 'nina'));

select public.throws_code(
    'select public.set_member_access('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'nina') || ''',''all'',null)',
    '42501',
    'and a restricted member cannot lift their own restriction');

select public.act_as((select v from _a where k = 'sarah'));

select public.throws_code(
    'select public.set_member_access('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'sarah') || ''',''listed'',null)',
    '42501',
    'an owner cannot restrict themselves out of their own circle');

select public.throws_code(
    'select public.set_member_access('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'mom') || ''',''listed'',null)',
    '42501',
    'a subject is scoped by their linked record, not by this table');

select public.throws_code(
    'select public.set_member_access('''
    || (select v from _a where k = 'g') || ''','''
    || (select v from _a where k = 'nina') || ''',''everything'',null)',
    '22023',
    'an unknown scope is refused rather than stored');

-- ============================================================
\echo ''
\echo '-- lifting a restriction, and revoking one grant --'
select public.act_as((select v from _a where k = 'sarah'));

select public.set_member_access(
    (select v from _a where k = 'g')::text,
    (select v from _a where k = 'nina')::text,
    'listed',
    array[(select v from _a where k = 'r_mom')::text,
          (select v from _a where k = 'r_dad')::text]);

select public.act_as((select v from _a where k = 'nina'));
select public.ok(
    public.rows_visible('select 1 from public.medications') = 2,
    'granting both people restores both medication lists');

select public.act_as((select v from _a where k = 'sarah'));
select public.set_member_access(
    (select v from _a where k = 'g')::text,
    (select v from _a where k = 'nina')::text,
    'listed',
    array[(select v from _a where k = 'r_mom')::text]);

select public.act_as((select v from _a where k = 'nina'));
select public.ok(
    public.rows_visible('select 1 from public.medications') = 1,
    'sending a shorter list revokes the grant it left out');

select public.act_as((select v from _a where k = 'sarah'));
select public.set_member_access(
    (select v from _a where k = 'g')::text,
    (select v from _a where k = 'nina')::text,
    'all',
    null);

select public.act_as((select v from _a where k = 'nina'));
select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 3,
    'lifting the restriction restores the whole circle, including Aunt Vi');

-- ============================================================
\echo ''
\echo '-- a removed member keeps nothing --'
select public.act_as((select v from _a where k = 'sarah'));
select public.set_member_access(
    (select v from _a where k = 'g')::text,
    (select v from _a where k = 'nina')::text,
    'listed',
    array[(select v from _a where k = 'r_mom')::text]);

reset role;
update public.group_members set removed_at = now()
 where group_id = (select v from _a where k = 'g')
   and user_id  = (select v from _a where k = 'nina');
set role authenticated;

select public.act_as((select v from _a where k = 'nina'));
select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 0,
    'a removed member sees nothing, even with grant rows still on file');

\echo ''
\echo 'Recipient access: all assertions passed'
