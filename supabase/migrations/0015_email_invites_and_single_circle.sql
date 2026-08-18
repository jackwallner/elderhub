-- Elderhub uses one care circle per account. A circle can hold any number of
-- care recipients, so Mom and Dad belong in one shared record rather than in
-- separate groups with an ambiguous active membership.

alter table public.invite_codes
    add column intended_email text;

alter table public.invite_codes
    add constraint invite_email_is_normalized
    check (
        intended_email is null
        or (
            intended_email = lower(trim(intended_email))
            and intended_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
        )
    );

create or replace function public.create_group(p_name text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    v_uid      uuid := (select auth.uid());
    v_group_id uuid;
begin
    if v_uid is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;

    if exists (
        select 1
          from public.group_members
         where user_id = v_uid
           and removed_at is null
    ) then
        raise exception 'this account already belongs to a care circle'
            using errcode = '23505';
    end if;

    insert into public.groups (name, created_by)
    values (coalesce(nullif(trim(p_name), ''), 'Care circle'), v_uid)
    returning id into v_group_id;

    insert into public.group_members (group_id, user_id, role)
    values (v_group_id, v_uid, 'owner');

    return v_group_id;
end;
$$;

drop function public.generate_invite_code(text, text, text, int);

create function public.generate_invite_code(
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
    if not public.is_group_staff(v_group_id) then
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

grant execute on function public.generate_invite_code(text, text, text, text, int)
    to authenticated;

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

    if exists (
        select 1 from public.group_members
         where user_id = v_uid
           and removed_at is null
    ) then
        return query select false, null::uuid, 'already_in_group'::text;
        return;
    end if;

    if v_invite.used_at is not null
       or v_invite.revoked_at is not null
       or v_invite.expires_at <= now() then
        return query select false, null::uuid, 'invalid_code'::text;
        return;
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
