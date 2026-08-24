-- One account belongs to one care circle (0015). The rule is right, but the
-- refusal it produces was a dead end: someone who signs in, taps "Start a care
-- record" and only then gets read an invite code over the phone is told
-- "already_in_group" and has nowhere to go from that screen. Every joiner who
-- did not happen to pick "I have an invitation" first hit it, which is the
-- failure the app exists to avoid: the family cannot get into the record.
--
-- The dead end is only real when the circle they are stuck in has other people
-- in it. A sole owner is one step away from where they were trying to go, so
-- accept_invite now takes that step for them: their own circle is closed, on
-- exactly the terms `delete_group` already offers a solo owner in the app, and
-- the invite is accepted.
--
-- Fixing it here rather than in the client is deliberate. The build in the
-- store cannot be changed and prints the refusal with no way past it; a server
-- fix reaches those installs today.
--
-- Nothing of theirs is carried across. Uploading the record they started into
-- the circle they just joined would be a disclosure, not a migration (I5), so
-- the closed circle's shared rows go with it and whatever their phone keeps
-- locally stays local.
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

    -- In some other circle. Closing it is only ever offered when they own it
    -- and nobody else is in it; anything else is somebody else's record and
    -- the refusal stands.
    select gm.group_id into v_own_group
      from public.group_members gm
     where gm.user_id = v_uid
       and gm.removed_at is null
     limit 1;

    if v_own_group is not null then
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
