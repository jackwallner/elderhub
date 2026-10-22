-- Enforce invite, recipient and tenant boundaries at the database.
-- Existing migrations are intentionally unchanged.

-- The escalation worker can read across circles. Clients cannot invoke it.
revoke all on function public.recipients_due_for_escalation() from public, anon, authenticated;
grant execute on function public.recipients_due_for_escalation() to service_role;

create or replace function public.recipient_in_group(p_recipient_id uuid, p_group_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
    select public.is_group_member(p_group_id)
       and exists (select 1 from public.care_recipients
                    where id = p_recipient_id and group_id = p_group_id)
       and p_recipient_id in (select public.visible_recipient_ids());
$$;

-- A stored link is not an independent grant to a restricted caregiver.
-- This also closes links forged before the client-write guard was installed.
create or replace function public.is_my_recipient(p_recipient_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.care_recipients cr
        join public.group_members gm on gm.group_id = cr.group_id
          and gm.user_id = cr.linked_user_id and gm.removed_at is null
        where cr.id = p_recipient_id and cr.linked_user_id = (select auth.uid())
          and (gm.role in ('owner', 'subject') or gm.access_scope = 'all'
               or exists (select 1 from public.recipient_access ra
                           where ra.group_id = cr.group_id and ra.care_recipient_id = cr.id
                             and ra.user_id = gm.user_id))
    );
$$;

create or replace function public.medication_is_mine(p_medication_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
    select exists (select 1 from public.medications m
        join public.care_recipients cr on cr.id = m.care_recipient_id and cr.group_id = m.group_id
        where m.id = p_medication_id and public.is_my_recipient(cr.id));
$$;

alter policy care_recipients_subject_self_select on public.care_recipients
    using (public.is_my_recipient(id));

create or replace function public.visible_recipient_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
    -- Unrestricted staff, and every owner regardless of the stored flag.
    select cr.id
      from public.care_recipients cr
      join public.group_members gm on gm.group_id = cr.group_id
     where gm.user_id = (select auth.uid())
       and gm.removed_at is null
       and gm.role in ('owner', 'caregiver')
       and (gm.access_scope = 'all' or gm.role = 'owner')

    union

    -- Members restricted to a list see exactly what they were granted, and only
    -- while their membership is live: removing someone must not leave their
    -- grants standing.
    select ra.care_recipient_id
      from public.recipient_access ra
      join public.group_members gm
        on gm.group_id = ra.group_id
       and gm.user_id  = ra.user_id
     where ra.user_id = (select auth.uid())
       and gm.removed_at is null
       and gm.role in ('owner', 'caregiver')
       and gm.access_scope = 'listed'

    union

    -- A linked record still requires live membership. Restricted caregivers
    -- follow their current grants even when a link predates this migration.
    select cr.id
      from public.care_recipients cr
     where cr.linked_user_id = (select auth.uid())
       and public.is_my_recipient(cr.id)
$$;


create or replace function public.group_has_plus(p_group_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
    select public.is_group_member(p_group_id)
       and exists (select 1 from public.group_billing
                    where group_id = p_group_id and entitlement = 'plus'
                      and (is_lifetime or expires_at > now()));
$$;

-- Codes grant circle-wide access. Restricted helpers must not receive them.
alter policy invite_codes_staff_select on public.invite_codes
    using (public.is_unrestricted_staff(group_id));
-- Audit JSON contains full medical rows. Keep it with unrestricted staff.
alter policy audit_log_staff_select on public.audit_log
    using (public.is_unrestricted_staff(group_id));

-- Linking is a lifecycle operation performed by accept_invite/remove_member.
-- An ordinary sync may echo an unchanged link, but cannot establish one.
create function public.protect_recipient_link()
returns trigger language plpgsql set search_path = public
as $$
begin
    if current_user in ('authenticated', 'anon') then
        if (tg_op = 'INSERT' and new.linked_user_id is not null)
           or (tg_op = 'UPDATE' and new.linked_user_id is distinct from old.linked_user_id) then
            raise exception 'recipient links must use an invitation' using errcode = '42501';
        end if;
    end if;
    return new;
end;
$$;
create trigger care_recipients_protect_link before insert or update on public.care_recipients
    for each row execute function public.protect_recipient_link();

-- A subject's dose policy used the medication but did not check group_id.
-- The composite key enforces the same tenant on every insert and update.
alter table public.medications add constraint medications_id_group_unique unique(id, group_id);
alter table public.dose_logs add constraint dose_logs_medication_group_fk
    foreign key (medication_id, group_id) references public.medications(id, group_id)
    on delete cascade not valid;
-- NOT VALID preserves any pre-existing inconsistent rows for owner review;
-- new writes and updates are checked immediately. Hide inconsistent old rows.
create policy dose_logs_parent_group_guard on public.dose_logs as restrictive
    for all to authenticated
    using (exists (select 1 from public.medications m
                    where m.id = medication_id and m.group_id = dose_logs.group_id))
    with check (exists (select 1 from public.medications m
                         where m.id = medication_id and m.group_id = dose_logs.group_id));

create or replace function public.generate_invite_code(
    p_group_id          text,
    p_role              text,
    p_care_recipient_id text default null,
    p_email             text default null,
    p_ttl_hours         int  default 48
)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id     uuid := p_group_id::uuid;
    v_recipient_id uuid := nullif(p_care_recipient_id, '')::uuid;
    v_email        text := nullif(lower(trim(p_email)), '');
    v_uid          uuid := (select auth.uid());
    v_name         text;
    v_code         text;
    v_tries        int := 0;
begin
    if not public.is_unrestricted_staff(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    if p_role = 'owner' and not public.is_group_owner(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    if p_role not in ('caregiver', 'subject') then
        raise exception 'invalid role' using errcode = '22023';
    end if;

    if v_email is not null
       and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'invalid email address' using errcode = '22023';
    end if;

    if p_role <> 'subject' and v_recipient_id is not null then
        raise exception 'only subject invites may link a recipient' using errcode = '22023';
    end if;

    if p_role = 'subject' then
        if v_recipient_id is null then
            raise exception 'subject invite requires a care recipient' using errcode = '22023';
        end if;
        if not public.recipient_in_group(v_recipient_id, v_group_id) then
            raise exception 'recipient not in this group' using errcode = '22023';
        end if;
    end if;

    select display_name into v_name from public.profiles where id = v_uid;

    loop
        v_tries := v_tries + 1;
        v_code := public.random_invite_code();
        exit when not exists (select 1 from public.invite_codes where code = v_code);
        if v_tries > 20 then
            raise exception 'could not allocate an invite code';
        end if;
    end loop;

    insert into public.invite_codes (
        code, group_id, role_to_grant, care_recipient_id, intended_email,
        created_by, created_by_name, expires_at
    )
    values (
        v_code, v_group_id, p_role, v_recipient_id, v_email,
        v_uid, coalesce(v_name, ''), now() + make_interval(hours => greatest(p_ttl_hours, 1))
    );

    return v_code;
end;
$$;


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
