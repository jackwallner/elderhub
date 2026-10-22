-- Reproducible tenant and recipient boundary attacks. Local test helpers only.
\set ON_ERROR_STOP on
\set QUIET on
create table _security_ids (k text primary key, v uuid);
create table _security_codes (k text primary key, v text);
create table _security_results (name text, passed boolean, detail text);
grant all on _security_ids, _security_codes, _security_results to authenticated;
create function public.security_case(p_name text, p_sql text) returns void
language plpgsql as $$
begin
    execute p_sql;
    insert into _security_results values (p_name, true, null);
    raise notice 'PASS %', p_name;
exception when others then
    insert into _security_results values (p_name, false, sqlerrm);
    raise notice 'FAIL %: %', p_name, sqlerrm;
end $$;
insert into _security_ids values
 ('owner', make_user('Security Owner')), ('helper', make_user('Security Helper')),
 ('limited', make_user('Security Limited')), ('joiner', make_user('Security Joiner')),
 ('other', make_user('Security Other')), ('subject', make_user('Security Subject')),
 ('g', gen_random_uuid()), ('foreign', gen_random_uuid()), ('solo', gen_random_uuid()),
 ('mom', gen_random_uuid()), ('dad', gen_random_uuid()), ('foreign_person', gen_random_uuid()),
 ('solo_person', gen_random_uuid()), ('med', gen_random_uuid());
update auth.users set email_confirmed_at = now(), email = case when id = (select v from _security_ids where k='joiner')
    then 'joiner@example.com' else 'other@example.com' end
where id in (select v from _security_ids);
insert into groups(id,name) select v,k from _security_ids where k in ('g','foreign','solo');
insert into group_members(group_id,user_id,role) values
 ((select v from _security_ids where k='g'),(select v from _security_ids where k='owner'),'owner'),
 ((select v from _security_ids where k='g'),(select v from _security_ids where k='helper'),'caregiver'),
 ((select v from _security_ids where k='g'),(select v from _security_ids where k='limited'),'caregiver'),
 ((select v from _security_ids where k='g'),(select v from _security_ids where k='subject'),'subject'),
 ((select v from _security_ids where k='foreign'),(select v from _security_ids where k='other'),'owner'),
 ((select v from _security_ids where k='solo'),(select v from _security_ids where k='joiner'),'owner');
insert into care_recipients(id,group_id,name,linked_user_id) values
 ((select v from _security_ids where k='mom'),(select v from _security_ids where k='g'),'Mom',null),
 ((select v from _security_ids where k='dad'),(select v from _security_ids where k='g'),'Private Dad',(select v from _security_ids where k='subject')),
 ((select v from _security_ids where k='foreign_person'),(select v from _security_ids where k='foreign'),'Foreign Person',null),
 ((select v from _security_ids where k='solo_person'),(select v from _security_ids where k='solo'),'Solo Person',null);
insert into medications(id,group_id,care_recipient_id,name) values
 ((select v from _security_ids where k='med'),(select v from _security_ids where k='g'),(select v from _security_ids where k='dad'),'Private drug');
insert into check_in_settings(care_recipient_id,group_id,enabled,window_start_minute,window_end_minute,grace_minutes)
select (select v from _security_ids where k='foreign_person'),(select v from _security_ids where k='foreign'),true,0,1,0;
insert into check_ins(group_id,care_recipient_id,source,pressed_by)
select (select v from _security_ids where k='solo'),(select v from _security_ids where k='solo_person'),'self',(select v from _security_ids where k='joiner');
insert into group_billing(group_id,entitlement,is_lifetime)
select v,'plus',true from _security_ids where k='foreign';
set role authenticated;
select act_as((select v from _security_ids where k='owner'));
select set_member_access((select v from _security_ids where k='g')::text,(select v from _security_ids where k='limited')::text,'listed',array[(select v from _security_ids where k='mom')::text]);
insert into _security_codes select 'email',generate_invite_code((select v from _security_ids where k='g')::text,'caregiver',null,'recipient@example.com');
insert into _security_codes select 'open',generate_invite_code((select v from _security_ids where k='g')::text,'caregiver');
select security_case('caregiver_invite_cannot_name_foreign_recipient', $q$
 select throws_code(format('select generate_invite_code(%L,''caregiver'',%L)',(select v from _security_ids where k='g')::text,(select v from _security_ids where k='foreign_person')::text),'22023','caregiver invite cannot carry a foreign recipient link') $q$);
select act_as((select v from _security_ids where k='helper'));
insert into _security_codes select 'helper',generate_invite_code((select v from _security_ids where k='g')::text,'caregiver');
select act_as((select v from _security_ids where k='joiner'));
select security_case('email_invite_rejects_other_account', $q$
 select ok(not (select ok from accept_invite((select v from _security_codes where k='email'))),'wrong email must be refused') $q$);
select security_case('solo_swap_preserves_check_in_history', $q$
 select ok((select error_code from accept_invite((select v from _security_codes where k='open')))='already_in_group','check-in history must prevent an untouched-circle swap') $q$);
select act_as((select v from _security_ids where k='limited'));
select security_case('restricted_staff_cannot_mint_unrestricted_invites', $q$
 select throws_code(format('select generate_invite_code(%L,''caregiver'')',(select v from _security_ids where k='g')::text),'42501','restricted helper cannot delegate wider access') $q$);
select security_case('restricted_staff_cannot_read_unrestricted_codes', $q$
 select ok(not exists(select 1 from invite_codes where code=(select v from _security_codes where k='open')),'hidden owner code must stay hidden') $q$);
select security_case('audit_snapshots_obey_recipient_scope', $q$
 select ok(not exists(select 1 from audit_log where row_id=(select v from _security_ids where k='med')),'audit must not disclose the private medication') $q$);
select security_case('direct_link_write_cannot_bypass_revocation', $q$
 select throws_code(format('update care_recipients set linked_user_id=%L where id=%L',(select v from _security_ids where k='limited'),(select v from _security_ids where k='mom')),'42501','client cannot create a second access path') $q$);
select security_case('recipient_link_cannot_survive_scope_revocation', $q$
 do $body$
 begin
   begin
     update care_recipients set linked_user_id=(select v from _security_ids where k='limited')
       where id=(select v from _security_ids where k='mom');
   exception when insufficient_privilege then null;
   end;
   perform act_as((select v from _security_ids where k='owner'));
   perform set_member_access((select v from _security_ids where k='g')::text,(select v from _security_ids where k='limited')::text,'listed','{}');
   perform act_as((select v from _security_ids where k='limited'));
   perform ok(not exists(select 1 from care_recipients where id=(select v from _security_ids where k='mom')),'revoked recipient must disappear despite a forged self link');
 end $body$ $q$);
select act_as((select v from _security_ids where k='subject'));
select security_case('dose_parent_cannot_write_into_foreign_circle', $q$
 select throws(format('insert into dose_logs(group_id,medication_id,scheduled_at,recorded_by) values(%L,%L,now(),%L)',(select v from _security_ids where k='foreign'),(select v from _security_ids where k='med'),(select v from _security_ids where k='subject')),'subject dose must stay in medication circle') $q$);
select act_as((select v from _security_ids where k='owner'));
select remove_member((select v from _security_ids where k='g')::text,(select v from _security_ids where k='helper')::text);
select act_as((select v from _security_ids where k='helper'));
select security_case('removed_member_cannot_reuse_cached_owner_code', $q$
 select ok(not (select ok from accept_invite((select v from _security_codes where k='open'))),'removed helper cannot reuse another owners cached code') $q$);
select act_as((select v from _security_ids where k='joiner'));
-- Clear only the caller's fixtures to isolate inviter validation from the swap.
reset role;
update group_members set removed_at=now() where group_id=(select v from _security_ids where k='solo');
insert into invite_codes(code,group_id,role_to_grant,care_recipient_id,created_by,expires_at)
select 'LEGACY22',(select v from _security_ids where k='g'),'caregiver',(select v from _security_ids where k='foreign_person'),(select v from _security_ids where k='owner'),now()+interval '1 day';
set role authenticated;
select security_case('legacy_invite_cannot_link_foreign_recipient', $q$
 select ok(not (select ok from accept_invite('LEGACY22')),'legacy malformed code must not link a foreign recipient') $q$);
select security_case('removed_inviter_code_cannot_restore_access', $q$
 select ok(not (select ok from accept_invite((select v from _security_codes where k='helper'))),'removed inviter code must be invalid') $q$);
reset role;
update group_members set removed_at=null,role='subject' where group_id=(select v from _security_ids where k='g') and user_id=(select v from _security_ids where k='helper');
set role authenticated;
select security_case('demoted_inviter_cannot_grant_caregiver', $q$
 select ok(not (select ok from accept_invite((select v from _security_codes where k='helper'))),'subject cannot grant a caregiver role through an old code') $q$);
select security_case('escalation_rpc_cannot_read_other_families', $q$
 select throws_code('select * from recipients_due_for_escalation()','42501','escalation RPC is service-only') $q$);
select security_case('recipient_probe_cannot_read_foreign_association', $q$
 select ok(not recipient_in_group((select v from _security_ids where k='foreign_person'),(select v from _security_ids where k='foreign')),'outsider must not learn recipient association') $q$);
select security_case('billing_probe_cannot_read_foreign_entitlement', $q$
 select ok(not group_has_plus((select v from _security_ids where k='foreign')),'outsider must not learn billing state') $q$);
-- Model a forged link that was stored before this migration was deployed.
reset role;
update care_recipients set linked_user_id=(select v from _security_ids where k='limited') where id=(select v from _security_ids where k='mom');
set role authenticated;
select act_as((select v from _security_ids where k='owner'));
select set_member_access((select v from _security_ids where k='g')::text,(select v from _security_ids where k='limited')::text,'listed','{}');
select act_as((select v from _security_ids where k='limited'));
select security_case('stored_self_link_cannot_bypass_recipient_scope', $q$
 select ok(not exists(select 1 from care_recipients where id=(select v from _security_ids where k='mom')),'a stored forged link must not bypass current recipient scope') $q$);
select act_as((select v from _security_ids where k='owner'));
insert into _security_codes select 'correct_email',generate_invite_code((select v from _security_ids where k='g')::text,'caregiver',null,'joiner@example.com');
select act_as((select v from _security_ids where k='joiner'));
select ok((select ok from accept_invite((select v from _security_codes where k='correct_email'))),'matching confirmed email can accept');
select ok((select ok from accept_invite((select v from _security_codes where k='correct_email'))),'a matching accepted invitation remains idempotent');
reset role;
select ok(not exists(select 1 from _security_results where not passed),
    (select string_agg(name,', ') from _security_results where not passed));
\echo 'Security boundaries: all assertions passed'
