-- Check-in notices carry care data. Scope both reads and push delivery to the
-- recipient, and fail closed for historical notices without a recipient id.
alter table public.group_notices
    add column care_recipient_id uuid references public.care_recipients(id) on delete cascade;
create index group_notices_recipient_idx on public.group_notices(care_recipient_id)
    where care_recipient_id is not null;

alter policy group_notices_member_select on public.group_notices
    using (
        public.is_unrestricted_staff(group_id)
        or (
            public.is_group_staff(group_id)
            and public.recipient_in_group(care_recipient_id, group_id)
        )
    );

create or replace function public.queue_check_in_notices()
returns int
language plpgsql security definer set search_path = public
as $$
declare
    v_count int := 0;
begin
    with due as (
        select * from public.recipients_due_for_escalation()
    ), stamped as (
        update public.check_in_settings s
           set last_escalated_on = d.local_date
          from due d
         where s.care_recipient_id = d.care_recipient_id
        returning s.care_recipient_id, s.group_id
    )
    insert into public.group_notices
        (group_id, care_recipient_id, kind, title, body, subject_name)
    select d.group_id, d.care_recipient_id, 'no_check_in', 'No check-in today',
           d.recipient_name || ' has not checked in today.', d.recipient_name
      from due d
      join stamped st on st.care_recipient_id = d.care_recipient_id;

    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

create or replace function public.pending_notices_with_targets()
returns table (notice_id uuid, title text, body text, apns_token text)
language sql stable security definer set search_path = public
as $$
    select n.id, n.title, n.body, p.apns_token
      from public.group_notices n
      join public.group_members m
        on m.group_id = n.group_id
       and m.removed_at is null
       and m.role in ('owner', 'caregiver')
       and (n.exclude_user is null or m.user_id <> n.exclude_user)
       and (
           m.role = 'owner' or m.access_scope = 'all'
           or exists (
               select 1 from public.recipient_access ra
               join public.care_recipients cr
                 on cr.id = ra.care_recipient_id and cr.group_id = ra.group_id
              where ra.group_id = n.group_id and ra.user_id = m.user_id
                and ra.care_recipient_id = n.care_recipient_id
           )
       )
      join public.profiles p on p.id = m.user_id and p.apns_token is not null
     where n.delivered_at is null
       and n.created_at > now() - interval '2 days';
$$;

-- Replacements preserve ACLs, and restate the service boundary explicitly.
revoke all on function public.queue_check_in_notices() from public, anon, authenticated;
revoke all on function public.pending_notices_with_targets() from public, anon, authenticated;
grant execute on function public.queue_check_in_notices() to service_role;
grant execute on function public.pending_notices_with_targets() to service_role;

-- A solo-circle swap must not delete a circle that gained a member after
-- the empty-circle check. Preserve the 0022 grant and email validations.
create or replace function public.accept_invite(p_code text)
returns table (ok boolean, joined_group_id uuid, error_code text)
language plpgsql
security definer set search_path = public
as $$
declare
    v_uid       uuid := (select auth.uid());
    v_code      text := upper(trim(p_code));
    v_invite    public.invite_codes%rowtype;
    v_recent    int;
    v_own_group uuid;
    v_target_group uuid;
    v_others    int;
    v_untouched boolean;
begin
    if v_uid is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;

    select count(*) into v_recent
      from public.invite_attempts
     where user_id = v_uid
       and attempted_at > now() - interval '1 hour';

    if v_recent >= 10 then
        return query select false, null::uuid, 'rate_limited'::text;
        return;
    end if;

    insert into public.invite_attempts (user_id) values (v_uid);

    -- Lock both circles before locking the code or inspecting members/data.
    -- FK checks make concurrent joins and inserts wait here. Sorting avoids
    -- deadlocks between two circles swapping at the same time.
    select group_id into v_target_group from public.invite_codes where code = v_code;
    if v_target_group is null then
        return query select false, null::uuid, 'invalid_code'::text;
        return;
    end if;

    select gm.group_id into v_own_group
      from public.group_members gm
     where gm.user_id = v_uid and gm.removed_at is null
     limit 1;

    perform 1 from public.groups
     where id in (v_own_group, v_target_group)
     order by id for update;

    select * into v_invite
      from public.invite_codes
     where code = v_code
       for update;

    if v_invite.code is null or v_invite.group_id <> v_target_group then
        return query select false, null::uuid, 'invalid_code'::text;
        return;
    end if;

    -- Already in the circle this code opens. Idempotent on purpose: a second
    -- tap on the same link is not an error.
    if exists (
        select 1 from public.group_members
         where group_members.group_id = v_invite.group_id
           and user_id = v_uid
           and removed_at is null
    ) then
        update public.invite_attempts set succeeded = true
         where id = (select max(id) from public.invite_attempts where user_id = v_uid);
        return query select true, v_invite.group_id, null::text;
        return;
    end if;

    -- Validate every grant before closing the caller's onboarding circle.
    -- Read the authenticated user's server-side email, never user metadata.
    if v_invite.used_at is not null or v_invite.revoked_at is not null
       or v_invite.expires_at <= now()
       or exists (
           select 1 from public.group_members gm
            where gm.group_id = v_invite.group_id and gm.user_id = v_uid
              and gm.removed_at is not null and v_invite.created_at <= gm.removed_at
       )
       or (v_invite.intended_email is not null and not exists (
           select 1 from auth.users u where u.id = v_uid
             and lower(trim(u.email)) = v_invite.intended_email
             and u.email_confirmed_at is not null
       ))
       or not exists (
           select 1 from public.group_members gm
            where gm.group_id = v_invite.group_id and gm.user_id = v_invite.created_by
              and gm.removed_at is null and gm.role in ('owner', 'caregiver')
              and (gm.role = 'owner' or gm.access_scope = 'all')
       )
       or (v_invite.care_recipient_id is not null and (
           v_invite.role_to_grant <> 'subject' or not exists (
               select 1 from public.care_recipients cr
                where cr.id = v_invite.care_recipient_id and cr.group_id = v_invite.group_id
                  and cr.deleted_at is null
                  and (cr.linked_user_id is null or cr.linked_user_id = v_uid)
           )
       )) then
        return query select false, null::uuid, 'invalid_code'::text;
        return;
    end if;

    -- Another request may have moved the caller while the circle locks waited.
    -- Never close a circle that was not included in the locks above.
    if exists (select 1 from public.group_members gm
                where gm.user_id = v_uid and gm.removed_at is null
                  and gm.group_id is distinct from v_own_group) then
        return query select false, null::uuid, 'already_in_group'::text;
        return;
    end if;

    if v_own_group is not null then
        -- Only ever their own circle, and only while nobody else is in it.
        if not exists (
            select 1 from public.group_members
             where group_id = v_own_group
               and user_id = v_uid
               and role = 'owner'
               and removed_at is null
        ) then
            return query select false, null::uuid, 'already_in_group'::text;
            return;
        end if;

        select count(*) into v_others
          from public.group_members
         where group_id = v_own_group
           and user_id <> v_uid
           and removed_at is null;

        if v_others > 0 then
            return query select false, null::uuid, 'already_in_group'::text;
            return;
        end if;

        select
            (select count(*) from public.care_recipients    where group_id = v_own_group) <= 1
        and not exists (select 1 from public.check_ins         where group_id = v_own_group)
        and not exists (select 1 from public.check_in_settings where group_id = v_own_group)
        and not exists (select 1 from public.medications        where group_id = v_own_group)
        and not exists (select 1 from public.dose_logs          where group_id = v_own_group)
        and not exists (select 1 from public.visits             where group_id = v_own_group)
        and not exists (select 1 from public.vital_readings     where group_id = v_own_group)
        and not exists (select 1 from public.emergency_contacts where group_id = v_own_group)
        and not exists (select 1 from public.providers          where group_id = v_own_group)
        and not exists (select 1 from public.care_events        where group_id = v_own_group)
        and not exists (select 1 from public.care_notes         where group_id = v_own_group)
        and not exists (select 1 from public.bills              where group_id = v_own_group)
          into v_untouched;

        if not v_untouched then
            return query select false, null::uuid, 'already_in_group'::text;
            return;
        end if;
    end if;

    -- The code itself is checked only after the membership questions, so a
    -- circle is never closed for an invitation that was never going to work.
    if v_invite.used_at is not null
       or v_invite.revoked_at is not null
       or v_invite.expires_at <= now() then
        return query select false, null::uuid, 'invalid_code'::text;
        return;
    end if;

    if v_own_group is not null then
        -- audit_log has no FK to groups (0006), so it is cleared by hand here
        -- for the same reason delete_group does it by hand.
        delete from public.audit_log where group_id = v_own_group;
        delete from public.groups where id = v_own_group;
    end if;

    insert into public.group_members (group_id, user_id, role, invited_by)
    values (v_invite.group_id, v_uid, v_invite.role_to_grant, v_invite.created_by)
    on conflict (group_id, user_id) do update
        set role = excluded.role,
            removed_at = null,
            invited_by = excluded.invited_by;

    if v_invite.care_recipient_id is not null then
        update public.care_recipients
           set linked_user_id = v_uid
         where id = v_invite.care_recipient_id
           and linked_user_id is null;
    end if;

    update public.invite_codes
       set used_at = now(), used_by = v_uid
     where code = v_code;

    update public.invite_attempts set succeeded = true
     where id = (select max(id) from public.invite_attempts where user_id = v_uid);

    return query select true, v_invite.group_id, null::text;
end;
$$;

notify pgrst, 'reload schema';
