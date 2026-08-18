-- Med List (Aging) — invites and group lifecycle.
--
-- Every mutation in this file is a security-definer RPC rather than an
-- RLS-guarded table write. That is not ceremony: group_members has no client
-- insert or update policy at all, because a single unguarded PATCH would let a
-- member promote themselves to owner. Bond's migration history (0004 to 0009,
-- 0008 to 0010) is what happens when lifecycle logic lives in cascades and
-- table policies instead of in one auditable function.
--
-- Every parameter is `text` and cast to uuid inside the body. PostgREST cannot
-- always choose between a (uuid) and a (text) overload when a Swift client
-- sends a UUID as a JSON string, and Bond hit exactly that (PGRST203).

-- ============================================================
-- Invite codes
-- ============================================================
create table public.invite_codes (
    code              text primary key,
    group_id          uuid not null references public.groups(id) on delete cascade,
    role_to_grant     text not null check (role_to_grant in ('caregiver', 'subject')),
    -- For a 'subject' invite: the recipient row this person will be linked to,
    -- so Mom is joined to the profile the family already built for her rather
    -- than arriving as an unattached member.
    care_recipient_id uuid references public.care_recipients(id) on delete cascade,
    created_by        uuid not null references public.profiles(id) on delete cascade,
    created_by_name   text not null default '',
    expires_at        timestamptz not null,
    used_at           timestamptz,
    used_by           uuid references public.profiles(id) on delete set null,
    revoked_at        timestamptz,
    created_at        timestamptz not null default now(),
    constraint invite_subject_needs_recipient
        check (role_to_grant <> 'subject' or care_recipient_id is not null)
);

create index invite_codes_group_idx on public.invite_codes(group_id);

alter table public.invite_codes enable row level security;

create policy "invite_codes_staff_select"
    on public.invite_codes for select
    using (public.is_group_staff(group_id));

-- No insert/update/delete policies: created by generate_invite_code(),
-- consumed by accept_invite(), revoked by revoke_invite_code().

-- Consumption attempts, for rate limiting. Supabase's platform rate limits
-- cover GoTrue endpoints, not custom RPCs going through PostgREST, so an
-- unthrottled accept_invite() is brute-forceable against an 8-character code.
create table public.invite_attempts (
    id           bigserial primary key,
    user_id      uuid not null references public.profiles(id) on delete cascade,
    attempted_at timestamptz not null default now(),
    succeeded    boolean not null default false
);

create index invite_attempts_user_idx on public.invite_attempts(user_id, attempted_at desc);

alter table public.invite_attempts enable row level security;
-- No policies at all: written only by accept_invite(), read only by the
-- service role.

-- ============================================================
-- create_group
-- ============================================================
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

    insert into public.groups (name, created_by)
    values (coalesce(nullif(trim(p_name), ''), 'Family'), v_uid)
    returning id into v_group_id;

    insert into public.group_members (group_id, user_id, role)
    values (v_group_id, v_uid, 'owner');

    return v_group_id;
end;
$$;

-- ============================================================
-- generate_invite_code
-- ============================================================
-- Alphabet excludes 0/O/1/I/L: these codes get read aloud over the phone to a
-- 78-year-old, which is the actual delivery mechanism.
create or replace function public.random_invite_code()
returns text
language sql volatile
as $$
    select string_agg(
        substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
               (floor(random() * 31) + 1)::int, 1),
        ''
    )
    from generate_series(1, 8);
$$;

create or replace function public.generate_invite_code(
    p_group_id          text,
    p_role              text,
    p_care_recipient_id text default null,
    p_ttl_hours         int  default 48
)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id     uuid := p_group_id::uuid;
    v_recipient_id uuid := nullif(p_care_recipient_id, '')::uuid;
    v_uid          uuid := (select auth.uid());
    v_name         text;
    v_code         text;
    v_tries        int := 0;
begin
    if not public.is_group_staff(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    if p_role not in ('caregiver', 'subject') then
        raise exception 'invalid role' using errcode = '22023';
    end if;

    -- A caregiver may invite at or below their own level; only an owner can
    -- create another owner, and owner invites are not offered at all in v1.
    if p_role = 'caregiver' and not public.is_group_staff(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
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
        code, group_id, role_to_grant, care_recipient_id,
        created_by, created_by_name, expires_at
    )
    values (
        v_code, v_group_id, p_role, v_recipient_id,
        v_uid, coalesce(v_name, ''), now() + make_interval(hours => greatest(p_ttl_hours, 1))
    );

    return v_code;
end;
$$;

-- ============================================================
-- revoke_invite_code
-- ============================================================
create or replace function public.revoke_invite_code(p_code text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid;
begin
    select group_id into v_group_id from public.invite_codes where code = upper(trim(p_code));
    if v_group_id is null then
        return;
    end if;
    if not public.is_group_staff(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    update public.invite_codes
       set revoked_at = now()
     where code = upper(trim(p_code)) and revoked_at is null;
end;
$$;

-- ============================================================
-- accept_invite
-- ============================================================
-- Returns a result row rather than raising on a bad code, and this is
-- load-bearing rather than a style choice.
--
-- PostgREST runs each RPC in its own transaction. If this function raised on an
-- invalid code, the `invite_attempts` row written moments earlier would roll
-- back with it, and the rate limiter would count nothing and stop nobody. The
-- attempt has to survive the failure to be worth recording, so failure has to
-- be a return value. Postgres has no autonomous transactions to reach for here.
--
-- Genuine programming errors (no session) still raise.
create or replace function public.accept_invite(p_code text)
-- OUT parameters are named to avoid colliding with column names inside the
-- body: a plain `group_id` OUT param shadows group_members.group_id and makes
-- every unqualified reference ambiguous.
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

    -- Recorded before the lookup, so a wrong guess still costs an attempt.
    insert into public.invite_attempts (user_id) values (v_uid);

    select * into v_invite
      from public.invite_codes
     where code = v_code
       for update;

    if v_invite.code is null then
        return query select false, null::uuid, 'invalid_code'::text;
        return;
    end if;

    -- Membership is checked BEFORE the used/expired/revoked checks, on purpose.
    -- Tapping the same invite link twice is the single most likely thing a user
    -- does, and the second tap consults a code this function itself just marked
    -- used. Landing them in the group they are already in is the correct answer;
    -- a red "invalid code" screen would be a bug that reads like a policy.
    if exists (
        select 1 from public.group_members
        where group_members.group_id = v_invite.group_id
          and user_id = v_uid and removed_at is null
    ) then
        update public.invite_attempts set succeeded = true
         where id = (select max(id) from public.invite_attempts where user_id = v_uid);
        return query select true, v_invite.group_id, null::text;
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

    -- A subject invite links this account to the recipient row the family
    -- already created, so Mom's history is continuous rather than starting over.
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

-- ============================================================
-- change_role
-- ============================================================
create or replace function public.change_role(
    p_group_id text,
    p_user_id  text,
    p_role     text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
    v_user_id  uuid := p_user_id::uuid;
    v_uid      uuid := (select auth.uid());
    v_owners   int;
begin
    if not public.is_group_owner(v_group_id) then
        raise exception 'only an owner can change roles' using errcode = '42501';
    end if;
    if p_role not in ('owner', 'caregiver', 'subject') then
        raise exception 'invalid role' using errcode = '22023';
    end if;

    -- Never leave the group ownerless by demoting the last owner.
    if v_user_id = v_uid and p_role <> 'owner' then
        select count(*) into v_owners
          from public.group_members
         where group_id = v_group_id and role = 'owner' and removed_at is null;
        if v_owners <= 1 then
            raise exception 'transfer ownership before giving up the owner role'
                using errcode = '23514';
        end if;
    end if;

    update public.group_members
       set role = p_role
     where group_id = v_group_id and user_id = v_user_id and removed_at is null;

    if not found then
        raise exception 'member not found' using errcode = '22023';
    end if;
end;
$$;

-- ============================================================
-- remove_member
-- ============================================================
create or replace function public.remove_member(p_group_id text, p_user_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
    v_user_id  uuid := p_user_id::uuid;
    v_uid      uuid := (select auth.uid());
begin
    if not public.is_group_owner(v_group_id) then
        raise exception 'only an owner can remove members' using errcode = '42501';
    end if;
    if v_user_id = v_uid then
        raise exception 'use leave_group to remove yourself' using errcode = '22023';
    end if;

    update public.group_members
       set removed_at = now()
     where group_id = v_group_id and user_id = v_user_id and removed_at is null;

    -- Unlink them from any recipient row, but never delete the row: the
    -- medical history on it belongs to the family, not to the departing member.
    update public.care_recipients
       set linked_user_id = null
     where group_id = v_group_id and linked_user_id = v_user_id;
end;
$$;

-- ============================================================
-- transfer_ownership
-- ============================================================
create or replace function public.transfer_ownership(p_group_id text, p_new_owner_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
    v_new      uuid := p_new_owner_id::uuid;
    v_uid      uuid := (select auth.uid());
begin
    if not public.is_group_owner(v_group_id) then
        raise exception 'only an owner can transfer ownership' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.group_members
        where group_id = v_group_id and user_id = v_new and removed_at is null
    ) then
        raise exception 'member not found' using errcode = '22023';
    end if;

    update public.group_members set role = 'owner'
     where group_id = v_group_id and user_id = v_new;

    update public.group_members set role = 'caregiver'
     where group_id = v_group_id and user_id = v_uid;
end;
$$;

-- ============================================================
-- leave_group
--
-- The subject can always use this. Leaving is deliberately not blocked: an app
-- a parent cannot walk away from is a surveillance tool their children
-- installed on them. The safety net is that leaving is announced loudly to the
-- group (the notification is sent by the client and by the escalation function),
-- not that the door is locked.
-- ============================================================
create or replace function public.leave_group(p_group_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
    v_uid      uuid := (select auth.uid());
    v_role     text;
    v_owners   int;
    v_others   int;
begin
    select role into v_role
      from public.group_members
     where group_id = v_group_id and user_id = v_uid and removed_at is null;

    if v_role is null then
        raise exception 'not a member' using errcode = '22023';
    end if;

    select count(*) into v_others
      from public.group_members
     where group_id = v_group_id and user_id <> v_uid and removed_at is null;

    if v_role = 'owner' and v_others > 0 then
        select count(*) into v_owners
          from public.group_members
         where group_id = v_group_id and role = 'owner' and removed_at is null;
        if v_owners <= 1 then
            raise exception 'transfer ownership before leaving' using errcode = '23514';
        end if;
    end if;

    update public.group_members
       set removed_at = now()
     where group_id = v_group_id and user_id = v_uid;

    update public.care_recipients
       set linked_user_id = null
     where group_id = v_group_id and linked_user_id = v_uid;

    -- Last person out turns off the lights. Nothing is shared any more, so
    -- there is no history to preserve for anyone else.
    if v_others = 0 then
        delete from public.audit_log where group_id = v_group_id;
        delete from public.groups where id = v_group_id;
    end if;
end;
$$;

-- ============================================================
-- delete_group
-- ============================================================
create or replace function public.delete_group(p_group_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
begin
    if not public.is_group_owner(v_group_id) then
        raise exception 'only an owner can delete a group' using errcode = '42501';
    end if;
    -- audit_log has no FK to groups on purpose (see 0006), so it is cleaned up
    -- here rather than by a cascade that would deadlock against its own trigger.
    delete from public.audit_log where group_id = v_group_id;
    delete from public.groups where id = v_group_id;
end;
$$;

-- ============================================================
-- delete_account (App Review 5.1.1(v))
--
-- Deletes the account. Does NOT delete the family's medical history: rows this
-- user authored keep their *_by_name snapshot and drop their FK to null, so
-- "logged by Sarah" survives Sarah deleting her account.
-- ============================================================
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public, auth
as $$
declare
    v_uid   uuid := (select auth.uid());
    v_group record;
    v_heir  uuid;
    v_name  text;
begin
    if v_uid is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;

    -- Stash the display name before anything is deleted. The audit trigger
    -- fires on the cascade into group_members, by which point the profile row
    -- it would otherwise read is already gone.
    select coalesce(display_name, '') into v_name from public.profiles where id = v_uid;
    perform set_config('app.actor_name', coalesce(v_name, ''), true);

    -- Hand off, or clean up, every group this user owns.
    for v_group in
        select gm.group_id
          from public.group_members gm
         where gm.user_id = v_uid and gm.role = 'owner' and gm.removed_at is null
    loop
        -- Prefer the longest-tenured caregiver. Falling back to any remaining
        -- member (including a subject) is deliberate: a group left with no
        -- owner can never be administered again, which is worse than a subject
        -- owning the group that tracks them.
        select user_id into v_heir
          from public.group_members
         where group_id = v_group.group_id
           and user_id <> v_uid
           and removed_at is null
         order by (role = 'caregiver') desc, joined_at asc
         limit 1;

        if v_heir is not null then
            update public.group_members set role = 'owner'
             where group_id = v_group.group_id and user_id = v_heir;
        else
            delete from public.audit_log where group_id = v_group.group_id;
            delete from public.groups where id = v_group.group_id;
        end if;
    end loop;

    update public.care_recipients
       set linked_user_id = null
     where linked_user_id = v_uid;

    -- Cascades to public.profiles, which cascades to group_members. Authored
    -- rows survive because every created_by/updated_by is `on delete set null`.
    delete from auth.users where id = v_uid;
end;
$$;

grant execute on function public.create_group(text)                          to authenticated;
grant execute on function public.generate_invite_code(text, text, text, int) to authenticated;
grant execute on function public.revoke_invite_code(text)                    to authenticated;
grant execute on function public.accept_invite(text)                         to authenticated;
grant execute on function public.change_role(text, text, text)               to authenticated;
grant execute on function public.remove_member(text, text)                   to authenticated;
grant execute on function public.transfer_ownership(text, text)              to authenticated;
grant execute on function public.leave_group(text)                           to authenticated;
grant execute on function public.delete_group(text)                          to authenticated;
grant execute on function public.delete_account()                            to authenticated;

notify pgrst, 'reload schema';
