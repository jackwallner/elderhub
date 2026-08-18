# Family groups, roles, and RLS for Med List (Aging)

Research brief for moving Aging from local-only SwiftData to a Supabase-backed
family group model. Written against the existing local model
(`Shared/Models/CareModels.swift`) and the house style already established in
`~/bond/supabase/migrations/*.sql`. This is a design document — SQL below is a
sketch to implement from, not a migration to run verbatim.

## Recommendations up front

- **Cared-for person ("Person") is a separate table from auth users**, linked
  optionally via a nullable `linked_user_id` FK, not merged into `profiles`
  and not modeled as two unrelated tables with no relationship. See §1.
- **Roles live on the membership row (`group_members.role`), not on the user
  or the care-recipient row.** A user can be `owner`/`caregiver` in one group
  and `subject` in another. See §2.
- **Role model for v1: a `role` text column (check constraint, not a native
  Postgres enum) on `group_members`**, with a capability matrix hard-coded
  into policies now and left room to grow into a capability-override column
  or a per-recipient grant table later, additively. See §2.
- **v1 roles: `owner`, `caregiver`, `subject`.** Reserve `viewer` (read-only
  extended family) as a documented future value; don't add it to the check
  constraint until it's built.
- **RLS recursion:** never let a `group_members` policy re-query
  `group_members` inline. Use a `security definer` helper function
  (`is_group_member`, `group_role`), exactly Bond's `is_couple_member`
  pattern, extended for N members. See §3.
- **Use security-definer helper functions for role checks, not JWT custom
  claims**, for v1. Family groups are tiny (single/low-double-digit rows per
  group), so the live-lookup cost is negligible, and role changes (removing
  a caregiver, promoting an owner) need to take effect immediately, not after
  a token refresh. See §3.
- **Wrap `auth.uid()` as `(select auth.uid())` in every policy, and index
  every column a policy filters on** (`group_members.user_id`,
  `care_recipients.group_id`, and a denormalized `group_id` on every leaf
  table). See §3.
- **Denormalize `group_id` onto every leaf table** (medications, dose_logs,
  visits, vitals, emergency_contacts, check_ins) so policies don't need a
  join through `care_recipients` on every row. Care recipients don't move
  between groups in v1, so there's no drift risk yet — flag it if that
  changes.
- **Sensitive mutations go through `security definer` RPCs, not raw
  RLS-guarded table writes**: accepting an invite, changing a role, removing
  a member, transferring ownership, leaving a group, deleting a group,
  deleting an account. Bond's own migration history (0004 → 0009, 0008 →
  0010) is a live example of what goes wrong when you skip this. See §3, §4.
- **High-frequency low-risk writes stay as direct RLS-guarded inserts**: dose
  logs, vitals, visits, check-ins. No RPC needed there.
- **Invite codes: keep them short and human-typeable, but harden past
  Bond's version** — 8-10 char code, single-use, ~48h expiry, owner-revocable
  from day one (Bond only added revocation reactively, in 0011), and add
  explicit rate limiting on the consume path, which Supabase does not give
  you for free on a custom RPC. See §4.
- **Removed-member history is never deleted.** Rows a removed member
  authored (medications, dose logs, visits) are shared family medical
  history, not their personal property — closer to Bond's `milestones` than
  its `reminders`. Keep a `created_by` FK (`on delete set null`) *plus* a
  denormalized `*_by_name` text snapshot taken at write time, so "logged by
  Sarah" survives Sarah's account deletion. See §4, §5.
- **Audit trail: `created_by`/`updated_by` columns everywhere, plus a single
  generic `audit_log` table populated by triggers on the highest-stakes
  tables only** (medications, dose_logs, group_members, care_recipients).
  Proportionate for a solo-developer app — this is "responsible design," not
  HIPAA/BAA-grade compliance (Aging is a consumer app, not a covered
  entity). See §5.
- **Check-in write authorization is keyed off `care_recipients.linked_user_id`,
  not off role.** A caregiver can also log a manual check-in on behalf of a
  recipient who has no phone. This is what makes the sandwich-generation case
  (same user, subject in one group, caregiver in another) fall out cleanly
  instead of needing special-cased logic. See §2, §6.

---

## 1. Entity model: is the cared-for person a user?

**Recommendation: two tables, optionally linked.** A `care_recipients` table
(the cloud counterpart of local `Person`) that may optionally point at a
`profiles` row via a nullable, unique `linked_user_id`. Not the same table as
`profiles`, and not two tables with no relationship between them.

Argument, given the two constraints in the brief:

- **Dad has dementia and no smartphone.** He must be fully representable —
  named, tracked, medicated, visited, vitals recorded — with **zero** auth
  identity. If "Person" were required to be an auth user (one-table model,
  `care_recipients extends profiles` or similar), you cannot create Dad at
  all without an account for him, which is either fake (a shadow account
  someone else controls) or impossible. A local `Person` row today has no
  user attached and none is coming; the cloud schema must preserve that.
- **Mom does press the button.** She needs a real session, a real JWT, RLS
  that recognizes her, and a UI that maps "I am logged in as Mom" onto "which
  care_recipients row is *me*." That requires a real link between an
  `auth.users`/`profiles` row and a `care_recipients` row — not just "a
  member with a restrictive role," because role lives on `group_members`
  (membership in the group), and being-the-subject is a property of a
  specific recipient row, not of group membership in general.
- **Sandwich generation.** The same person is a caregiver for their mother in
  one group and, elsewhere, the cared-for subject for their own kids managing
  *their* early dementia in another group. If `care_recipients` and
  `profiles` were the same table, "is this row a caregiver or a subject"
  would have to be a property of the person, which is exactly the thing the
  brief says must not happen. Keeping them separate, joined per-group via
  `group_members.role` and `care_recipients.linked_user_id`, means the same
  `profiles.id` can be `owner` in group A's `group_members` and simultaneously
  be `care_recipients.linked_user_id` for a row in group B — no conflict,
  no special-casing.

The alternative some SaaS "org member" tutorials suggest — put a `user_type`
or `is_subject` flag on the membership row instead of a separate table — was
considered and rejected: it collapses "this user is being cared for" and
"this specific human is being cared for" into one thing, but real cared-for
people frequently don't have a `profiles` row at all (Dad). You'd end up
needing the `care_recipients` table anyway for the no-account case, and then
have two divergent representations of "a person being cared for" depending on
whether they have a phone. One table, optionally linked, avoids that split.

```sql
create table public.care_recipients (
    id              uuid primary key default gen_random_uuid(),
    group_id        uuid not null references public.groups(id) on delete cascade,
    linked_user_id  uuid references public.profiles(id) on delete set null,
    name            text not null,
    relationship    text not null default '',
    birth_date      date,
    blood_type      text not null default '',
    color_index     int  not null default 0,
    allergies       text[] not null default '{}',
    conditions      text[] not null default '{}',
    notes           text not null default '',
    created_by      uuid references public.profiles(id) on delete set null,
    created_at      timestamptz not null default now()
);

-- A profile can be "the subject" of at most one care_recipients row per group
-- (they could in principle be linked in more than one group, which is fine —
-- e.g. two adult children's groups both track the same aging parent — so this
-- is scoped to (group_id, linked_user_id), not a global unique on linked_user_id).
create unique index care_recipients_group_linked_user_idx
    on public.care_recipients(group_id, linked_user_id)
    where linked_user_id is not null;

create index care_recipients_group_idx on public.care_recipients(group_id);
```

`on delete set null` on `linked_user_id` is deliberate: deleting Mom's
`profiles` row (account deletion) must not delete the `care_recipients` row
that holds her medication history — it just un-links it, same as it would if
she'd never had an account.

---

## 2. Role and permission model

Compared:

- **(a) single `role` on the membership row** — simplest, matches "a user's
  power is scoped to one group" requirement directly, cheap to check in RLS
  (one indexed lookup), easy to reason about for a family-sized group where
  members are trusted with the whole group's recipients.
- **(b) roles + separate capability table** — right model once you need
  per-group *custom* capability sets (e.g. "caregiver but no vitals edit").
  Overkill for v1: nobody has asked for that granularity yet, and it adds a
  join to every single policy check.
- **(c) per-care-recipient grants** — right model once a group has recipients
  that not all members should see (a paid caregiver who only handles Dad, not
  Mom's finances-adjacent notes). Real future need (brief mentions paid
  caregiver access explicitly) but not a v1 requirement — today's target
  users are a handful of siblings who all manage both parents.

**Recommendation: (a) for v1**, structured so it grows into (b) and (c)
without a destructive migration:

- Ship `role text not null check (role in ('owner','caregiver','subject'))`.
  Adding `'viewer'` later is a one-line `alter table ... drop constraint ...
  add constraint ...` (or a migration that widens the check), not a rewrite.
  (Deliberately **not** a native Postgres enum — see §6 for why.)
- Ship group-wide capability policies now (role ⇒ full access to every
  `care_recipients` row in the group). When per-recipient grants are needed,
  add an additive `care_recipient_grants (group_member_id, care_recipient_id,
  capability)` table and change each policy from `is_group_caregiver(group_id)`
  to `is_group_caregiver(group_id) and (no grants exist for this member OR a
  matching grant exists)` — additive, not destructive, and rows with no grants
  keep today's default "full group access" behavior.
- When custom per-member capability overrides are needed, add an additive
  `capabilities text[]` column to `group_members` that, when non-null,
  overrides the role default in the same helper function. Existing rows with
  `capabilities = null` keep behaving exactly as their role says.

### Capability matrix (v1)

| Capability | owner | caregiver | subject |
|---|---|---|---|
| Read medications (any recipient in group) | Y | Y | own recipient only |
| Write/edit medications | Y | Y | N |
| Log a dose (self or on behalf of) | Y | Y | N *(see note)* |
| Read dose logs | Y | Y | own recipient only |
| Read/write visits | Y | Y | N / N |
| Read/write vitals | Y | Y | own recipient read-only / N |
| Read/write emergency card | Y | Y | own recipient read-only / N |
| Press "I'm OK" check-in for self | n/a | n/a (see note) | **Y**, own linked recipient only |
| Log a manual check-in on someone's behalf | Y | Y | N |
| Read check-in status / receive escalation alerts | Y | Y | N |
| Invite a member | Y | Y (capped to caregiver-or-below role) | N |
| Remove a member | Y | N | N |
| Change a member's role | Y | N | N |
| Delete the group | Y | N | N |
| Billing / subscription management | Y | N | N |

Note: check-in write authorization is **not** gated on `role = 'subject'`. It's
gated on `care_recipients.linked_user_id = (select auth.uid())` for a
self-press, or `role in ('owner','caregiver')` for a manual/on-behalf press.
This is what makes it correct for the sandwich-generation case for free: the
same `auth.uid()` can press their own button as `subject` in one group and
press Dad's button as `caregiver` in another, with no special-casing — the
check is always "does this specific row's `linked_user_id` match me, or am I
staff for this group," never "what's my global role."

`subject` deliberately cannot log their own doses in v1 (matches "deliberately
reduced subset"); if that turns out to be wrong for a mildly-impaired but
capable parent, it's a single policy addition, not a schema change.

---

## 3. RLS design

### Recursion

The classic trap: a `group_members` SELECT policy that needs "show me every
row for groups I'm in" has to query `group_members` again to establish "am I
in this group," which re-triggers the same policy — Postgres detects the
cycle and errors (`infinite recursion detected in policy for relation
"group_members"`). This is a well-documented Supabase footgun ([GitHub
Discussion #47525](https://github.com/orgs/supabase/discussions/47525),
[GitHub Discussion #3802](https://github.com/orgs/supabase/discussions/3802)).

Fix, and the one Bond already uses (`is_couple_member`, generalized here): a
`security definer` function queries the membership table **without RLS
applying to that internal query** (security definer functions run as the
function owner, bypassing the caller's RLS), and the policy calls the
function instead of querying the table inline.

```sql
create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.group_members
        where group_id = p_group_id
          and user_id = (select auth.uid())
    );
$$;

create or replace function public.group_role(p_group_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
    select role from public.group_members
    where group_id = p_group_id
      and user_id = (select auth.uid());
$$;

create or replace function public.is_group_staff(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select public.group_role(p_group_id) in ('owner', 'caregiver');
$$;
```

`group_members`'s own SELECT policy can then safely be
`using (public.is_group_member(group_id))` without recursing, because the
function's internal query runs outside RLS.

### Security-definer helpers vs. JWT custom claims

Supabase supports baking role/permission claims into the JWT via a Custom
Access Token Auth Hook, checked in policies as `auth.jwt() ->> 'role'`
([Supabase docs, Custom Claims & RBAC](https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac)).
The tradeoff: JWT claims are baked in at token issuance and **do not update
until the token refreshes** (default access token lifetime up to 1 hour) —
if an owner removes a caregiver mid-session, that caregiver's existing JWT
still carries the old claim until it expires or they re-authenticate. The
security-definer-function approach instead does a live table lookup on every
request, so a role change or removal is enforced on the very next request,
at the cost of one extra indexed lookup per RLS check.

**Recommendation: security-definer functions for v1.** Family groups are
small (a handful of members, one or two recipients), so the live-lookup cost
is negligible — this is not the 1M-row-table scenario the JWT-claims
optimization exists for. Given this is a medical-adjacent app where "I just
removed my sister's access after a falling-out" needs to work *now*, not
"after her token expires," correctness beats the marginal performance win.
Keep custom claims as a documented escape hatch if group/table sizes ever
justify the added complexity.

One caveat from the docs, worth remembering either way: *"functions you use
in RLS can be called from the API. Secure your functions in an alternate
schema if their results would be a security leak"* — `group_role` returning
a bare role string is low-risk, but don't build a helper that leaks more than
intended.

### Performance

Two documented pitfalls, both directly applicable here
([Supabase RLS Performance and Best Practices](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv)):

1. **`auth.uid()` re-evaluates per row** unless wrapped. `auth.uid() =
   user_id` forces a function call on every row scanned; `(select auth.uid())
   = user_id` lets the planner run it once as an `initPlan` and cache the
   result. Documented improvement: 179ms → 9ms on one benchmark, and up to
   99.99% on larger tables. **Every policy in this schema should use `(select
   auth.uid())`, never bare `auth.uid()`.** The same applies to any
   security-definer helper call: wrap as `(select public.is_group_member(group_id))`.
2. **Every column referenced in a policy needs an index** if it isn't already
   a primary/unique key. Documented improvement: 171ms → <0.1ms just from
   indexing the filtered column. Required indexes for this schema:
   `group_members(user_id)`, `group_members(group_id, user_id)` (composite,
   also serves as the natural uniqueness constraint), `care_recipients(group_id)`,
   and a `group_id` index on every leaf table once it's denormalized there
   (see below).

Denormalizing `group_id` onto every leaf table (medications, dose_logs,
visits, vitals, emergency_contacts, check_ins) means every policy is a single
indexed `group_id` lookup through the security-definer helper, instead of a
join up through `care_recipients` on every row of every query. Given
`care_recipients` don't move between groups in v1, there's no consistency
risk from the denormalization; if cross-group recipient transfer is ever
built, add a trigger to cascade the `group_id` update to all children at that
point.

### Policy granularity and `with check`

Use `for all` only where the read and write rule are genuinely identical
(Bond does this for `milestones` and `reminder_events`: any member can read
or write, full stop). Everywhere the write rule needs to be *narrower* than
the read rule — which is most of this schema, because `subject` can read
their own data but not write it, and nobody but `owner` can write
`group_members.role` — use separate `select`/`insert`/`update`/`delete`
policies.

`with check` is the mechanism that stops privilege escalation on writes,
and it is required (not optional) in exactly two places here:

1. **`group_members` insert/update.** A bare `using (is_group_staff(group_id))`
   with no `with check` would let a caregiver `PATCH` their own row's `role`
   to `'owner'`, or insert a new membership row for themselves in a group
   they don't belong to, using their write access to *other* rows as cover.
   The `with check` must independently re-validate the *new* row, not trust
   the `using` clause that validated visibility of the *old* row.
2. **Any insert where a client picks the foreign key.** E.g. inserting a
   `medications` row: `using`/`with check` must both confirm the *supplied*
   `care_recipient_id`'s `group_id` matches a group the caller is staff in —
   otherwise a caregiver in group A could insert a medication row pointed at
   a `care_recipient_id` belonging to group B by guessing/enumerating a UUID.

**Recommendation: don't allow direct client writes to `group_members.role` or
`group_members` inserts at all.** Route every role-affecting mutation through
a security-definer RPC (§3 next, §4) that does its own authorization inside
the function body with row locking, and give `group_members` **no client
insert/update policy** for the `role` column path — only a `select` policy
for the caller's own groups. This removes an entire class of `with check`
bugs by removing the endpoint instead of trying to lock it down perfectly.

### RLS-guarded writes vs. security-definer RPCs

**Recommendation: RPCs for anything that changes group shape or power**
(invite acceptance, role change, member removal, ownership transfer, group
deletion, account deletion), **direct RLS-guarded inserts for anything that's
just a new row of medical data** (dose logs, vitals, visits, check-ins,
medication edits).

Justification is Bond's own migration history, which is a live case study of
what happens when this line is drawn in the wrong place:

- 0004 `leave_couple` did a bare `delete from couples`, relying on FK cascade
  to clean up — and cascaded away *both* partners' reminders/milestones, not
  just the leaver's. Fixed properly only in 0009, with explicit re-homing
  logic that a same-transaction, row-locked RPC could express but a
  declarative RLS `delete` policy fundamentally cannot (RLS can say *who* may
  delete a row, not *what else should happen* when they do).
- 0008 `delete_account` cascaded `auth.users → profiles → couples`, and
  because the couple row was *shared*, one partner deleting their account
  destroyed the other partner's data too. Fixed in 0010 by first
  re-parenting the shared row to the surviving partner *inside the RPC*,
  atomically, under `for update` locking.

The shape of the bug both times was the same: a shared/group-owned row got
swept up in a cascade meant for one user's own data. Aging has more shared
state than Bond (a `care_recipients` row is shared history across every
member of the group, not just two partners), so the same class of bug is
*more* likely here if lifecycle mutations are left to raw cascades or
declarative policies instead of explicit, transactional, row-locked RPCs.

---

## 4. Invite and lifecycle flows

### Invite codes

Bond's pattern: a `text primary key` code, `created_by`, `expires_at`,
consumed via a `security definer` RPC that does `select ... for update` (row
lock against a race), deletes the code on success, and has **no rate
limiting and no delete policy for the creator** until 0011 added revocation
reactively.

For Aging, keep the human-typeable short code (real families read a code out
loud over the phone — a signed deep link is worse UX for exactly the target
user, e.g. a spouse with a flip phone reading digits to an adult child), but
hedge past Bond's version from day one instead of reactively:

- **Length/entropy**: 8 alphanumeric characters, excluding visually
  ambiguous characters (`0/O`, `1/I/l`) — enough keyspace (~32^8) that online
  brute force is impractical *if* paired with rate limiting; short codes are
  explicitly meant to be low-entropy and rely on rate limiting for
  practical security, not entropy alone.
- **Single-use, ~48h expiry**: matches Bond's `expires_at` mechanism; delete
  the row on successful consumption (Bond already does this).
- **Owner-revocable from day one**: ship the `delete` policy in the initial
  migration instead of adding it after the first support request, unlike
  Bond's 0011.
- **Rate limiting on the consume path**: this is a real gap even in the
  reference implementation — a bare RPC that does `select ... where code =
  p_code` has no attempt limit, and Supabase's platform-level rate limits
  apply to GoTrue auth endpoints, not to arbitrary PostgREST RPC calls
  ([RapidDev rate limiting writeup](https://www.rapidevelopers.com/app-features/custom-roles),
  general rate-limiting guidance from
  [HackerOne](https://www.hackerone.com/blog/rate-limiting-strategies-protecting-your-api-ddos-and-brute-force-attacks)).
  **Unverified**: I could not confirm from documentation whether Supabase's
  project-level API rate limits (if configured) cover PostgREST RPC calls the
  same way they cover `/auth/v1/*` — treat this as needing direct
  verification against the actual Supabase project's rate-limit
  configuration before relying on it, and in the meantime add an explicit
  attempt counter (a small `invite_attempts(ip_or_user, code, attempted_at)`
  table checked at the top of the RPC, or move consumption into an Edge
  Function fronted by a rate limiter) rather than assuming platform coverage.

### Revoking / removing a member

Owner-only RPC. Rows the removed member authored (medications, dose logs,
visits, vitals) **stay in the group** — see §1 and §5 on why (`created_by`
`on delete set null` + a denormalized name snapshot). The membership row is
deleted (or soft-deleted with a `removed_at`, which is worth doing for audit
purposes — see §5).

### Member leaving voluntarily

Same RPC path (`leave_group`), self-service instead of owner-invoked. If the
leaving member is linked as a `subject` for a `care_recipients` row in that
group, null the `linked_user_id` on the way out (their care history stays;
they just stop being "the person who can press their own button" — a
caregiver has to hand the account link to someone else or leave it unlinked).

### Last owner leaving / transferring ownership

- `transfer_ownership(group_id, new_owner_user_id)` — owner-only RPC, sets
  the target's `role = 'owner'`, optionally demotes the caller to
  `'caregiver'` in the same transaction.
- `leave_group` should **raise, not silently no-op or silently cascade**, if
  the caller is the sole owner and other members remain — force an explicit
  `transfer_ownership` call first. Silent auto-promotion of "whoever's been
  in the group longest" is tempting for UX but removes the owner's ability to
  choose who inherits control of medical data; an explicit block with a clear
  error is safer for a family-trust product than an implicit choice.
- If the caller is the *only* member left entirely, `leave_group` should
  require the caller to call `delete_group` explicitly instead of implicitly
  deleting the group as a side effect of leaving — no destructive action
  should be reachable through a "leave" button without a distinct
  confirmation step.

### Account deletion (App Store 5.1.1(v) requirement, same as Bond)

`delete_account`, `security definer`, `auth.uid()`-gated exactly like Bond's.
Per group the caller belongs to:

- If they're the sole `owner` **and** other members remain: **auto-promote
  the longest-tenured `caregiver`** to `owner` inside the same transaction,
  rather than blocking deletion pending another user's action. Blocking
  account deletion on someone else's cooperation is both bad UX and a likely
  App Review objection (5.1.1(v) expects deletion to work, not "works if your
  sister answers her phone first"). Surface a warning in the UI before the
  user confirms, but don't make it a hard stop.
- If they're the sole `owner` **and no other members remain**: delete the
  whole group and everything under it — there's nothing left to preserve.
- If they're a linked `subject`: null `care_recipients.linked_user_id` for
  their row (payoff of the §1 two-table design — the medical history is
  untouched, only the account link goes away) and remove their membership
  row.
- If they're a plain `caregiver`: remove their membership row; their
  authored rows stay per §4/§5.

Then `delete from auth.users where id = p_user` — by this point no shared row
still references the caller as an FK owner in a way that would cascade into
other people's data, so the cascade is safe (same fix pattern as Bond 0010).

---

## 5. Audit trail

Recommendation, proportionate for a solo-developer indie app (this is a
consumer app, not a HIPAA-covered entity — no BAA, so this is a "responsible
design and good customer support" bar, not a compliance bar):

- **`created_by` / `updated_by` uuid columns, `on delete set null`, on every
  mutable table.** Cheap, already directionally present in the local model
  (`DoseLog.recordedBy` is free text today).
- **Also keep a denormalized `*_by_name` text snapshot** taken at write time
  (e.g. `dose_logs.recorded_by_name`) in addition to the FK. The FK gives you
  a live link (avatar, tap-through) while the author is still in the group;
  the text snapshot means "logged by Sarah" still reads correctly after
  Sarah is removed or deletes her account, without needing a join to a
  possibly-null profile.
- **A single generic `audit_log` table, populated by triggers only on the
  highest-stakes tables**: `medications` (create/update/delete — what a
  parent is actually prescribed), `dose_logs` (create/update — a changed dose
  status is exactly the kind of thing a family member should be able to
  review), `group_members` (role change, removal), `care_recipients` (edit).
  Skip triggers on `visits`/`vitals`/`emergency_contacts` for v1 —
  `created_by`/`updated_by` columns are enough there; adding triggers later
  is additive.
- Standard shape ([EDB writeup on Postgres audit triggers](https://www.enterprisedb.com/postgres-tutorials/working-postgres-audit-triggers),
  [OneUptime's trigger-based audit trail guide](https://oneuptime.com/blog/post/2026-01-25-postgresql-audit-trails-triggers/view)):
  `table_name`, `row_id`, `operation`, `actor_id`, `actor_name` (snapshot),
  `old_data jsonb`, `new_data jsonb`, `occurred_at`. Keep the jsonb diffs
  narrow (changed fields, not full row dumps) to avoid unnecessary PII
  buildup.
- Readable only by `owner`/`caregiver` of the relevant group (via
  `is_group_staff(group_id)`), for a future "activity history" screen — not
  visible to `subject`.

---

## 6. Anti-patterns and gotchas specific to this migration

- **Native Postgres enums for `role` are a trap here.** `ALTER TYPE ... ADD
  VALUE` cannot be used in the same transaction that also *uses* the new
  value, and Supabase CLI migrations are commonly one-transaction-per-file —
  adding `'viewer'` later would need care around transaction boundaries. A
  plain `text` column with a `check` constraint (which is what Bond already
  uses everywhere — `love_language`, `trigger_type`, `tier`) sidesteps this
  entirely and is a trivial migration to widen.
- **PostgREST schema cache staleness.** Every migration that adds or
  replaces a function or policy needs `notify pgrst, 'reload schema';` at the
  end — Bond hit exactly this in 0006 (`PGRST202`, function existed in
  Postgres but the API gateway hadn't refreshed its cache).
- **RPC parameter type overload ambiguity.** When PostgREST resolves an RPC
  call from a Swift client, a UUID sent as a JSON string can collide between
  `(p_x uuid)` and `(p_x text)` overloads (`PGRST203`, "could not choose the
  best candidate"). Bond hit this directly (0006 → 0007) and settled on a
  single `text`-typed parameter, cast to `uuid` inside the function body.
  Carry that convention into every new Aging RPC from the start instead of
  rediscovering it.
- **`on delete cascade` from `auth.users` through a *shared* row is the
  single most dangerous default in this schema.** Any FK chain that starts
  at a specific user's `auth.users` row and passes through a row shared by
  the group (a `groups` row, a `care_recipients` row) will delete other
  people's data when that one user deletes their account. This is precisely
  Bond's 0008→0010 bug, and Aging has *more* shared state than Bond (a
  `care_recipients` row's medical history is shared across every member of
  the group, not just two partners), so it's a bigger blast radius here if
  it recurs. `care_recipients`, `medications`, `dose_logs`, `visits`,
  `vitals`, `emergency_contacts`, `check_ins` should all cascade from
  `group_id → groups.id`, never from an individual member's profile.
- **Don't let migration files get hand-edited after they've shipped.** Bond's
  0012 exists because 0005 was rewritten after being recorded as "applied,"
  so production silently never received its actual content. Treat every
  migration as append-only once it has touched a real environment; fix
  forward with a new file, never edit history in place.
- **Recursive RLS on `group_members` will be hit on the very first policy
  you write for it if you don't reach for the security-definer helper
  immediately** — it's not a scale problem that shows up later, it errors on
  the first "list members of my group" query. Build `is_group_member` /
  `group_role` / `is_group_staff` before writing a single other policy.
- **`auth.uid()` wrapping and `group_id` indexing matter here even though
  today's groups are tiny.** `dose_logs` and `vitals` are exactly the tables
  that accumulate thousands of rows per recipient over years of daily use;
  retrofitting the wrap-and-index fix later means an emergency migration
  under load instead of a one-line convention followed from the first
  migration.
- **Don't build the "subject" reduced-access policies as `is_group_member(group_id)`
  with role checked only in the app layer.** If the *database* policy is just
  "any member of this group can read/write this table," a `subject`'s
  reduced UI is cosmetic, not a security boundary — a jailbroken or scripted
  client could read everything. Every table needs a role-aware policy, not a
  membership-aware one, everywhere `subject` should be blocked from
  something a `caregiver` can do.
- **Billing/subscription scope is an open product question, not resolved
  here.** `StoreService.swift`/RevenueCat currently ties the `pro` entitlement
  to a single device/account. Whether a group has one payer whose
  entitlement gates the whole group, or every member pays individually, is a
  real decision that affects the schema (does `subscriptions` key off
  `user_id` like Bond, or off `group_id`?) and is out of scope for this
  brief — flagging it so it isn't accidentally decided by default when the
  `subscriptions` table gets ported over.
- **Client-side SwiftData → Supabase migration/sync strategy is out of scope
  here too.** This brief only covers the target server schema
  (`care_recipients` replacing local `Person`, etc.); mapping existing local
  `Person.isSelf`, free-text `DoseLog.recordedBy`, and so on onto the new
  schema, plus the offline/sync story, needs its own research pass.

---

## SQL sketches

Design sketches only — table/column names, helper functions, and
representative policies for the recommended v1 shape. Not a final migration
(no down-migrations, no full RPC bodies for every lifecycle action, no
`notify pgrst` calls included per-statement — see §6 for why those matter at
migration time).

```sql
create extension if not exists "pgcrypto";

-- ============================================================
-- Profiles (1:1 with auth.users, member users only — NOT care recipients)
-- ============================================================
create table public.profiles (
    id           uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    phone        text,
    apns_token   text,
    created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_self_rw"
    on public.profiles for all
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- ============================================================
-- Groups
-- ============================================================
create table public.groups (
    id          uuid primary key default gen_random_uuid(),
    name        text not null default 'Family',
    created_by  uuid references public.profiles(id) on delete set null,
    created_at  timestamptz not null default now()
);

alter table public.groups enable row level security;

-- ============================================================
-- Group members (role lives HERE, never on profiles or care_recipients)
-- ============================================================
create table public.group_members (
    id          uuid primary key default gen_random_uuid(),
    group_id    uuid not null references public.groups(id) on delete cascade,
    user_id     uuid not null references public.profiles(id) on delete cascade,
    role        text not null check (role in ('owner', 'caregiver', 'subject')),
    invited_by  uuid references public.profiles(id) on delete set null,
    joined_at   timestamptz not null default now(),
    removed_at  timestamptz,
    unique (group_id, user_id)
);

create index group_members_user_idx on public.group_members(user_id);
create index group_members_group_idx on public.group_members(group_id);

alter table public.group_members enable row level security;

-- ============================================================
-- Helper functions (security definer — break the RLS recursion cycle)
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
    select public.group_role(p_group_id) in ('owner', 'caregiver');
$$;

create or replace function public.is_group_owner(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select public.group_role(p_group_id) = 'owner';
$$;

-- ============================================================
-- Groups / group_members policies
-- ============================================================
create policy "groups_member_select"
    on public.groups for select
    using (public.is_group_member(id));

-- No client insert/update policy on groups; created only via create_group() RPC.

create policy "group_members_select"
    on public.group_members for select
    using (public.is_group_member(group_id));

-- Deliberately NO insert/update policy here (see §3): role changes and new
-- memberships only happen via security-definer RPCs (accept_invite,
-- change_role, remove_member), never via direct PostgREST table writes.

-- ============================================================
-- Care recipients
-- ============================================================
create table public.care_recipients (
    id              uuid primary key default gen_random_uuid(),
    group_id        uuid not null references public.groups(id) on delete cascade,
    linked_user_id  uuid references public.profiles(id) on delete set null,
    name            text not null,
    relationship    text not null default '',
    birth_date      date,
    blood_type      text not null default '',
    color_index     int  not null default 0,
    allergies       text[] not null default '{}',
    conditions      text[] not null default '{}',
    notes           text not null default '',
    created_by      uuid references public.profiles(id) on delete set null,
    created_by_name text not null default '',
    created_at      timestamptz not null default now()
);

create unique index care_recipients_group_linked_user_idx
    on public.care_recipients(group_id, linked_user_id)
    where linked_user_id is not null;
create index care_recipients_group_idx on public.care_recipients(group_id);

alter table public.care_recipients enable row level security;

create policy "care_recipients_staff_select"
    on public.care_recipients for select
    using (public.is_group_staff(group_id));

create policy "care_recipients_subject_self_select"
    on public.care_recipients for select
    using (linked_user_id = (select auth.uid()));

create policy "care_recipients_staff_write"
    on public.care_recipients for all
    using (public.is_group_staff(group_id))
    with check (public.is_group_staff(group_id));

-- ============================================================
-- Medications (group_id denormalized — see §3 on why)
-- ============================================================
create table public.medications (
    id                 uuid primary key default gen_random_uuid(),
    group_id           uuid not null references public.groups(id) on delete cascade,
    care_recipient_id  uuid not null references public.care_recipients(id) on delete cascade,
    name               text not null,
    strength           text not null default '',
    form               text not null default 'tablet',
    purpose            text not null default '',
    prescriber         text not null default '',
    pharmacy           text not null default '',
    instructions       text not null default '',
    schedule_minutes   int[] not null default '{}',
    weekdays           int[] not null default '{}',
    is_as_needed       boolean not null default false,
    is_active          boolean not null default true,
    start_date         date not null default current_date,
    end_date           date,
    created_by         uuid references public.profiles(id) on delete set null,
    created_by_name    text not null default '',
    updated_by         uuid references public.profiles(id) on delete set null,
    updated_by_name    text not null default '',
    created_at         timestamptz not null default now()
);

create index medications_group_idx on public.medications(group_id);
create index medications_recipient_idx on public.medications(care_recipient_id);

alter table public.medications enable row level security;

create policy "medications_staff_select"
    on public.medications for select
    using (public.is_group_staff(group_id));

create policy "medications_subject_self_select"
    on public.medications for select
    using (
        exists (
            select 1 from public.care_recipients cr
            where cr.id = care_recipient_id
              and cr.linked_user_id = (select auth.uid())
        )
    );

create policy "medications_staff_insert"
    on public.medications for insert
    with check (
        public.is_group_staff(group_id)
        and exists (
            select 1 from public.care_recipients cr
            where cr.id = care_recipient_id and cr.group_id = medications.group_id
        )
    );

create policy "medications_staff_update"
    on public.medications for update
    using (public.is_group_staff(group_id))
    with check (public.is_group_staff(group_id));

create policy "medications_staff_delete"
    on public.medications for delete
    using (public.is_group_staff(group_id));

-- dose_logs, visits, vital_readings, emergency_contacts follow the same
-- shape as medications above: group_id denormalized, staff select/write +
-- subject self-select-only, staff insert re-validates care_recipient_id's
-- group_id matches.

-- ============================================================
-- Check-ins ("I'm OK" button) — auth keyed off linked_user_id, not role
-- ============================================================
create table public.check_ins (
    id                 uuid primary key default gen_random_uuid(),
    group_id           uuid not null references public.groups(id) on delete cascade,
    care_recipient_id  uuid not null references public.care_recipients(id) on delete cascade,
    source             text not null check (source in ('self', 'caregiver_manual')),
    pressed_by         uuid references public.profiles(id) on delete set null,
    pressed_at         timestamptz not null default now()
);

create index check_ins_recipient_pressed_idx
    on public.check_ins(care_recipient_id, pressed_at desc);

alter table public.check_ins enable row level security;

create policy "check_ins_staff_select"
    on public.check_ins for select
    using (public.is_group_staff(group_id));

create policy "check_ins_self_insert"
    on public.check_ins for insert
    with check (
        source = 'self'
        and pressed_by = (select auth.uid())
        and exists (
            select 1 from public.care_recipients cr
            where cr.id = care_recipient_id
              and cr.group_id = check_ins.group_id
              and cr.linked_user_id = (select auth.uid())
        )
    );

create policy "check_ins_staff_manual_insert"
    on public.check_ins for insert
    with check (
        source = 'caregiver_manual'
        and public.is_group_staff(group_id)
    );

-- A trigger (not shown) maintains care_recipients.last_check_in_at on
-- insert; a pg_cron job on a schedule (e.g. every 15 min) compares that
-- against a per-recipient checkin_window and calls an Edge Function to push
-- "No check-in from Mom today" to group staff when the window lapses.
-- https://supabase.com/docs/guides/functions/schedule-functions

-- ============================================================
-- Invite codes
-- ============================================================
create table public.invite_codes (
    code            text primary key,
    group_id        uuid not null references public.groups(id) on delete cascade,
    role_to_grant   text not null check (role_to_grant in ('caregiver', 'subject')),
    created_by      uuid not null references public.profiles(id) on delete cascade,
    expires_at      timestamptz not null,
    used_at         timestamptz,
    created_at      timestamptz not null default now()
);

alter table public.invite_codes enable row level security;

create policy "invite_codes_staff_select"
    on public.invite_codes for select
    using (public.is_group_staff(group_id));

create policy "invite_codes_staff_insert"
    on public.invite_codes for insert
    with check (
        public.is_group_staff(group_id)
        -- caregivers may only grant roles at or below their own level
        and (public.is_group_owner(group_id) or role_to_grant <> 'owner')
    );

create policy "invite_codes_owner_delete"
    on public.invite_codes for delete
    using (public.is_group_owner(group_id));

-- accept_invite(p_code text) — security definer RPC, mirrors Bond's
-- consume_invite_code: `select ... for update` row lock, checks expiry and
-- used_at, inserts the group_members row (this is the ONE place a
-- group_members row gets created for an invited path — never a direct
-- client insert), marks the code used, and — because there's no client
-- rate limit on this path today — should check/increment an attempt
-- counter before the code lookup. Also needs the p_code/uuid text-overload
-- convention from §6 if any uuid params are involved.

-- ============================================================
-- Audit log (generic, triggers attached selectively — see §5)
-- ============================================================
create table public.audit_log (
    id          uuid primary key default gen_random_uuid(),
    group_id    uuid not null references public.groups(id) on delete cascade,
    table_name  text not null,
    row_id      uuid not null,
    operation   text not null check (operation in ('insert', 'update', 'delete')),
    actor_id    uuid references public.profiles(id) on delete set null,
    actor_name  text not null default '',
    old_data    jsonb,
    new_data    jsonb,
    occurred_at timestamptz not null default now()
);

create index audit_log_group_occurred_idx on public.audit_log(group_id, occurred_at desc);

alter table public.audit_log enable row level security;

create policy "audit_log_staff_select"
    on public.audit_log for select
    using (public.is_group_staff(group_id));

-- populated by a generic trigger function attached to medications,
-- dose_logs, group_members, care_recipients only (§5) — no client
-- insert/update/delete policy; writes happen exclusively via the trigger,
-- which runs as the table owner and is unaffected by RLS.
```
