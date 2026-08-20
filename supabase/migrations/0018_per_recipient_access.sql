-- Per-recipient access inside one care circle (D5's stated growth path).
--
-- Until now every member of a circle could read every care recipient in it:
-- `is_group_staff(group_id)` was the whole test. That was correct while a
-- circle held one person. It stops being correct the moment Elderhub Plus is
-- sold on "everyone you look after in the same circle", because Mom's
-- neighbour, invited to help with Mom, could read Dad's medications, bills and
-- notes as well.
--
-- Shape, and why this shape:
--
--  * A per-member **flag** (`group_members.access_scope`) plus a **grant table**
--    (`recipient_access`), not a backfilled grant row per (member x recipient).
--    A backfill has to stay correct forever after: every recipient added to a
--    circle would need fan-out rows written for every existing member, and one
--    miss is a sibling who silently cannot see Dad. With the flag, the common
--    case ('all') writes no rows at all, and the grant table only ever holds
--    rows a human deliberately created.
--
--  * Default is 'all', so this migration changes nothing anyone can currently
--    see. Restricting a member is a deliberate act. Hiding a recipient somebody
--    could read yesterday is a data-loss-shaped surprise, and D31 already says
--    siblings are not extra users to be metered.
--
--  * `visible_recipient_ids()` takes **no parameters**. This is the load-bearing
--    detail. A security-definer function that takes row values cannot be
--    wrapped in `(select ...)`, so Postgres calls it once per row;
--    `is_group_staff(group_id)` and `recipient_in_group(id, group_id)` are both
--    per-row calls today. A parameterless function reading only `auth.uid()`
--    hoists into an initPlan and runs **once per query**. Supabase's own RLS
--    guidance benchmarks exactly this rewrite (a correlated `exists` against a
--    membership table, turned into `col in (select ... where user_id =
--    auth.uid())`) at 9,000ms -> 20ms. So the scoped policies below are cheaper
--    than the unscoped ones they replace, not more expensive.
--
--  * The owner is never restrictable, in two places: the RPC refuses, and
--    `visible_recipient_ids()` treats an owner as unrestricted regardless of the
--    stored flag. An owner locked out of their own circle has no recovery path,
--    and owners manage billing and membership for the whole circle.
--
--  * Subject access (`is_my_recipient`, `medication_is_mine`) is untouched.
--    A parent reading their own record does not go through the circle at all
--    (D15), and I4 says that boundary is the database's job.

-- ============================================================
-- Schema
-- ============================================================

alter table public.group_members
    add column access_scope text not null default 'all'
    check (access_scope in ('all', 'listed'));

comment on column public.group_members.access_scope is
    'all = every recipient in the circle (default). listed = only the rows in recipient_access. Owners are unrestricted whatever this says.';

-- The grant table. Deliberately narrow: this is Oso''s "role on a resource"
-- pattern, added only because a human explicitly assigns it, and it replaces
-- the group-wide test on scoped tables rather than sitting beside it. Two ways
-- to express the same permission is how they drift apart.
create table public.recipient_access (
    care_recipient_id uuid not null references public.care_recipients(id) on delete cascade,
    user_id           uuid not null references auth.users(id)             on delete cascade,
    -- Denormalized, per D9, so the policies below stay join-free.
    group_id          uuid not null references public.groups(id)          on delete cascade,
    granted_at        timestamptz not null default now(),
    granted_by        uuid references public.profiles(id) on delete set null,
    primary key (care_recipient_id, user_id)
);

-- D8: index every column a policy filters on. The (user_id) lookup is the hot
-- one, because it is what visible_recipient_ids() runs once per query.
create index recipient_access_user_idx  on public.recipient_access(user_id);
create index recipient_access_group_idx on public.recipient_access(group_id);

alter table public.recipient_access enable row level security;

-- Readable by the circle's staff so the Sharing screen can render who sees
-- whom. Written only through the RPC below: like group_members, this table has
-- no client insert, update or delete policy at all, so there is no second path
-- that could drift from the rules in set_member_access().
create policy "recipient_access_staff_select"
    on public.recipient_access for select
    to authenticated
    using (public.is_group_staff(group_id));

-- ============================================================
-- The visibility functions
--
-- Parameterless on purpose: see the header. Both are `stable`, so the planner
-- may evaluate them once and reuse the result for the whole statement.
-- ============================================================

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

    -- The subject's own record (D15). Not a circle permission and never gated
    -- by one.
    select cr.id
      from public.care_recipients cr
     where cr.linked_user_id = (select auth.uid())
$$;

-- dose_logs hangs off medication_id, not care_recipient_id, so it needs the
-- same trick one level down rather than a join in the policy.
create or replace function public.visible_medication_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
    select m.id
      from public.medications m
     where m.care_recipient_id in (select public.visible_recipient_ids())
$$;

-- Staff who see the whole circle: unrestricted members, and every owner
-- whatever their stored flag says.
--
-- This exists as well as `visible_recipient_ids()` because two policies need to
-- ask the question *without* naming a row. `care_recipients` insert has no row
-- to name yet, and `care_recipients` select has to answer for a row that was
-- inserted by the same statement: `visible_recipient_ids()` is `stable`, so it
-- reads the snapshot taken at statement start and cannot see it. PostgREST
-- returns the inserted row on every write, so a select policy that could not
-- see it would fail every "add a person" call with an RLS violation.
create or replace function public.is_unrestricted_staff(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1
          from public.group_members gm
         where gm.group_id = p_group_id
           and gm.user_id = (select auth.uid())
           and gm.removed_at is null
           and gm.role in ('owner', 'caregiver')
           and (gm.access_scope = 'all' or gm.role = 'owner')
    );
$$;

grant execute on function public.visible_recipient_ids()  to authenticated;
grant execute on function public.visible_medication_ids() to authenticated;
grant execute on function public.is_unrestricted_staff(uuid) to authenticated;

-- ============================================================
-- Rewrite the staff policies
--
-- Nine tables carry exactly the same three staff policies over
-- (group_id, care_recipient_id), so they are rewritten in one loop: uniformity
-- is the property that matters here, and nine hand-copied triples is nine
-- chances to typo one `using` clause into something permissive. The tables that
-- differ are done explicitly below.
-- ============================================================

do $$
declare
    t text;
begin
    foreach t in array array[
        'medications',
        'visits',
        'vital_readings',
        'emergency_contacts',
        'providers',
        'care_events',
        'care_tasks',
        'care_notes',
        'bills'
    ]
    loop
        execute format('drop policy if exists %I on public.%I', t || '_staff_select', t);
        execute format('drop policy if exists %I on public.%I', t || '_staff_insert', t);
        execute format('drop policy if exists %I on public.%I', t || '_staff_update', t);

        execute format($f$
            create policy %I on public.%I for select to authenticated
            using (
                public.is_group_staff(group_id)
                and care_recipient_id in (select public.visible_recipient_ids())
            )
        $f$, t || '_staff_select', t);

        execute format($f$
            create policy %I on public.%I for insert to authenticated
            with check (
                public.is_group_staff(group_id)
                and public.recipient_in_group(care_recipient_id, group_id)
                and care_recipient_id in (select public.visible_recipient_ids())
            )
        $f$, t || '_staff_insert', t);

        execute format($f$
            create policy %I on public.%I for update to authenticated
            using (
                public.is_group_staff(group_id)
                and care_recipient_id in (select public.visible_recipient_ids())
            )
            with check (
                public.is_group_staff(group_id)
                and public.recipient_in_group(care_recipient_id, group_id)
                and care_recipient_id in (select public.visible_recipient_ids())
            )
        $f$, t || '_staff_update', t);
    end loop;
end $$;

-- care_recipients: the one table that cannot phrase its own visibility purely
-- in terms of `visible_recipient_ids()`, for the snapshot reason above. An
-- unrestricted member sees the circle by definition, so asking that directly is
-- not a loosening; a restricted member still has to find the row in their
-- grants. Insert is gated on being unrestricted, because a member scoped to Mom
-- creating a person they would then be unable to see is not a thing to allow.
drop policy if exists "care_recipients_staff_select" on public.care_recipients;
drop policy if exists "care_recipients_staff_insert" on public.care_recipients;
drop policy if exists "care_recipients_staff_update" on public.care_recipients;

create policy "care_recipients_staff_select"
    on public.care_recipients for select
    to authenticated
    using (
        public.is_unrestricted_staff(group_id)
        or (
            public.is_group_staff(group_id)
            and id in (select public.visible_recipient_ids())
        )
    );

create policy "care_recipients_staff_insert"
    on public.care_recipients for insert
    to authenticated
    with check (public.is_unrestricted_staff(group_id));

create policy "care_recipients_staff_update"
    on public.care_recipients for update
    to authenticated
    using (
        public.is_unrestricted_staff(group_id)
        or (
            public.is_group_staff(group_id)
            and id in (select public.visible_recipient_ids())
        )
    )
    with check (
        public.is_unrestricted_staff(group_id)
        or (
            public.is_group_staff(group_id)
            and id in (select public.visible_recipient_ids())
        )
    );

-- dose_logs: one level down, through visible_medication_ids().
drop policy if exists "dose_logs_staff_select" on public.dose_logs;
drop policy if exists "dose_logs_staff_insert" on public.dose_logs;
drop policy if exists "dose_logs_staff_update" on public.dose_logs;

create policy "dose_logs_staff_select"
    on public.dose_logs for select
    to authenticated
    using (
        public.is_group_staff(group_id)
        and medication_id in (select public.visible_medication_ids())
    );

create policy "dose_logs_staff_insert"
    on public.dose_logs for insert
    to authenticated
    with check (
        public.is_group_staff(group_id)
        and medication_id in (select public.visible_medication_ids())
    );

create policy "dose_logs_staff_update"
    on public.dose_logs for update
    to authenticated
    using (
        public.is_group_staff(group_id)
        and medication_id in (select public.visible_medication_ids())
    )
    with check (
        public.is_group_staff(group_id)
        and medication_id in (select public.visible_medication_ids())
    );

-- check_ins: no update policy by design (a check-in is a historical fact), and
-- the self-insert path is the subject's own and stays untouched (I2).
drop policy if exists "check_ins_staff_select"        on public.check_ins;
drop policy if exists "check_ins_staff_manual_insert" on public.check_ins;

create policy "check_ins_staff_select"
    on public.check_ins for select
    to authenticated
    using (
        public.is_group_staff(group_id)
        and care_recipient_id in (select public.visible_recipient_ids())
    );

create policy "check_ins_staff_manual_insert"
    on public.check_ins for insert
    to authenticated
    with check (
        source = 'caregiver_manual'
        and pressed_by = (select auth.uid())
        and public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
        and care_recipient_id in (select public.visible_recipient_ids())
    );

drop policy if exists "check_in_settings_staff_select" on public.check_in_settings;
drop policy if exists "check_in_settings_staff_insert" on public.check_in_settings;
drop policy if exists "check_in_settings_staff_update" on public.check_in_settings;

create policy "check_in_settings_staff_select"
    on public.check_in_settings for select
    to authenticated
    using (
        public.is_group_staff(group_id)
        and care_recipient_id in (select public.visible_recipient_ids())
    );

create policy "check_in_settings_staff_insert"
    on public.check_in_settings for insert
    to authenticated
    with check (
        public.is_group_staff(group_id)
        and public.recipient_in_group(care_recipient_id, group_id)
        and care_recipient_id in (select public.visible_recipient_ids())
    );

create policy "check_in_settings_staff_update"
    on public.check_in_settings for update
    to authenticated
    using (
        public.is_group_staff(group_id)
        and care_recipient_id in (select public.visible_recipient_ids())
    )
    with check (
        public.is_group_staff(group_id)
        and care_recipient_id in (select public.visible_recipient_ids())
    );

-- ============================================================
-- Mutation RPC (D10: lifecycle changes go through a security-definer function)
--
-- Every parameter is text and cast inside (D11), so PostgREST cannot land on an
-- ambiguous overload.
-- ============================================================

create or replace function public.set_member_access(
    p_group_id     text,
    p_user_id      text,
    p_scope        text,
    p_recipient_ids text[] default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_group_id uuid := p_group_id::uuid;
    v_user_id  uuid := p_user_id::uuid;
    v_uid      uuid := (select auth.uid());
    v_role     text;
    v_ids      uuid[];
    v_id       uuid;
begin
    if v_uid is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;

    -- Deciding who may read a family's medical records is an owner's call, the
    -- same as removing a member or changing a role.
    if not public.is_group_owner(v_group_id) then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    if p_scope not in ('all', 'listed') then
        raise exception 'unknown access scope %', p_scope using errcode = '22023';
    end if;

    select role into v_role
      from public.group_members
     where group_id = v_group_id
       and user_id = v_user_id
       and removed_at is null;

    if v_role is null then
        raise exception 'not a member of this circle' using errcode = '23503';
    end if;

    -- Two ways an owner could lock a circle: restrict another owner, or restrict
    -- themselves. Neither has a recovery path that does not involve me and a
    -- SQL console, so neither is allowed.
    if v_role = 'owner' and p_scope = 'listed' then
        raise exception 'an owner always sees the whole circle' using errcode = '42501';
    end if;

    -- A subject is scoped by linked_user_id and never by this table.
    if v_role = 'subject' then
        raise exception 'subject access is set by their linked record' using errcode = '42501';
    end if;

    update public.group_members
       set access_scope = p_scope
     where group_id = v_group_id
       and user_id = v_user_id
       and removed_at is null;

    -- Replace rather than merge: the caller sends the whole list it wants, so a
    -- recipient dropped from the list is a revocation. Merging would make
    -- "stop showing her Dad" impossible to express.
    delete from public.recipient_access
     where user_id = v_user_id
       and group_id = v_group_id;

    if p_scope = 'listed' and p_recipient_ids is not null then
        -- Cast the whole text[] once. Every RPC parameter is text (D11), so the
        -- cast has to happen somewhere; doing it here means a malformed id
        -- fails the call rather than half-applying it.
        select coalesce(array_agg(t.x::uuid), '{}')
          into v_ids
          from unnest(p_recipient_ids) as t(x)
         where nullif(trim(t.x), '') is not null;

        foreach v_id in array v_ids
        loop
            -- Only recipients that actually belong to this circle, so a crafted
            -- call cannot grant access to a stranger's record.
            if public.recipient_in_group(v_id, v_group_id) then
                insert into public.recipient_access
                    (care_recipient_id, user_id, group_id, granted_by)
                values (v_id, v_user_id, v_group_id, v_uid)
                on conflict (care_recipient_id, user_id) do nothing;
            end if;
        end loop;
    end if;
end;
$$;

revoke all on function public.set_member_access(text, text, text, text[]) from public;
grant execute on function public.set_member_access(text, text, text, text[]) to authenticated;

-- Clearing grants when a member is removed is handled by the membership RPCs
-- setting removed_at, which visible_recipient_ids() already joins against. The
-- rows are left in place so that re-adding someone restores what they had.

notify pgrst, 'reload schema';
