-- Med List (Aging) — make the invite role ceiling a real check.
--
-- `generate_invite_code` (0004) called `is_group_staff(v_group_id)` twice: once
-- as the authorization gate, and again a few lines later under a comment
-- promising "only an owner can create another owner". The second call could
-- never be false, because the first had already raised for anyone who was not
-- staff, so the rule the comment described was not enforced by any check at all.
-- It held only by accident: `p_role` is constrained to caregiver-or-subject, so
-- 'owner' could not be requested in the first place, and the client never offers
-- an owner invite.
--
-- Not exploitable today. It becomes exploitable the moment someone widens the
-- allow-list, which is exactly the change a future owner-invite feature makes,
-- and the dead check would have read as though it already covered it.
--
-- The fix asks the question the comment claims: an 'owner' invite requires
-- `is_group_owner`, checked before the allow-list rather than after, so it is
-- live rather than shadowed. The allow-list itself is unchanged, so no new
-- invite path opens here: a caregiver asking for an owner invite now gets 42501
-- instead of 22023, and that is the whole behavioural difference.
--
-- Append-only, per the project rule. 0004 is not edited.

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

    -- The ceiling. Asked of the caller's actual role, and asked first, so it
    -- is reachable: a caregiver requesting an owner invite is refused here on
    -- authorization grounds rather than falling through to the allow-list and
    -- being refused as a malformed argument.
    if p_role = 'owner' and not public.is_group_owner(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    -- v1 hands out caregiver and subject invites only. Stated separately from
    -- the ceiling above, so widening this list later inherits the rule instead
    -- of quietly bypassing it.
    if p_role not in ('caregiver', 'subject') then
        raise exception 'invalid role' using errcode = '22023';
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

grant execute on function public.generate_invite_code(text, text, text, int) to authenticated;
