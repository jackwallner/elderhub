-- Positive and negative coverage of every table containing care data.
\set ON_ERROR_STOP on
\set QUIET on
begin;
create table _matrix_ids (k text primary key, v uuid);
grant select on _matrix_ids to authenticated;
insert into _matrix_ids values
 ('new',make_user('Matrix New')),('owner',make_user('Matrix Owner')),('limited',make_user('Matrix Limited')),
 ('outsider',make_user('Matrix Outsider')),('subject',make_user('Matrix Subject')),
 ('g',gen_random_uuid()),('mom',gen_random_uuid()),('dad',gen_random_uuid()),('med',gen_random_uuid());
insert into groups(id,name) select v,'Matrix' from _matrix_ids where k='g';
insert into group_members(group_id,user_id,role)
select (select v from _matrix_ids where k='g'),v,
 case k when 'owner' then 'owner' when 'subject' then 'subject' else 'caregiver' end
from _matrix_ids where k in ('owner','limited','subject');
insert into care_recipients(id,group_id,name,linked_user_id)
select v,(select v from _matrix_ids where k='g'),k,
 case when k='dad' then (select v from _matrix_ids where k='subject') end
from _matrix_ids where k in ('mom','dad');
insert into medications(id,group_id,care_recipient_id,name)
select (select v from _matrix_ids where k='med'),(select v from _matrix_ids where k='g'),(select v from _matrix_ids where k='dad'),'Private refill';
insert into dose_logs(group_id,medication_id,scheduled_at)
select (select v from _matrix_ids where k='g'),v,now() from _matrix_ids where k='med';
insert into vital_readings(group_id,care_recipient_id,kind,primary_value)
select (select v from _matrix_ids where k='g'),v,'weight',70 from _matrix_ids where k='dad';
insert into care_events(group_id,care_recipient_id,kind)
select (select v from _matrix_ids where k='g'),v,'other' from _matrix_ids where k='dad';
do $$ declare t text; begin
 foreach t in array array['providers','emergency_contacts'] loop
  execute format('insert into %I(group_id,care_recipient_id,name) select (select v from _matrix_ids where k=''g''),v,''Private'' from _matrix_ids where k=''dad''',t);
 end loop;
 foreach t in array array['visits','care_tasks','care_notes','bills','check_in_settings'] loop
  execute format('insert into %I(group_id,care_recipient_id) select (select v from _matrix_ids where k=''g''),v from _matrix_ids where k=''dad''',t);
 end loop;
end $$;
insert into check_ins(group_id,care_recipient_id,source)
select (select v from _matrix_ids where k='g'),v,'self' from _matrix_ids where k='dad';
insert into group_billing(group_id) select v from _matrix_ids where k='g';
set role authenticated;
select act_as((select v from _matrix_ids where k='owner'));
select set_member_access((select v from _matrix_ids where k='g')::text,(select v from _matrix_ids where k='limited')::text,'listed',array[(select v from _matrix_ids where k='mom')::text]);
-- Each row exists and is visible to its owner, so a zero below is meaningful.
do $$ declare t text; begin
 foreach t in array array['care_recipients','medications','dose_logs','visits','vital_readings','emergency_contacts','providers','care_events','care_tasks','care_notes','bills','check_ins','check_in_settings','audit_log','group_billing'] loop
  perform ok(rows_visible(format('select 1 from %I where group_id=%L',t,(select v from _matrix_ids where k='g')))>0,'owner can read '||t);
 end loop;
end $$;
select act_as((select v from _matrix_ids where k='limited'));
do $$ declare t text; n bigint; begin
 foreach t in array array['medications','dose_logs','visits','vital_readings','emergency_contacts','providers','care_events','care_tasks','care_notes','bills','check_ins','check_in_settings','audit_log'] loop
  perform ok(rows_visible(format('select 1 from %I where group_id=%L',t,(select v from _matrix_ids where k='g')))=0,'restricted helper cannot read Dad through '||t);
  execute format('update %I set %I=%I where group_id=%L',t,case when t='audit_log' then 'actor_name' else 'updated_at' end,case when t='audit_log' then 'actor_name' else 'updated_at' end,(select v from _matrix_ids where k='g'));
  get diagnostics n = row_count;
  perform ok(n=0,'restricted helper cannot update Dad through '||t);
 end loop;
 perform throws_code(format('insert into care_notes(group_id,care_recipient_id,body) values(%L,%L,''hidden'')',(select v from _matrix_ids where k='g'),(select v from _matrix_ids where k='dad')),'42501','restricted helper cannot write a hidden recipient');
end $$;
select act_as((select v from _matrix_ids where k='outsider'));
do $$ declare t text; n bigint; begin
 foreach t in array array['care_recipients','medications','dose_logs','visits','vital_readings','emergency_contacts','providers','care_events','care_tasks','care_notes','bills','check_ins','check_in_settings','audit_log','group_billing'] loop
  perform ok(rows_visible(format('select 1 from %I where group_id=%L',t,(select v from _matrix_ids where k='g')))=0,'outsider cached group id cannot read '||t);
  execute format('delete from %I where group_id=%L',t,(select v from _matrix_ids where k='g'));
  get diagnostics n = row_count;
  perform ok(n=0,'outsider cannot delete '||t);
 end loop;
end $$;
select act_as((select v from _matrix_ids where k='owner'));
update group_billing set entitlement='plus' where group_id=(select v from _matrix_ids where k='g');
select ok((select entitlement from group_billing where group_id=(select v from _matrix_ids where k='g'))='free','client cannot update billing');
delete from group_billing where group_id=(select v from _matrix_ids where k='g');
select ok(exists(select 1 from group_billing where group_id=(select v from _matrix_ids where k='g')),'client cannot delete billing');
select throws_code(format('insert into group_billing(group_id) values(%L)',gen_random_uuid()),'42501','client cannot insert billing');
create temporary table _matrix_code as select generate_invite_code((select v from _matrix_ids where k='g')::text,'caregiver') as code;
select act_as((select v from _matrix_ids where k='new'));
create temporary table _matrix_solo as select create_group('Untouched onboarding') as id;
insert into care_recipients(group_id,name) select id,'Onboarding person' from _matrix_solo;
select ok((select ok from accept_invite((select code from _matrix_code))),'an untouched solo circle can still swap');
select ok(not exists(select 1 from groups where id=(select id from _matrix_solo)),'the old untouched circle is gone');
select ok(exists(select 1 from medications where id=(select v from _matrix_ids where k='med')),'joining preserves the target circle medical record');
select act_as((select v from _matrix_ids where k='owner'));
select remove_member((select v from _matrix_ids where k='g')::text,(select v from _matrix_ids where k='subject')::text);
select act_as((select v from _matrix_ids where k='subject'));
do $$ declare t text; begin
 foreach t in array array['care_recipients','medications','dose_logs','visits','vital_readings','emergency_contacts','providers','care_events','care_tasks','care_notes','bills','check_ins','check_in_settings','audit_log','group_billing'] loop
  perform ok(rows_visible(format('select 1 from %I where group_id=%L',t,(select v from _matrix_ids where k='g')))=0,'removed subject cached ids cannot read '||t);
 end loop;
end $$;
reset role;
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and not exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')),'all public security definers have a fixed search_path');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname in ('care_recipients','medications','dose_logs','visits','vital_readings','emergency_contacts','providers','care_events','care_tasks','care_notes','bills','check_ins','check_in_settings','audit_log','group_billing') and not c.relrowsecurity),'all care tables have RLS enabled');
rollback;
\echo 'Security matrix: all assertions passed'
