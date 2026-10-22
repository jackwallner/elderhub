-- Check-in facts must obey recipient access in both REST reads and push targets.
\set ON_ERROR_STOP on
\set QUIET on
begin;
create table _notice_ids (k text primary key, v uuid);
create table _notice_results (name text, passed boolean, detail text);
grant select on _notice_ids to authenticated;
grant all on _notice_results to authenticated;
create function public.notice_case(p_name text, p_sql text) returns void
language plpgsql as $$
begin
    execute p_sql;
    insert into _notice_results values (p_name, true, null);
    raise notice 'PASS %', p_name;
exception when others then
    insert into _notice_results values (p_name, false, sqlerrm);
    raise notice 'FAIL %: %', p_name, sqlerrm;
end $$;

insert into _notice_ids values
 ('owner', make_user('Notice Owner')), ('limited', make_user('Notice Helper')),
 ('subject', make_user('Notice Subject')), ('outsider', make_user('Notice Outsider')),
 ('g', gen_random_uuid()), ('mom', gen_random_uuid()), ('dad', gen_random_uuid());
insert into groups(id, name) select v, 'Notice circle' from _notice_ids where k = 'g';
insert into group_members(group_id, user_id, role)
select (select v from _notice_ids where k = 'g'), v,
       case k when 'owner' then 'owner' when 'subject' then 'subject' else 'caregiver' end
from _notice_ids where k in ('owner', 'limited', 'subject');
insert into care_recipients(id, group_id, name, linked_user_id)
select v, (select v from _notice_ids where k = 'g'), 'Notice ' || k,
       case when k = 'mom' then (select v from _notice_ids where k = 'subject') end
from _notice_ids where k in ('mom', 'dad');
update profiles set apns_token = 'notice-token-' || k
from _notice_ids where profiles.id = v and k in ('owner', 'limited', 'subject');

set role authenticated;
select act_as((select v from _notice_ids where k = 'owner'));
select set_member_access((select v from _notice_ids where k = 'g')::text,
    (select v from _notice_ids where k = 'limited')::text, 'listed',
    array[(select v from _notice_ids where k = 'mom')::text]);
reset role;
insert into check_in_settings(care_recipient_id, group_id, enabled,
    window_start_minute, window_end_minute, grace_minutes, timezone)
select v, (select v from _notice_ids where k = 'g'), true, 0, 1, 0,
       -- Put both windows well in the past without depending on local time.
       case when extract(hour from now() at time zone 'UTC') < 12
            then 'Etc/GMT-12' else 'UTC' end
from _notice_ids where k in ('mom', 'dad');
select queue_check_in_notices();
-- Historical notices cannot safely be matched to recipients by name.
insert into group_notices(group_id, kind, body, subject_name)
select v, 'no_check_in', 'Legacy private check-in', 'Notice dad'
from _notice_ids where k = 'g';

set role authenticated;
select act_as((select v from _notice_ids where k = 'owner'));
select ok((select count(*) from group_notices where group_id = (select v from _notice_ids where k = 'g')) = 3,
    'unrestricted owner still sees both recipients and the historical notice');
select act_as((select v from _notice_ids where k = 'limited'));
select notice_case('restricted_helper_cannot_read_other_recipient_notices', $q$
    select ok(not exists(select 1 from group_notices
        where group_id = (select v from _notice_ids where k = 'g') and subject_name = 'Notice dad'),
        'hidden check-in facts must not be readable through the notice queue') $q$);
select notice_case('restricted_helper_still_sees_assigned_recipient_notice', $q$
    select ok((select count(*) from group_notices
        where group_id = (select v from _notice_ids where k = 'g') and subject_name = 'Notice mom') = 1,
        'assigned recipient check-in notices remain available') $q$);
select throws_code('select * from pending_notices_with_targets()', '42501',
    'a restricted client cannot bypass notice RLS with the push RPC');
select throws_code('select queue_check_in_notices()', '42501',
    'a client cannot invoke the service notice writer');
select act_as((select v from _notice_ids where k = 'subject'));
select notice_case('subject_cannot_read_another_recipient_check_in_notices', $q$
    select ok(not exists(select 1 from group_notices
        where group_id = (select v from _notice_ids where k = 'g') and subject_name = 'Notice dad'),
        'a subject must not receive another persons check-in history') $q$);
select act_as((select v from _notice_ids where k = 'outsider'));
select ok(not exists(select 1 from group_notices where group_id = (select v from _notice_ids where k = 'g')),
    'outsider cannot read notices using a cached circle id');
reset role;
select notice_case('restricted_helper_cannot_receive_hidden_recipient_push', $q$
    select ok(not exists(select 1 from pending_notices_with_targets() t
        join group_notices n on n.id = t.notice_id
        where n.group_id = (select v from _notice_ids where k = 'g')
          and t.apns_token = 'notice-token-limited' and n.subject_name = 'Notice dad'),
        'the service push query must enforce recipient access too') $q$);
select ok(exists(select 1 from pending_notices_with_targets() t
    join group_notices n on n.id = t.notice_id
    where n.group_id = (select v from _notice_ids where k = 'g')
      and t.apns_token = 'notice-token-limited' and n.subject_name = 'Notice mom'),
    'the helper still receives their assigned recipients check-in push');
select ok((select count(*) from pending_notices_with_targets() t
    join group_notices n on n.id = t.notice_id
    where n.group_id = (select v from _notice_ids where k = 'g') and t.apns_token = 'notice-token-owner') = 3,
    'the owner still receives all three notices');

set role authenticated;
select act_as((select v from _notice_ids where k = 'owner'));
select set_member_access((select v from _notice_ids where k = 'g')::text,
    (select v from _notice_ids where k = 'limited')::text, 'listed', '{}');
select act_as((select v from _notice_ids where k = 'limited'));
select notice_case('scope_revocation_hides_cached_notice_ids', $q$
    select ok(not exists(select 1 from group_notices where group_id = (select v from _notice_ids where k = 'g')),
        'revoked recipient scope must immediately hide queued notices') $q$);
reset role;
select notice_case('scope_revocation_removes_queued_push_targets', $q$
    select ok(not exists(select 1 from pending_notices_with_targets() t
        join group_notices n on n.id = t.notice_id
        where n.group_id = (select v from _notice_ids where k = 'g') and t.apns_token = 'notice-token-limited'),
        'revoked recipient scope must immediately stop queued pushes') $q$);
set role authenticated;
select act_as((select v from _notice_ids where k = 'owner'));
select set_member_access((select v from _notice_ids where k = 'g')::text,
    (select v from _notice_ids where k = 'limited')::text, 'all', null);
select remove_member((select v from _notice_ids where k = 'g')::text,
    (select v from _notice_ids where k = 'limited')::text);
select act_as((select v from _notice_ids where k = 'limited'));
select ok(not exists(select 1 from group_notices where group_id = (select v from _notice_ids where k = 'g')),
    'a removed unrestricted member cannot read cached notice ids');
reset role;
select ok(not exists(select 1 from pending_notices_with_targets() t
    join group_notices n on n.id = t.notice_id
    where n.group_id = (select v from _notice_ids where k = 'g') and t.apns_token = 'notice-token-limited'),
    'a removed unrestricted member receives no queued notices');
select ok(not exists(select 1 from _notice_results where not passed),
    (select string_agg(name, ', ') from _notice_results where not passed));
rollback;
\echo 'Notice recipient boundaries: all assertions passed'
