-- Med List (Aging) — providers RLS boundary tests (plan82 slice C, migration 0010).
--
-- Column-level defaults are exercised in the app's own tests; this file is
-- about the security boundary: an anonymous caller sees nothing, and a
-- non-member cannot read another group's providers, matching rls_test.sql's
-- shape for the other leaf tables.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _pv (k text primary key, v uuid);
grant select on _pv to authenticated;

-- ============================================================
-- Fixture
--   Group 1 "Wallner"     : Sarah owner, recipient Mom, provider Dr. Patel
--   Group 2 "Other family": Stranger owner, recipient Someone, provider Dr. Lee
-- ============================================================
insert into _pv (k, v) values
    ('sarah',    public.make_user('Sarah')),
    ('stranger', public.make_user('Stranger'));

insert into _pv (k, v) values ('g1', gen_random_uuid()), ('g2', gen_random_uuid());

insert into public.groups (id, name, created_by)
values ((select v from _pv where k = 'g1'), 'Wallner',      (select v from _pv where k = 'sarah')),
       ((select v from _pv where k = 'g2'), 'Other family', (select v from _pv where k = 'stranger'));

insert into public.group_members (group_id, user_id, role) values
    ((select v from _pv where k = 'g1'), (select v from _pv where k = 'sarah'),    'owner'),
    ((select v from _pv where k = 'g2'), (select v from _pv where k = 'stranger'), 'owner');

insert into public.care_recipients (id, group_id, name) values
    (gen_random_uuid(), (select v from _pv where k = 'g1'), 'Mom')
    returning id \gset mom_
insert into _pv (k, v) values ('r_mom', :'mom_id');

insert into public.care_recipients (id, group_id, name) values
    (gen_random_uuid(), (select v from _pv where k = 'g2'), 'Someone')
    returning id \gset other_
insert into _pv (k, v) values ('r_other', :'other_id');

insert into public.providers (id, group_id, care_recipient_id, name, specialty, phone) values
    (gen_random_uuid(), (select v from _pv where k = 'g1'), (select v from _pv where k = 'r_mom'),
     'Dr. Patel', 'Cardiology', '555-0101')
    returning id \gset p1_
insert into _pv (k, v) values ('provider_mom', :'p1_id');

insert into public.providers (id, group_id, care_recipient_id, name, specialty, phone) values
    (gen_random_uuid(), (select v from _pv where k = 'g2'), (select v from _pv where k = 'r_other'),
     'Dr. Lee', 'Dentistry', '555-0202')
    returning id \gset p2_
insert into _pv (k, v) values ('provider_other', :'p2_id');

select public.ok(
    (select is_pharmacy = false and phone = '555-0101'
       from public.providers where id = (select v from _pv where k = 'provider_mom')),
    'the untracked defaults (not a pharmacy) and the phone the client relies on');

-- ============================================================
set role authenticated;
-- ============================================================

\echo ''
\echo '-- owner (Sarah) --'
select public.act_as((select v from _pv where k = 'sarah'));

select public.ok(
    public.rows_visible('select 1 from public.providers') = 1,
    'a group member sees only their own group''s providers');

select public.ok(
    public.rows_visible(format('select 1 from public.providers where id = %L',
                               (select v from _pv where k = 'provider_other'))) = 0,
    'a group member cannot read another group''s provider by id');

update public.providers set phone = '555-9999'
 where id = (select v from _pv where k = 'provider_mom');
select public.ok(
    (select phone = '555-9999' from public.providers
      where id = (select v from _pv where k = 'provider_mom')),
    'group staff can edit a provider they own');

select public.throws(
    format('insert into public.providers (group_id, care_recipient_id, name)
            values (%L, %L, ''Sneaky'')',
           (select v from _pv where k = 'g1'), (select v from _pv where k = 'r_other')),
    'staff cannot attach a provider to another group''s recipient');

select public.throws(
    format('insert into public.providers (group_id, care_recipient_id, name)
            values (%L, %L, ''Sneaky'')',
           (select v from _pv where k = 'g2'), (select v from _pv where k = 'r_other')),
    'staff cannot write into a group they do not belong to');

\echo ''
\echo '-- outsider (Stranger, member of group 2) --'
select public.act_as((select v from _pv where k = 'stranger'));

select public.ok(
    public.rows_visible('select 1 from public.providers') = 1,
    'a non-member of group 1 sees none of the Wallners'' providers');

select public.ok(
    public.rows_visible(format('select 1 from public.providers where id = %L',
                               (select v from _pv where k = 'provider_mom'))) = 0,
    'a non-member cannot read another group''s provider by id');

\echo ''
\echo '-- signed out --'
select public.act_as(null);

select public.ok(
    public.rows_visible('select 1 from public.providers') = 0,
    'anonymous access is blocked: a signed-out caller sees no providers');

select public.throws(
    format('insert into public.providers (group_id, care_recipient_id, name)
            values (%L, %L, ''Sneaky'')',
           (select v from _pv where k = 'g1'), (select v from _pv where k = 'r_mom')),
    'anonymous access is blocked: a signed-out caller cannot insert a provider');

reset role;

\echo ''
\echo 'providers: all assertions passed'
