-- Two real authenticated database sessions, paused at a reproducible schedule.
-- TEST-ONLY dblink connections stay inside scripts/test-db.sh's local cluster.
\set ON_ERROR_STOP on
\set QUIET on
create extension if not exists dblink;
create table _swap_ids (k text primary key, v uuid);
grant select on _swap_ids to authenticated;
insert into _swap_ids values
 ('owner', make_user('Swap Owner')), ('joiner', make_user('Swap Joiner')),
 ('visitor', make_user('Swap Visitor')), ('target', gen_random_uuid()), ('solo', gen_random_uuid()),
 ('person', gen_random_uuid());
insert into groups(id, name) select v, k from _swap_ids where k in ('target', 'solo');
insert into care_recipients(id, group_id, name)
select (select v from _swap_ids where k = 'person'), v, 'Onboarding person' from _swap_ids where k = 'solo';
insert into group_members(group_id, user_id, role) values
 ((select v from _swap_ids where k = 'target'), (select v from _swap_ids where k = 'owner'), 'owner'),
 ((select v from _swap_ids where k = 'solo'), (select v from _swap_ids where k = 'joiner'), 'owner');
insert into invite_codes(code, group_id, role_to_grant, created_by, expires_at) values
 ('SWAPAB22', (select v from _swap_ids where k = 'target'), 'caregiver',
  (select v from _swap_ids where k = 'owner'), now() + interval '1 day'),
 ('SWAPCD22', (select v from _swap_ids where k = 'solo'), 'caregiver',
  (select v from _swap_ids where k = 'joiner'), now() + interval '1 day');

create function public.swap_accept_result(p_code text) returns jsonb
language plpgsql as $$
declare v_result jsonb;
begin
    select to_jsonb(r) into v_result from public.accept_invite(p_code) r;
    if p_code = 'SWAPCD22' and (v_result->>'ok')::boolean then
        insert into public.care_tasks(group_id, care_recipient_id, title, notes)
        values ((select v from _swap_ids where k = 'solo'),
                (select v from _swap_ids where k = 'person'),
                'Visitor care task', 'Newly joined member wrote this before the swap committed');
        v_result := v_result || jsonb_build_object('wrote_care_task', true);
    end if;
    return v_result;
exception when others then
    return jsonb_build_object('ok', false, 'error_code', sqlstate);
end $$;
create table _swap_results (k text primary key, result jsonb);
do $$
declare
    v_conn text := format('dbname=%L host=%L port=%L user=postgres',
        current_database(), current_setting('unix_socket_directories'), current_setting('port'));
begin
    perform dblink_connect('swap_blocker', v_conn);
    perform dblink_connect('swap_owner', v_conn);
    perform dblink_connect('swap_visitor', v_conn);
    perform dblink_exec('swap_blocker', 'begin; lock table public.medications in access exclusive mode');
    perform dblink_exec('swap_owner', 'set application_name = ''sharing_swap_owner''; set role authenticated');
    perform dblink_exec('swap_owner', format('set test.uid = %L', (select v::text from _swap_ids where k = 'joiner')));
    perform dblink_exec('swap_visitor', 'set application_name = ''sharing_swap_visitor''; set role authenticated');
    perform dblink_exec('swap_visitor', format('set test.uid = %L', (select v::text from _swap_ids where k = 'visitor')));
    perform dblink_send_query('swap_owner', 'select public.swap_accept_result(''SWAPAB22'')');
end $$;

do $$
declare v_waiting boolean := false;
begin
    for i in 1..500 loop
        select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid = l.pid
            where a.application_name = 'sharing_swap_owner'
              and l.relation = 'public.medications'::regclass and not l.granted) into v_waiting;
        exit when v_waiting;
        perform pg_sleep(0.01);
        perform pg_stat_clear_snapshot();
    end loop;
    perform ok(v_waiting, 'owner is paused in the untouched-record check after counting members');
    perform dblink_send_query('swap_visitor', 'select public.swap_accept_result(''SWAPCD22'')');
end $$;

do $$
declare v_reached boolean := false;
begin
    for i in 1..500 loop
        v_reached := dblink_is_busy('swap_visitor') = 0 or exists(
            select 1 from pg_stat_activity where application_name = 'sharing_swap_visitor'
              and wait_event_type = 'Lock');
        exit when v_reached;
        perform pg_sleep(0.01);
        perform pg_stat_clear_snapshot();
    end loop;
    perform ok(v_reached, 'visitor has either joined or reached the circle serialization lock');
    perform dblink_exec('swap_blocker', 'commit');
end $$;

insert into _swap_results select 'owner', result from dblink_get_result('swap_owner') as t(result jsonb);
insert into _swap_results select 'visitor', result from dblink_get_result('swap_visitor') as t(result jsonb);
select dblink_disconnect('swap_blocker');
select dblink_disconnect('swap_owner');
select dblink_disconnect('swap_visitor');
table _swap_results;
select ok(not (
    (select (result->>'ok')::boolean from _swap_results where k = 'owner')
    and (select (result->>'ok')::boolean from _swap_results where k = 'visitor')
    and not exists(select 1 from groups where id = (select v from _swap_ids where k = 'solo'))
), 'solo_swap_cannot_erase_a_newly_joined_members_circle');
select ok(
    (select (result->>'ok')::boolean from _swap_results where k = 'owner')
    <> (select (result->>'ok')::boolean from _swap_results where k = 'visitor'),
    'exactly one of the competing lifecycle operations succeeds');
select ok(not (select (result->>'ok')::boolean from _swap_results where k = 'visitor')
    or exists(select 1 from group_members where group_id = (select v from _swap_ids where k = 'solo')
        and user_id = (select v from _swap_ids where k = 'visitor') and removed_at is null),
    'a successful join retains its membership');
select ok(not (select (result->>'ok')::boolean from _swap_results where k = 'visitor')
    or exists(select 1 from care_tasks where group_id = (select v from _swap_ids where k = 'solo')
        and title = 'Visitor care task'), 'a successfully joined members committed care task survives');
select ok(not exists(select 1 from _swap_results where result->>'error_code' in ('40P01', '23503')),
    'the concurrent lifecycle operations return normal results without deadlocks or broken foreign keys');
\echo 'Concurrent solo swap: all assertions passed'
