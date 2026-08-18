-- Med List (Aging) — foundation: profiles, groups, membership, RLS helpers.
--
-- Order matters here. The security-definer helper functions are created before
-- any policy that needs them, because a policy on `group_members` that queries
-- `group_members` inline recurses and errors on the very first "list my group"
-- query. See docs/research/01-groups-rbac-rls.md §3.
--
-- Conventions used in every migration in this directory:
--   * `(select auth.uid())`, never bare `auth.uid()` — the bare form is
--     re-evaluated per row and `dose_logs`/`vital_readings` grow to thousands
--     of rows per recipient.
--   * RPC parameters are `text`, cast to uuid inside the body. Bond hit
--     PostgREST overload ambiguity (PGRST203) doing it the other way.
--   * Every file ends with `notify pgrst, 'reload schema';`.
--   * Migrations are append-only once applied anywhere. Fix forward.

create extension if not exists "pgcrypto";

-- ============================================================
-- Shared trigger: server-authoritative updated_at
-- ============================================================
-- Clients never set updated_at. The sync cursor compares against this column,
-- so a device with a wrong clock must not be able to write a timestamp that
-- makes its rows invisible (or permanently re-fetched) for everyone else.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

-- ============================================================
-- Profiles — 1:1 with auth.users. Member users only.
-- A cared-for person is NOT a profile; see care_recipients in 0002.
-- ============================================================
create table public.profiles (
    id           uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default '',
    apns_token   text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

create trigger profiles_touch
    before insert or update on public.profiles
    for each row execute function public.touch_updated_at();

create policy "profiles_self_rw"
    on public.profiles for all
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- Auto-create a profile row on signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'display_name',
                 new.raw_user_meta_data->>'full_name',
                 '')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ============================================================
-- Groups
-- ============================================================
create table public.groups (
    id          uuid primary key default gen_random_uuid(),
    name        text not null default 'Family',
    created_by  uuid references public.profiles(id) on delete set null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

alter table public.groups enable row level security;

create trigger groups_touch
    before insert or update on public.groups
    for each row execute function public.touch_updated_at();

-- ============================================================
-- Group members — role lives HERE, never on profiles or care_recipients.
-- A user is owner of their mother's group and the subject of their own
-- children's group at the same time; role cannot be a property of the person.
-- ============================================================
create table public.group_members (
    id          uuid primary key default gen_random_uuid(),
    group_id    uuid not null references public.groups(id) on delete cascade,
    user_id     uuid not null references public.profiles(id) on delete cascade,
    role        text not null check (role in ('owner', 'caregiver', 'subject')),
    invited_by  uuid references public.profiles(id) on delete set null,
    joined_at   timestamptz not null default now(),
    removed_at  timestamptz,
    updated_at  timestamptz not null default now(),
    unique (group_id, user_id)
);

-- `role` is text + check, deliberately not a native enum: ALTER TYPE ADD VALUE
-- cannot be used in the same transaction that uses the new value, and Supabase
-- CLI migrations are one transaction per file. Adding 'viewer' later is a
-- constraint swap, not a rewrite.

create index group_members_user_idx  on public.group_members(user_id) where removed_at is null;
create index group_members_group_idx on public.group_members(group_id) where removed_at is null;

alter table public.group_members enable row level security;

create trigger group_members_touch
    before insert or update on public.group_members
    for each row execute function public.touch_updated_at();

-- ============================================================
-- Security-definer helpers. These break the RLS recursion cycle: they run as
-- the function owner and are not themselves subject to RLS, so a policy on
-- group_members may call them without re-entering group_members' own policy.
--
-- Chosen over JWT custom claims on purpose: removing a caregiver must take
-- effect immediately, not at the next token refresh, and family groups are
-- small enough that the live lookup costs nothing.
-- ============================================================
create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.group_members
        where group_id = p_group_id
          and user_id = (select auth.uid())
          and removed_at is null
    );
$$;

create or replace function public.group_role(p_group_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
    select role from public.group_members
    where group_id = p_group_id
      and user_id = (select auth.uid())
      and removed_at is null;
$$;

create or replace function public.is_group_staff(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce(public.group_role(p_group_id) in ('owner', 'caregiver'), false);
$$;

create or replace function public.is_group_owner(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce(public.group_role(p_group_id) = 'owner', false);
$$;

-- Do I share any group with this user? Used by the profiles select policy so
-- members can see each other's display names without exposing the whole table.
create or replace function public.shares_group_with(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1
        from public.group_members mine
        join public.group_members theirs on theirs.group_id = mine.group_id
        where mine.user_id = (select auth.uid())
          and mine.removed_at is null
          and theirs.user_id = p_user_id
          and theirs.removed_at is null
    );
$$;

grant execute on function public.is_group_member(uuid)  to authenticated;
grant execute on function public.group_role(uuid)       to authenticated;
grant execute on function public.is_group_staff(uuid)   to authenticated;
grant execute on function public.is_group_owner(uuid)   to authenticated;
grant execute on function public.shares_group_with(uuid) to authenticated;

-- ============================================================
-- Policies that depend on the helpers
-- ============================================================
create policy "profiles_group_visible_select"
    on public.profiles for select
    using (public.shares_group_with(id));

create policy "groups_member_select"
    on public.groups for select
    using (public.is_group_member(id));

create policy "groups_owner_update"
    on public.groups for update
    using (public.is_group_owner(id))
    with check (public.is_group_owner(id));

-- No client insert on groups: creation goes through create_group() in 0004.
-- No client delete on groups: deletion goes through delete_group() in 0004.

create policy "group_members_select"
    on public.group_members for select
    using (public.is_group_member(group_id));

-- Deliberately NO insert/update/delete policy on group_members. Every write is
-- a security-definer RPC (accept_invite, change_role, remove_member,
-- transfer_ownership, leave_group). Without this, a member could promote
-- themselves to owner with a single PATCH.

notify pgrst, 'reload schema';
