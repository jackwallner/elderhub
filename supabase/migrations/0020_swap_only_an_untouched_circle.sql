-- 0019 lets accept_invite close a solo owner's circle so the invitation can be
-- taken. That is right for the case it was written for (someone one minute into
-- onboarding who tapped "Start a care record" before the code was read out to
-- them) and much too broad for the case it also caught: a caregiver who has
-- kept Mom's whole record on their own for months, then joins a sibling's
-- circle, would have had the shared copy of it deleted by typing eight
-- characters, with no question asked and no way back.
--
-- So the swap now only happens to a circle that has nothing in it yet: at most
-- the one care recipient onboarding creates, and none of the record itself.
-- Anyone past that keeps the refusal and closes their circle deliberately, from
-- Sharing, where the app says what goes with it.
--
-- Tasks are not in the list on purpose. A to-do somebody typed on their first
-- screen is not a medical record, and counting it would put the original dead
-- end back for the exact person this is for.
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

    select * into v_invite
      from public.invite_codes
     where code = v_code
       for update;

    if v_invite.code is null then
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

    select gm.group_id into v_own_group
      from public.group_members gm
     where gm.user_id = v_uid
       and gm.removed_at is null
     limit 1;

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
