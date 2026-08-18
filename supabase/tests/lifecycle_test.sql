-- Med List (Aging) — group lifecycle RPC tests.
--
-- The cases here are the ones Bond had to fix in production: cascades that
-- destroyed shared data on account deletion, groups left with no owner, invite
-- codes with no revocation path.

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create table _l (k text primary key, v uuid);
create table _lc (k text primary key, v text);
grant select, insert on _l, _lc to authenticated;

insert into _l (k, v) values
    ('sarah', public.make_user('Sarah')),
    ('mike',  public.make_user('Mike')),
    ('mom',   public.make_user('Mom')),
    ('kate',  public.make_user('Kate')),
    ('alex',  public.make_user('Alex')),
    ('solo',  public.make_user('Solo'));

set role authenticated;

-- ============================================================
\echo ''
\echo '-- create_group --'
select public.act_as((select v from _l where k = 'sarah'));

insert into _l (k, v) select 'g', public.create_group('Wallner');

select public.ok(
    (select role from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'sarah')) = 'owner',
    'create_group makes the creator the owner');

select public.ok(
    public.rows_visible('select 1 from public.groups') = 1,
    'the creator can see the group they just made');

select public.throws_code(
    'select public.create_group(''Another circle'')',
    '23505',
    'one account cannot create a second care circle');

-- The recipient rows the family will actually use.
insert into public.care_recipients (id, group_id, name, relationship)
values (gen_random_uuid(), (select v from _l where k = 'g'), 'Mom', 'Mom')
returning id \gset r_mom_
insert into _l (k, v) values ('r_mom', :'r_mom_id');

insert into public.medications (group_id, care_recipient_id, name, created_by, created_by_name)
values ((select v from _l where k = 'g'), (select v from _l where k = 'r_mom'),
        'Lisinopril', (select v from _l where k = 'sarah'), 'Sarah');

-- ============================================================
\echo ''
\echo '-- invites --'
insert into _lc (k, v)
select 'caregiver_code',
       public.generate_invite_code(
           (select v from _l where k = 'g')::text,
           'caregiver',
           null,
           'mike@example.com'
       );

select public.ok(
    (select intended_email from public.invite_codes
      where code = (select v from _lc where k = 'caregiver_code')) = 'mike@example.com',
    'an email-addressed invitation stores the normalized delivery address');

select public.ok(
    length((select v from _lc where k = 'caregiver_code')) = 8,
    'invite codes are 8 characters, short enough to read down the phone');

select public.ok(
    (select v from _lc where k = 'caregiver_code') !~ '[01OIL]',
    'invite codes avoid characters that get misheard as each other');

-- Mike joins as a caregiver.
select public.act_as((select v from _l where k = 'mike'));
select public.ok(
    (select ok from public.accept_invite((select v from _lc where k = 'caregiver_code'))),
    'a valid code is accepted');
select public.ok(
    (select role from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'mike')) = 'caregiver',
    'the invitee gets the role the invite granted');

-- Alex already owns another circle, so the same account cannot join this one.
select public.act_as((select v from _l where k = 'alex'));
insert into _l (k, v) select 'g_alex', public.create_group('Alex circle');
select public.act_as((select v from _l where k = 'sarah'));
insert into _lc (k, v)
select 'alex_code',
       public.generate_invite_code((select v from _l where k = 'g')::text, 'caregiver');
select public.act_as((select v from _l where k = 'alex'));
select public.ok(
    (select error_code from public.accept_invite(
        (select v from _lc where k = 'alex_code'))) = 'already_in_group',
    'an account in another care circle gets an actionable refusal');
select public.act_as((select v from _l where k = 'mike'));

-- Tapping the same invite twice must not be an error.
select public.ok(
    (select ok from public.accept_invite((select v from _lc where k = 'caregiver_code'))),
    'accepting an invite you already used is idempotent, not an error');

-- Mom joins as the subject, and is linked to the recipient row already built
-- for her, so her medication history is continuous.
select public.act_as((select v from _l where k = 'sarah'));
insert into _lc (k, v)
select 'subject_code',
       public.generate_invite_code((select v from _l where k = 'g')::text, 'subject',
                                   (select v from _l where k = 'r_mom')::text);

select public.act_as((select v from _l where k = 'mom'));
select public.ok(
    (select ok from public.accept_invite((select v from _lc where k = 'subject_code'))),
    'a subject invite is accepted');

select public.act_as((select v from _l where k = 'sarah'));
select public.ok(
    (select linked_user_id from public.care_recipients
      where id = (select v from _l where k = 'r_mom')) = (select v from _l where k = 'mom'),
    'accepting a subject invite links that account to the recipient row');

-- ============================================================
\echo ''
\echo '-- invite hardening --'
select public.act_as((select v from _l where k = 'kate'));

select public.ok(
    (select error_code from public.accept_invite('ZZZZZZZZ')) = 'invalid_code',
    'an unknown code is rejected');

select public.ok(
    (select error_code from public.accept_invite(
        (select v from _lc where k = 'caregiver_code'))) = 'invalid_code',
    'a code that has already been used is rejected');

-- Revocation, which Bond only added reactively in its 0011.
select public.act_as((select v from _l where k = 'sarah'));
insert into _lc (k, v)
select 'revoked_code',
       public.generate_invite_code((select v from _l where k = 'g')::text, 'caregiver');
select public.revoke_invite_code((select v from _lc where k = 'revoked_code'));

select public.act_as((select v from _l where k = 'kate'));
select public.ok(
    (select error_code from public.accept_invite(
        (select v from _lc where k = 'revoked_code'))) = 'invalid_code',
    'a revoked code is rejected');

-- Expiry.
reset role;
insert into public.invite_codes (code, group_id, role_to_grant, created_by, expires_at)
values ('EXPIRED1', (select v from _l where k = 'g'), 'caregiver',
        (select v from _l where k = 'sarah'), now() - interval '1 hour');
set role authenticated;
select public.act_as((select v from _l where k = 'kate'));
select public.ok(
    (select error_code from public.accept_invite('EXPIRED1')) = 'invalid_code',
    'an expired code is rejected');

-- Rate limiting. This is the assertion that caught the original design bug:
-- when accept_invite raised on a bad code, PostgREST rolled the whole
-- transaction back, the attempt row vanished, and the limiter counted nothing.
do $$
begin
    for i in 1..12 loop
        perform public.accept_invite('BADCODE' || i::text);
    end loop;
end;
$$;

select public.ok(
    (select error_code from public.accept_invite('ANOTHER1')) = 'rate_limited',
    'brute-forcing invite codes is rate limited, and the attempts actually persist');

select public.ok(
    public.rows_visible('select 1 from public.invite_attempts') = 0,
    'invite_attempts is invisible to clients');

-- Counted as the superuser: the table has RLS on with no policies at all, so a
-- client legitimately cannot see these rows.
reset role;
select public.ok(
    (select count(*) from public.invite_attempts
      where user_id = (select v from _l where k = 'kate')) >= 10,
    'failed attempts are recorded rather than rolled back');
set role authenticated;
select public.act_as((select v from _l where k = 'kate'));

-- A stranger cannot mint an invite to a group they are not in.
select public.throws(
    format('select public.generate_invite_code(%L, ''caregiver'')',
           (select v from _l where k = 'g')::text),
    'a non-member cannot generate an invite to somebody else''s group');

-- The role ceiling (0013). Before that migration this was enforced by nothing:
-- the check that claimed it asked `is_group_staff` a second time, which the
-- authorization gate above had already proved true. The rule survived only
-- because 'owner' was not in the allow-list, so the two cases below are what
-- keep it honest when someone widens that list.
select public.act_as((select v from _l where k = 'mike'));
select public.throws_code(
    format('select public.generate_invite_code(%L, ''owner'')',
           (select v from _l where k = 'g')::text),
    '42501',
    'a caregiver asking for an owner invite is refused on authorization, not on arguments');

select public.act_as((select v from _l where k = 'sarah'));
select public.throws_code(
    format('select public.generate_invite_code(%L, ''owner'')',
           (select v from _l where k = 'g')::text),
    '22023',
    'even an owner gets no owner invite in v1: the allow-list, not the ceiling, stops them');

select public.act_as((select v from _l where k = 'kate'));

-- ============================================================
\echo ''
\echo '-- roles --'
select public.act_as((select v from _l where k = 'mike'));
select public.throws(
    format('select public.change_role(%L, %L, ''owner'')',
           (select v from _l where k = 'g')::text, (select v from _l where k = 'mike')::text),
    'a caregiver cannot change roles');

select public.throws(
    format('select public.remove_member(%L, %L)',
           (select v from _l where k = 'g')::text, (select v from _l where k = 'sarah')::text),
    'a caregiver cannot remove the owner');

select public.act_as((select v from _l where k = 'sarah'));
select public.throws(
    format('select public.change_role(%L, %L, ''caregiver'')',
           (select v from _l where k = 'g')::text, (select v from _l where k = 'sarah')::text),
    'the last owner cannot demote themselves and orphan the group');

select public.throws(
    format('select public.leave_group(%L)', (select v from _l where k = 'g')::text),
    'the last owner cannot walk out and leave the group ownerless');

-- ============================================================
\echo ''
\echo '-- the subject can always leave --'
select public.act_as((select v from _l where k = 'mom'));
select public.leave_group((select v from _l where k = 'g')::text);

select public.act_as((select v from _l where k = 'sarah'));
select public.ok(
    (select removed_at is not null from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'mom')),
    'the subject can leave the group unilaterally');

select public.ok(
    (select linked_user_id is null from public.care_recipients
      where id = (select v from _l where k = 'r_mom')),
    'leaving unlinks the account from the recipient row');

select public.ok(
    public.rows_visible(format('select 1 from public.medications where care_recipient_id = %L',
                               (select v from _l where k = 'r_mom'))) = 1,
    'leaving does NOT delete the medication history the family depends on');

-- ============================================================
\echo ''
\echo '-- ownership transfer --'
select public.transfer_ownership((select v from _l where k = 'g')::text,
                                 (select v from _l where k = 'mike')::text);
select public.ok(
    (select role from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'mike')) = 'owner',
    'ownership transfers to the named member');
select public.ok(
    (select role from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'sarah')) = 'caregiver',
    'the previous owner is demoted to caregiver, not removed');

select public.leave_group((select v from _l where k = 'g')::text);
select public.ok(
    (select removed_at is not null from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'sarah')) is not false,
    'having transferred ownership, the old owner can leave');

-- ============================================================
\echo ''
\echo '-- account deletion (App Review 5.1.1(v)) --'
-- Kate joins so Mike has an heir.
select public.act_as((select v from _l where k = 'mike'));
insert into _lc (k, v)
select 'kate_code',
       public.generate_invite_code((select v from _l where k = 'g')::text, 'caregiver');
select public.act_as((select v from _l where k = 'kate'));
-- Kate is rate limited from the brute-force test above, so clear her attempts.
reset role;
delete from public.invite_attempts where user_id = (select v from _l where k = 'kate');
set role authenticated;
select public.ok(
    (select ok from public.accept_invite((select v from _lc where k = 'kate_code'))),
    'Kate joins as a caregiver');

-- Mike writes something before deleting his account, so we can check that what
-- he wrote survives him and still says he wrote it.
select public.act_as((select v from _l where k = 'mike'));
insert into public.medications (group_id, care_recipient_id, name, created_by, created_by_name)
values ((select v from _l where k = 'g'), (select v from _l where k = 'r_mom'),
        'Metformin', (select v from _l where k = 'mike'), 'Mike');

select public.delete_account();

select public.act_as((select v from _l where k = 'kate'));
select public.ok(
    (select role from public.group_members
      where group_id = (select v from _l where k = 'g')
        and user_id  = (select v from _l where k = 'kate')) = 'owner',
    'deleting the last owner''s account promotes the longest-tenured caregiver');

select public.ok(
    public.rows_visible('select 1 from public.medications') = 2,
    'the family medical history survives an account deletion');

select public.ok(
    (select created_by is null and created_by_name = 'Mike'
       from public.medications where name = 'Metformin'),
    'authored rows keep the name snapshot after the author''s account is gone');

select public.ok(
    (select created_by_name from public.medications where name = 'Lisinopril') = 'Sarah',
    'rows authored by a member who merely left are untouched');

reset role;
select public.ok(
    (select count(*) from public.audit_log
      where table_name = 'group_members' and operation = 'delete') > 0,
    'the account deletion is recorded in the audit log rather than failing on it');
set role authenticated;
select public.act_as((select v from _l where k = 'kate'));

-- ============================================================
\echo ''
\echo '-- the solo caregiver, who never invites anyone --'
select public.act_as((select v from _l where k = 'solo'));
insert into _l (k, v) select 'g_solo', public.create_group('Just me');
insert into public.care_recipients (group_id, name) values ((select v from _l where k = 'g_solo'), 'Dad');

select public.ok(
    public.rows_visible('select 1 from public.care_recipients') = 1,
    'a group of one works with no invites at all');

select public.delete_account();
reset role;
select public.ok(
    (select count(*) from public.groups where id = (select v from _l where k = 'g_solo')) = 0,
    'deleting the only member deletes the group, since nothing is shared with anyone');

\echo ''
\echo 'Lifecycle: all assertions passed'
