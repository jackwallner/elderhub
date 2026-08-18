-- Med List (Aging) — group-scoped entitlement.
--
-- One person buys through ordinary App Store IAP and the whole family is
-- covered, which is the Life360 model: one Circle member subscribes and every
-- member of that Circle gets the features. The purchase itself still goes
-- through in-app purchase, which is all guideline 3.1.1 asks; nothing in 3.1.2
-- speaks against a backend applying one purchase to a group.
--
-- The entitlement lives on the group, not fanned out per member. The
-- alternative (RevenueCat promotional entitlements granted to each member's
-- app_user_id) would mean every join, leave and removal has to call
-- RevenueCat, creating a second source of truth that drifts and fails
-- silently. Here, membership changes run no billing code at all.
--
-- Resolution on the client is:  myRevenueCatEntitlement || group.entitlement
-- so the payer's own device unlocks instantly with no round trip, and everyone
-- else resolves through a row that is already syncing and already cached
-- locally, which means it survives being offline.

create table public.group_billing (
    group_id       uuid primary key references public.groups(id) on delete cascade,
    entitlement    text not null default 'free' check (entitlement in ('free', 'plus')),
    expires_at     timestamptz,
    -- Null for a lifetime purchase.
    is_lifetime    boolean not null default false,
    payer_user_id  uuid references public.profiles(id) on delete set null,
    -- RevenueCat's app_user_id for the payer, which is the Supabase user id.
    rc_app_user_id text,
    product_id     text,
    updated_at     timestamptz not null default now()
);

alter table public.group_billing enable row level security;

create trigger group_billing_touch
    before insert or update on public.group_billing
    for each row execute function public.touch_updated_at();

-- Every member can read it, including the subject. Reading it never gates the
-- check-in button; see the note at the bottom of this file.
create policy "group_billing_member_select"
    on public.group_billing for select
    using (public.is_group_member(group_id));

-- No client write policies. The only writer is the RevenueCat webhook handler,
-- which runs as the service role and is not subject to RLS. A client that
-- could PATCH this row could give itself Plus.

create index group_billing_expiry_idx on public.group_billing(expires_at)
    where entitlement = 'plus' and not is_lifetime;

-- Convenience for the client and for future server-side checks. Deliberately
-- NOT referenced anywhere on the check-in path.
create or replace function public.group_has_plus(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.group_billing
        where group_id = p_group_id
          and entitlement = 'plus'
          and (is_lifetime or expires_at > now())
    );
$$;

grant execute on function public.group_has_plus(uuid) to authenticated;

-- Invariant, restated here because this is the file where it would get broken:
-- nothing in 0003_check_ins.sql references group_billing or group_has_plus, and
-- nothing ever should. The parent was told to press that button. A paywall on
-- it must be structurally impossible, not merely absent from the current UI.

notify pgrst, 'reload schema';
