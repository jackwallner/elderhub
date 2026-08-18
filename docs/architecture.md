# Elderhub: family groups, roles, and proof of life

Design record for moving Aging from a local-only single-device tracker to a
multi-user family group app, without losing what makes the current app good.

Status: **signed off 2026-08-01**, open questions resolved in §13. Building from §12.

Sources: `docs/research/01-groups-rbac-rls.md`, `02-offline-sync-swift6.md`,
`03-consent-compliance-billing.md`. Those hold the reasoning and the citations.
This file holds the decisions and the build order.

---

## 1. What we are building and why

Origin (2026-08-01, family thread): *"a big red button of proof of life to send to
the family somewhere"*, plus *"family members that have deep features and the aging
parent has a subset."*

So: a family group. Adult children and spouses get the full app. The aging parent
gets a real account with a deliberately smaller surface, whose centre is one large
button that says they are OK. If that button is not pressed inside an agreed window,
the family gets told.

### The tension with `aso-plan.md`, resolved

`aso-plan.md` put shared accounts explicitly out of v1, because thirty apps in the
eldercare graveyard all led with exactly that and none of them cleared 40 ratings.
That finding still stands and this document does not overturn it.

What changes is the front door, not the finding. The dead apps led with *care
coordination*, a thing nobody searches for. We lead with the medication list, which
people do search for (`medication list` pop 23 / diff 23), and the proof-of-life
button is a *retention and word-of-mouth* feature rather than an acquisition one.
`daily check in` at pop 16 with a contested rather than walled SERP is a bonus, not
the plan.

The architectural consequence is a hard requirement, listed below as invariant I3:
**a single caregiver who never invites anyone must still get the whole med-tracker
app.** If the group becomes mandatory, we have rebuilt the graveyard.

---

## 2. Invariants

These are the things that constrain every decision that follows. If a later change
breaks one of these, the change is wrong.

- **I1. The emergency room works with no signal.** Someone is standing in an ER with
  no bars and needs Mom's medications, allergies and conditions on screen. No spinner,
  no login wall, no "couldn't reach the server". This is the app's actual job.
- **I2. The parent never hits a paywall on the check-in button.** Not a product
  convention, a structural property: the check-in write path contains no billing
  check at all.
- **I3. A solo caregiver with no group gets the full med tracker.** The group is
  additive.
- **I4. The parent's reduced view is a database boundary, not a UI state.** If the
  policy were "any group member", the parent's restricted screen would be cosmetic
  and a scripted client would read everything.
- **I5. Shared medical history outlives any one member.** Deleting your account must
  not delete the family's record of Mom's medications.
- **I6. Nothing claims to detect an emergency or summon help.** It notifies family.
  That is the whole claim.

---

## 3. Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| D1 | Supabase, new project `oygrxltpydcmmdtbreec`, Bond's patterns reused but not its database | Separate `auth.users` pool; health data does not sit beside couples data | user |
| D2 | Account required to use the app, with a full local mirror | I1 is satisfied by the mirror, not by the network | user |
| D2a | **Softened at build time (2026-08-02):** sign-in is skippable on the supporter and solo paths, required only to join a family | A hard login wall in front of the medication list contradicts I3 and §11, and puts a sign-in screen between a first-time user and the only thing they came for. Sharing needs the account, so sharing is where it is asked for | build |
| D3 | Cared-for person is `care_recipients`, separate from `profiles`, nullable `linked_user_id` | Dad has no phone and must still be fully tracked; Mom links to a real account | 01 §1 |
| D4 | Role lives on `group_members.role`, never on the user | Sandwich generation: owner in one group, subject in another | 01 §2 |
| D5 | v1 roles `owner`, `caregiver`, `subject`; `viewer` reserved, not built | Grows additively into per-recipient grants | 01 §2 |
| D6 | `text` + check constraint, not a Postgres enum | `ALTER TYPE ADD VALUE` has a transaction-boundary trap in CLI migrations | 01 §6 |
| D7 | Security-definer helpers (`is_group_member`, `group_role`, `is_group_staff`, `is_group_owner`), not JWT claims | Role changes take effect immediately; groups are tiny so live lookup is free | 01 §3 |
| D8 | `(select auth.uid())` in every policy; index every policy-filtered column | `dose_logs` and `vitals` grow to thousands of rows per recipient | 01 §3 |
| D9 | Denormalized `group_id` on every leaf table | Keeps policies join-free | 01 §3 |
| D10 | Lifecycle mutations go through security-definer RPCs; high-frequency writes stay direct | Bond 0004→0009 and 0008→0010 are what happens otherwise | 01 §3 |
| D11 | Every RPC parameter is `text`, cast to `uuid` inside | Bond 0006→0007 hit PostgREST overload ambiguity (`PGRST203`) | 01 §6 |
| D12 | Every leaf table cascades from `group_id`, never from a member's profile | Bond's 0008→0010 bug, with a bigger blast radius here | 01 §6 |
| D13 | Migrations are append-only once applied anywhere | Bond's 0012 exists because 0005 was edited post-apply | 01 §6 |
| D14 | Every migration ends with `notify pgrst, 'reload schema';` | Bond hit `PGRST202` in 0006 | 01 §6 |
| D15 | Check-in authorization keys off `linked_user_id`, not role | Makes the sandwich case fall out with no special-casing | 01 §2 |
| D16 | `currentSession` gates first paint; `emitLocalSessionAsInitialSession: true` | Verified in `supabase-swift` source, see §6 below | 02 §1 |
| D17 | Never sign out or drop cache on a caught error unless it is a definitive `invalid_grant` | Transport failure is offline, not signed out | 02 §1 |
| D18 | Existing client `UUID`s become the server primary keys | Makes push, retry and adoption idempotent via `ON CONFLICT (id) DO UPDATE` | 02 §2 |
| D19 | Server-time compound `(updated_at, id)` cursor | Device clocks are wrong; ties at a page boundary skip or duplicate rows | 02 §2 |
| D20 | Outbox for writes; coalesce `Medication` edits, never coalesce `DoseLog` | A dose log is an event, not a state | 02 §2 |
| D21 | Conflict handling asymmetric: dedupe dose logs, manual-resolve dosage and allergies, LWW for visits and vitals | Last-writer-wins on a drug dose is not acceptable | 02 §2 |
| D22 | Foreground sync + Realtime while foregrounded + silent push; background refresh is a bonus | iOS grants background refresh unreliably | 02 §2, §6 |
| D23 | `@ModelActor` sync engine, `@MainActor @Observable` UI service, DTOs across the boundary | Swift 6 strict concurrency | 02 §3 |
| D24 | `NSFileProtectionCompleteUntilFirstUserAuthentication`, set explicitly; no SQLCipher | Proportionate; full encryption is not a clean SwiftData fit | 02 §4 |
| D25 | Escalation is entirely server-driven (pg_cron + edge function + APNs) | Cannot depend on the parent's phone waking up | 01, 02 §6 |
| D26 | Parent's own daily reminder is a local `UNCalendarNotificationTrigger` | The one thing that must be reliable on-device | 02 §6 |
| D27 | Subject can leave unilaterally, behind a friction step, with a loud unmuteable notice to the group | The safety net is the announcement, not a lock on the door | 03 §1 |
| D28 | No-account recipients are created by explicit caregiver attestation | Do not simulate consent that did not happen | 03 §1 |
| D29 | The app never assesses capacity | That is a clinical judgment an indie consumer app has no business making | 03 §1 |
| D30 | Entitlement is group-scoped, held in a single `group_billing` row fed by a RevenueCat webhook | The adult child pays; nobody else should have to. No per-member fan-out to drift | 03 §6, modified, see §9 |
| D31 | Free tier: one care recipient, unlimited members on that recipient | Siblings are not "extra users"; the second parent is still the paywall | 03 §6 |
| D32 | Subject may log doses for their own linked recipient only | A parent who can press a proof-of-life button can tap "took my pills"; the alternative is the family phoning to ask | §13 Q1 |
| D33 | Not available in EU/UK storefronts | Article 9 special-category data about third parties who never consented, plus DSR and Article 27 obligations a solo developer cannot run | §13 Q3 |

---

## 4. Data model

### Server (Postgres)

```
profiles          id = auth.users.id, display_name, apns_token
groups            id, name, created_by, created_at
group_members     group_id, user_id, role ∈ {owner,caregiver,subject}, joined_at
care_recipients   id, group_id, linked_user_id?, name, relationship, birth_date,
                  blood_type, color_index, allergies[], conditions[], notes
medications       id, group_id, care_recipient_id, name, strength, form, purpose,
                  prescriber, pharmacy, instructions, schedule_minutes[], weekdays[],
                  is_as_needed, is_active, start_date, end_date, label_photo_path,
                  tracks_refills, quantity_remaining, units_per_dose,
                  refill_threshold_days, last_filled_at
bills             id, group_id, care_recipient_id, payee, amount, notes, category,
                  recurrence, due_at, is_auto_pay, paid_at, paid_by_name
dose_logs         id, group_id, medication_id, scheduled_at, recorded_at, status,
                  recorded_by, recorded_by_name, note
visits            id, group_id, care_recipient_id, date, provider, specialty,
                  reason, notes, follow_up, next_appointment
vital_readings    id, group_id, care_recipient_id, kind, primary_value,
                  secondary_value, recorded_at, note
emergency_contacts id, group_id, care_recipient_id, name, relationship, phone,
                  is_primary
check_ins         id, group_id, care_recipient_id, pressed_at, source, pressed_by
check_in_settings care_recipient_id, enabled, window_start_minute,
                  window_end_minute, timezone, grace_minutes
invite_codes      code, group_id, created_by, intended_role, expires_at,
                  consumed_at, consumed_by, attempts
group_billing     group_id, entitlement, expires_at, payer_user_id, updated_at
audit_log         id, group_id, actor_id, actor_name, action, entity, entity_id,
                  occurred_at, detail jsonb
```

Every table above carries `created_by` / `updated_by` (FK, `on delete set null`) plus
a denormalized `*_by_name` snapshot taken at write time, so "logged by Sarah" survives
Sarah deleting her account (I5). Every table carries `updated_at` (server-set) and
`deleted_at` (tombstone, no hard deletes) for sync.

Full SQL sketches, including the helper functions and policies, are in
`docs/research/01-groups-rbac-rls.md` under "SQL sketches".

### Vitals: where the numbers come from

Asked at review (2026-08-02): *"How will vitals data be shared? Does that assume
the grandparent will have Apple Health and that that data will then be synced
back to the admin?"*

**No. There is no HealthKit in this app and none is planned for v1.** Every
`vital_readings` row is typed in by a person, and it syncs through the same
group-scoped path as everything else, so whoever took the reading enters it and
the rest of the family sees it.

That is not laziness, it is the shape of the actual situation:

- **The reading and the phone are usually in different hands.** A caregiver
  visits, puts a cuff on Dad's arm, and types 142/88. Dad's phone, if he has
  one, was never involved. HealthKit on the subject's device would capture
  nothing in the common case.
- **HealthKit is per-device and per-person, and this data is neither.** Reading
  Mom's Health app requires Mom to grant authorization on Mom's phone, which
  means the feature only works for the subset of subjects who have an iPhone,
  use it, and can complete an authorization sheet. That subset is the opposite
  of the population this app is for.
- **Writing into the caregiver's Health app would be wrong data.** HealthKit
  has no concept of "this blood pressure belongs to my mother". Anything written
  there is attributed to the phone's owner and would corrupt their own record.

So the answer to a caregiver asking "how do I share Mom's blood pressure" is:
type it in, everyone in the group sees it. If HealthKit ever earns a place, it
is a *subject-side* import on a linked recipient's own device only, which is a
later, smaller feature and not a dependency of anything here.

### Client (SwiftData)

The six existing `@Model` types stay and keep their client-generated `UUID`s (D18).
Added to each: `updatedAt`, `deletedAt`, `isDirty`, `serverVersion`. Added as new
local models: `GroupMembership`, `CheckIn`, `OutboxEntry`, `SyncCursor`.

`Person` becomes the local mirror of `care_recipients`. Its existing `isSelf` flag
maps onto `linked_user_id == currentUserID`.

---

## 5. Roles and capabilities

| Capability | owner | caregiver | subject |
|---|---|---|---|
| Read meds, dose logs, visits, vitals, emergency card | all recipients | all recipients | own recipient only |
| Write meds, visits, vitals, emergency card | Y | Y | N |
| Log a dose | Y | Y | Y, own linked recipient only (D32) |
| Press "I'm OK" for self | n/a | n/a | Y, own recipient only |
| Log a check-in on someone's behalf | Y | Y | N |
| Receive escalation notifications | Y | Y | N |
| Invite a member | Y | Y, capped at caregiver-or-below | N |
| Remove a member, change roles, delete the group | Y | N | N |
| Manage billing | Y | N | N |

Every row here is enforced by an RLS policy, not by the UI (I4).

---

## 6. The offline guarantee

I1 is the requirement most likely to be quietly broken later, so it is worth writing
down exactly why it holds.

I read current `supabase-swift` `main` directly rather than relying on the brief:

- `currentSession` is `nonisolated`, synchronous, non-throwing, and reads straight
  from Keychain-backed storage (`AuthClient.swift:196-198`). First paint gates on
  this, never on `try await client.auth.session`.
- `emitLocalSessionAsInitialSession` exists and, when true, emits the cached session
  immediately regardless of expiry, then attempts a background refresh whose failure
  is swallowed with `try?` (`AuthClient.swift:1523-1537`). Its own doc comment: *"the
  locally stored session is always emitted, regardless of its validity or expiration."*
  It defaults to `false` and the SDK emits a `reportIssue` warning telling you to opt in.
- Every caller of `sessionManager.remove()` was traced. There is exactly one, inside
  `signOut()` (`AuthClient.swift:1095`). `refreshSession` on failure throws and does
  not delete the stored session.

Caveat worth carrying: a comment in `AuthClient` claims `refreshSession` emits
`signOut` itself, which the current `SessionManager` does not do. The SDK's comments
are drifting from its behaviour, so D17's app-level classification is not redundant
belt-and-braces, it is the actual guarantee. We own it, not the SDK.

Combined with the SwiftData mirror holding the last-synced snapshot and file
protection at `CompleteUntilFirstUserAuthentication` (readable after first unlock,
which is always true when someone is holding the phone in an ER), an offline cold
launch lands on the emergency card with real data.

**This gets a UI test that runs with the network disabled.** It is the one test that
must never be allowed to go red.

---

## 7. Onboarding

### Fork on first launch

> **Who are you here for?**
> - *I'm looking after someone* → supporter path
> - *Someone is looking after me* → subject path
> - *Just me, for now* → solo path

The third option matters (I3). It creates a group of one with the user as owner and
themselves as the care recipient, never shows an invite screen, and is a complete med
tracker.

### Supporter path
Sign in, name the group, add the first care recipient. If that recipient will use the
app, generate an invite code. If not (Dad, no phone), the attestation step from D28
fires instead.

### Subject path
Sign in, enter the invite code, then land on the transparency screen **before any data
syncs**: who is in this group, their role, and exactly what each can see about you.
Exact copy is in `03 §Appendix`.

---

## 8. Check-in and escalation

- Parent's home screen is one large button. Pressing it writes a `check_ins` row.
  It works offline (queued in the outbox) and says so honestly.
- `check_in_settings` holds the agreed window in minutes-from-midnight plus an IANA
  timezone, matching the existing `scheduleMinutes` convention so it survives travel.
- A pg_cron job runs every 15 minutes, finds recipients whose window plus grace has
  passed with no check-in, and calls an edge function that pushes the caregivers.
  Server-driven, so it does not depend on anyone's phone (D25).
- Language boundary (I6, 03 §2): never "alert", "emergency", "911", "help is on the
  way", "monitoring". The push body is a statement of fact, not an assessment:
  *"No check-in from Mom today."* Exact strings in `03 §Appendix`.

---

## 9. Billing

**Decided: group entitlement row.** Brief 03 recommended RevenueCat's documented
per-member promotional-entitlement pattern; we are using a variation.

One IAP product, no seat concept. Apple has no native seats for consumer
subscriptions, so group size is our own backend's business, exactly as Life360 caps a
Circle at six. The purchase itself is ordinary IAP, which is all guideline 3.1.1
requires; nothing in 3.1.2 speaks against a backend applying one purchase to a group,
and Life360 is the standing precedent that it passes review.

Flow: owner buys, a RevenueCat webhook hits an edge function, the function writes one
`group_billing` row. Entitlement resolves as
`payerRevenueCatEntitlement || groupBilling.entitlement`. The payer's own device
unlocks instantly from the RC SDK with no round trip; everyone else resolves through
the group row, which already syncs and is already cached locally, so it survives
offline.

Why not per-member promotional entitlements: fan-out. Every join, leave and removal
would have to call RevenueCat's REST API, creating a second source of truth that can
drift, needing the RC secret key server-side, and failing silently (a sibling with no
Pro and no error anywhere). With the entitlement on the group, membership changes run
no billing code at all.

I2 holds unconditionally regardless: the check-in path checks nothing but
`linked_user_id`, and the client never renders a paywall on that screen.

---

## 10. Consent, privacy and compliance

- Transparency screen ("Who can see me") is first-class for any linked subject,
  one tap from their home screen, not buried in Settings (D27).
- Leaving is possible, gated behind re-typing a phrase, and announced immediately and
  unmuteably to every caregiver (D27).
- Adding a no-account recipient requires explicit caregiver attestation, logged to
  `audit_log` (D28).
- The app never assesses capacity and says so in plain language (D29).
- App Privacy answers move from "Data Not Collected" to Health & Fitness, Contact
  Info, Identifiers and User Content, all linked, none used for tracking.
  `PrivacyInfo.xcprivacy` needs collected-data-type entries, and the required-reason
  API list must be checked against Xcode's build-time privacy report rather than
  guessed (brief 03 could not verify Apple's current reason codes and labelled it so).
- Account deletion (App Review 5.1.1(v)) routes through the `delete_account` RPC,
  which separates deleting an account from deleting the family's history (I5).
- **Washington's My Health My Data Act is the highest-rated legal exposure**, above
  HIPAA (which does not apply here at all) and above GDPR. No revenue threshold, and
  a private right of action via the WA Consumer Protection Act with a first suit filed
  Feb 2025. Its consent bar (specific, opt-in, not bundled into terms) is cheaper to
  build once for everyone than to geofence. Not legal advice, and worth a lawyer's
  hour before launch given this is third-party health data.
- CPRA's HIPAA/CMIA carve-out does **not** rescue this app, since that exemption needs
  the data to be governed by HIPAA or CMIA in the first place.
- Privacy policy and terms need to exist and be hosted. Aging has no marketing site;
  Bond's GitHub Pages `docs/` pattern is the template.

---

## 11. Migration from the current build

Nobody is on the App Store yet (TestFlight build 4), which makes this cheap. Still:

- Local data stays local-only and fully usable until the user opts into an account.
- Adoption is a sequence of idempotent upserts keyed on existing client UUIDs,
  resumable after a kill at any point.
- It never mutates or deletes local rows while adopting them.
- Abandoning signup halfway leaves the user exactly where they started.

Brief 02 proposed an `adopt_local_group` RPC for this. Dropped: since the local
`UUID`s are already the server primary keys (D18), adoption is just "stamp the new
`group_id` on the local rows, mark them dirty, run the sync engine". That is the
ordinary write path, already idempotent through `ON CONFLICT (id) DO UPDATE` and
already resumable through the outbox. A dedicated RPC would be a second code path
doing the same job, with its own failure modes to test.

---

## 12. Build order

Each phase ends green and is committed. No phase leaves the app unbuildable.

1. **DONE. Schema.** Migrations 0001-0006, applied live to `oygrxltpydcmmdtbreec`.
   16 tables, all RLS on, 42 policies, 26 functions, 23 triggers. 64 assertions in
   `supabase/tests/` via `scripts/test-db.sh` (no Docker). Anonymous access verified
   blocked through PostgREST against the real project.
2. **DONE. Client foundation.** `SupabaseConfig`, `AuthService`, Sign in with Apple,
   offline session handling (D16, D17), file protection on the store.
   *Outstanding from this phase: the offline-launch UI test still needs writing.*
3. **DONE. Sync engine.** `@ModelActor`, outbox with per-entity coalescing, compound
   server-time cursor, asymmetric conflict handling, `SyncRemote` protocol plus a
   fake. 9 sync tests, 36 unit tests total.
4. **DONE. Groups and invites.** `GroupService` over the RPCs, `SyncCoordinator`,
   the three-way onboarding fork, Sign in with Apple screen, join-by-code,
   invite sheet (caregiver and subject kinds), and the Family tab.
5. **DONE. Roles.** `CareGroup.role` is cached locally so gating works offline.
   The subject gets a different root (`CheckInHomeView`), not a greyed-out
   caregiver app. Owner-only controls hidden; RLS still the enforcement (I4).
6. **DONE. Check-in.** The button, `CheckInService`, the local
   `UNCalendarNotificationTrigger` reminder, `check_in_settings` wired through
   the sync engine, migration 0007 (pg_cron every 15 min, `group_notices`,
   `queue_check_in_notices`), and the `escalate-check-ins` edge function with
   APNs ES256 provider tokens.
   *Outstanding: the APNs key and the two Vault secrets are environment setup,
   not code. See §15.*
7. **DONE. Consent and compliance.** Transparency screen (shown before any sync
   on the subject path, one tap from their home screen after), surrogate
   attestation with a server-side stamp, leave flow behind a typed phrase,
   account-deletion sheet, `PrivacyInfo.xcprivacy` rewritten off
   "Data Not Collected", and the privacy policy, terms and support pages in
   `docs/`.
   *Outstanding: hosting those pages needs a repo. See §15.*
8. **DONE. Billing.** `revenuecat-webhook` edge function writes the single
   `group_billing` row; `StoreService.identify()` ties the RevenueCat customer
   to the Supabase user id (without it the webhook has nobody to credit);
   entitlement resolves as `store.isPro || groups.hasPlus` at both paywall sites.
9. **IN PROGRESS. Ship.** Build 10 is uploaded, valid and attached to the 1.0
   draft in TestFlight. Store metadata is uploaded. Territory restriction (D33)
   is scripted in `scripts/asc-restrict-territories.py`, but cannot run yet: the
   app has no `appAvailabilityV2` record at all until the first release is
   configured in App Store Connect, so there is nothing to restrict. Re-run it
   the moment that exists, and before the app goes on sale. ASC privacy answers
   and first-release availability are UI-only. The Regulated Medical Device
   declaration is complete for this release.

---

## 15. Environment setup this code assumes

Everything here is a one-time console or CLI step, deliberately not committed.

| What | Where | Why it is not in the repo |
|---|---|---|
| APNs auth key (`.p8`), key id, team id | `supabase secrets set APNS_*` | Private key |
| `escalation_function_url`, `escalation_service_key` | Supabase Vault, names hardcoded in 0007 | Service-role key |
| `REVENUECAT_WEBHOOK_SECRET` | Supabase secrets + RevenueCat webhook header | Shared secret |
| RevenueCat webhook URL | RevenueCat → Integrations → Webhooks | Console-only |
| `docs/` on GitHub Pages | the `jackwallner/elderhub` repo | Public source repo and Pages site |
| App Privacy answers | App Store Connect UI | Not exposed in the ASC API |
| Apple auth provider: enabled, client id `com.jackwallner.aging`, email optional | Supabase → Auth → Providers (or `PATCH /v1/projects/{ref}/config/auth`) | Project config, not schema, so no migration carries it |

The Apple provider row is the one that has already bitten us. It defaults to
off, nothing in the repo asserts it, and with it off `signInWithIdToken` fails on
a correctly signed token from a correctly entitled build: the first tester to
tap Sign in with Apple (2026-08-05) got a red error and there was no bug to fix
in the app. `external_apple_email_optional` matters too, because
`prepareAppleRequest` asks only for `.fullName`, so Apple's token carries no
email claim and GoTrue would otherwise refuse to create the user. Neither
setting needs a build: flipping them fixes every version already installed.

---

## 13. Decisions taken at sign-off (2026-08-01)

**Q1. Can the subject log their own doses? Yes**, for their own linked recipient only
(D32). Brief 01 argued no. Overruled: a parent capable of pressing a proof-of-life
button is capable of tapping "took my morning pills", and if she cannot, the family
has to phone and ask, which is the exact chore this app exists to remove.
`DoseLog.recordedBy` already exists, so a caregiver still sees "logged by Mom" versus
"logged by Sarah".

**Q2. Billing: group entitlement row** (D30, §9). Brief 03's per-member promotional
entitlements declined on fan-out grounds.

**Q3. EU/UK: not available** (D33). Territory availability is set in App Store Connect
and applies to the app, not to a version, so this also removes the current local-only
build from those storefronts. Revisit when there is revenue to justify a real GDPR
posture. Note this cuts against the fleet PPP pricing work; that is accepted.

---

## 14. Out of scope

Fall detection, GPS and location sharing, life-alert or emergency dispatch of any
kind, paid-caregiver shift scheduling, password or credential storage, legal and
estate document vaults, and any read-only `viewer` role.

**Free-form notes (`care_notes`, migration 0014, 2026-08-05) are not a reversal
of the credential-storage line, and the distinction is load-bearing.** A tester
asked for a password vault. What shipped is an unstructured note per recipient,
because the schema cannot anticipate the gate code, the policy number or what to
ask the neurologist next time, and every attempt to model those produces a form
people leave empty. What did not ship is any of the machinery a vault needs: no
client-side encryption, no key, no Face ID gate, no field typed "password", and
no copy anywhere inviting credentials in. The body is ordinary text under the
same RLS as the medication list, and the editor says so on the screen before
anyone types. If the product ever does want a vault, the answer is still the one
in §15: end-to-end encryption with a family passphrase, `care_notes.body`
becoming ciphertext, and the key never touching Postgres. Bolting secrets onto
the plaintext table is the outcome this note exists to prevent.

**Bills (`bills`, migration 0017, 2026-08-09) sit on the same line, and are the
place it is most likely to be crossed.** A screen headed "Bills" is exactly
where a family will put the online banking login if the app leaves a box open
for it, so the table has no account-number, reference, card or login column, the
editor's footer says so where someone is about to type, and `notes` is ordinary
text under the same RLS as everything else. The other half of the boundary is
that nothing here pays anything: `paid_at` records that a human says they paid
it, the way `dose_logs.status` records that a human says a tablet was swallowed.
No bank connection, no reminders to a payee, no chasing. The feature exists
because the family was using `care_notes` for it and a note cannot answer "what
is due" or "did anyone pay it", which are the only two questions it answers.

"Care-team task boards" was on this list until 2026-08-04, when a **family**
to-do list was built instead (`care_tasks`, migration 0012). The distinction is
load-bearing and the boundary has not moved: a task belongs to one care
recipient, is assigned by writing a name on it, and notifies nobody. What stays
out is the shift-scheduling, rota and paid-staff-coordination product that
phrase referred to, which sits next to paid-caregiver scheduling for a reason.
The first three are liability surfaces we are deliberately not touching (I6); the rest
were priced against Astro in `aso-plan.md` and found at the popularity floor.

---

## 16. Making the app legible (2026-08-05)

The build had eighteen real features and a user who could not find them. Opening
the app, the verdict was that it was "not really clear what features it has",
which was a fair reading of what was on screen: `PersonDetailView` was twelve
grouped-list sections of identical weight, each a grey row with a grey glyph, and
nothing anywhere said what any of them were for.

Competitor research (report in the session scratchpad; sources are in it) landed
on one direct analog. Caring Village ships a "Village Builder", a dismissible
setup checklist pinned to the dashboard, built explicitly because "the app has
many different sections and can be a little confusing at first" - the same
problem, from a company that had already hit it. Medisafe and CareZone reviews
show the failure mode when nobody fixes it: users report giving up looking for
features that exist. MedM's dashboard is credited by its own users for showing
real values rather than icons. Round Health is the boundary in the other
direction: a ring-only home screen reads as "limited", so the answer is hierarchy,
not hiding.

What changed:

- **`CareFeature`** (`Shared/Services/CareOverview.swift`) is the single catalog:
  every feature's title, one-line blurb of what it is *for*, symbol and colour.
  The person hub, the Today quick-action row and the People rows all read it, so
  a feature added in one place cannot go missing in the other two.
- **`PersonDetailView` is a hub**: person header with the three numbers worth
  acting on, a dismissible setup checklist, medications inline (they are what the
  screen is for), then tiles grouped "Every day" and "Records", then the
  emergency card as a banner of its own rather than the last row of a list.
- **`SetupChecklist`** is the feature tour, framed as the user's own unfinished
  setup rather than a walkthrough nobody reads. Six steps, each with the reason
  it is worth doing, dismissible per person, and gone once complete.
- **The Today tab** carries a quick-action row, because the app's range has to be
  visible on the screen people actually open.

Two constraints held throughout. Every string is a statement of what is recorded
and never an assessment (I6): the check-in tile says "Not yet today", never
anything about how someone is. And no tile carries an upsell; the paywall stays
where it already was, on adding a second care recipient in `PeopleView`.

The tab bar was not touched. Four peer tabs is what the HIG asks for and it was
not the problem.

---

## 17. Getting the invitation out of the phone (2026-08-09)

The invitation is the only part of this app that leaves the device as plain text
and is read by someone who has never seen it. Every failure in that hop is silent,
so this section is a record of the four that were live and what replaced them.

- **The message led with `elderhub://invite?code=`.** That address is meaningful
  only on a phone that already has Elderhub. Mail on a phone without it answers
  "Safari cannot open the page", and a desktop client will not even draw it as a
  link, so the person most likely to be invited (the parent who has installed
  nothing) was handed the one address that could not help. Messages now lead with
  `docs/join.html?code=...`, a page that shows the code, offers "Open in
  Elderhub" for phones that have it, and says where to get it for phones that do
  not. The custom scheme is reached from that page by a tap, never from mail.
  The page makes no request of its own: a code in a URL is a bearer token for one
  membership, so nothing about it is reported anywhere.
- **A tapped invitation could reach a signed-out phone with no way to sign in.**
  An existing solo install has people and a finished onboarding flag, so it lands
  in the tabs rather than in onboarding, and the deep link opened the join sheet
  directly. The only control there was a Join button that answered "Sign in
  first." `JoinGroupView` now shows the sign-in step itself when there is no
  account, which covers both entry points.
- **A link arriving while onboarding was already on screen was swallowed**, since
  `onAppear` had already run. The flow now watches the code as well.
- **Expired invitations still offered Share and Email again.** Sending a dead code
  is worse than sending nothing: the recipient types it in, is told it did not
  work, and distrusts the next one. Expired rows can only be cleared.

Elderhub still sends no mail of its own. `intended_email` labels the invitation
and prefills a composer; the caregiver presses send. The invite sheet says so at
the point of entry rather than after the fact, because "Create" otherwise reads
as "Send". `Shared/Services/InviteLink.swift` is the one place that knows the
shape of a code, the link that carries it and the message around it, and its
email validation is the server's own regex so the UI and a 22023 cannot disagree.


---

## 18. What the 2026-08-09 audit changed

An end-to-end audit (`../archive/laudit89.md`, written by an unverified agent and treated as
leads rather than findings) turned up a mixture of real defects, deliberate
choices it had misread, and two things that were structural. Everything below was
reproduced in the source before it was touched.

**Identity.** `Person.displayLabel` returned the *relationship* whenever one was
set, so a record entered as "Eleanor" was titled "Mom" on Today and on the person
hub while the Care row and the emergency card said "Eleanor", and a solo record
read "Me's care record". Two labels for one row is not a naming preference in an
app someone opens in an ER: the reader cannot tell whether the record in front of
them is the one they meant to open. The entered name is now the identity
everywhere and the relationship is the subtitle it always was. Dose reminders
carry the name too, which matters most on a phone tracking two parents.

**Refills stopped working exactly when they mattered.** `quantity_remaining == 0`
meant both "not tracked" and "empty", so taking the last dose clamped the count
to zero, zero read as untracked, and the medication that had just run out dropped
out of Running low, loaded with its refill toggle off, and could not have the
dose undone. `tracks_refills` (migration 0016, backfilled from the old sentinel)
splits the two, `daysRemaining` now returns zero rather than nil for an empty
tracked bottle, and Today says "None left".

**Deleting a health record asks first.** Medications, visits, vitals, providers,
notes and incidents all removed a row on one horizontal swipe, with no
confirmation and no undo, and the tombstone propagates to the rest of the family.
Person and contact deletion already confirmed, which made the gap odder rather
than better. `PendingRecordDeletion` is the one dialog all of them use, and each
message names what goes with the row (the dose history, the gap in a vitals
series) and whether the delete leaves this phone. Tasks deliberately still delete
on a swipe: a chore is not a health record and ticking the list over should stay
frictionless.

**The two worlds are drawn apart.** Every people query returned every
non-tombstoned `Person`, so someone who tracked a parent privately and later
accepted a sibling's invitation saw both sets in one list; only the billing count
was group-scoped. That is a data boundary, not a label: the private row looked
shared, Today could default to it, and a caregiver could invite against it. The
Care tab now renders two named sections when both exist, Today defaults to a
shared record, the person picker marks private rows, and the invite sheet only
offers rows the circle actually holds. Joining still adopts nothing:
`SyncEngine.adoptPerson` moves one record across, from an explicit tap behind a
dialog that says it cannot be undone. Uploading everything on someone's phone
because they accepted an invitation is a disclosure, not a migration.

**Conflicts have somewhere to go.** The engine's rule was already right (keep
both sides and ask, because last-writer-wins is not acceptable for a dosage) but
Settings only counted the flagged records, with no destination and no action.
`ConflictsView` lists them with what they are and whose they are, and offers
"Keep mine" (requeue the push) or "Use theirs" (drop the queued write, mark the
row clean, and rewind that table's cursor so the server copy arrives through the
ordinary pull). Rewinding re-applies a few already-applied rows, which is free:
every apply is an upsert.

**Who can see me, offline.** `GroupMember` lived only in `GroupService`'s memory,
so a cold launch with no signal showed the subject an empty transparency list.
Consent to being watched means nothing without the list of who is watching, so
members are cached in SwiftData (`CachedGroupMember`, local only, never written
by the client to the server) and the remaining gap says so explicitly instead of
rendering a blank box.

**Smaller, and all reproduced:** the "Invite the family" checklist step ticked on
`isInGroup`, which onboarding satisfied instantly, so an owner with zero invites
was told sharing was done; the check-in window silently clamped an overnight
8 PM - 8 AM entry to a one-minute window on the way out (the pickers now keep the
pair ordered on screen and the footer says the window cannot cross midnight,
which is what the table's check constraint and the escalation job both assume);
the plain-text export dropped the blood-type line when it was empty while the
emergency card printed "not recorded"; the setup card said "0 of 6" over three
rows with no hint that three more existed; Today's task rows showed nothing for a
task due today; the Notes empty state suggested keeping the gate code there while
the editor warned it was not a vault; and the paywall showed three identically
prominent buttons with raw prices, which is the user doing the arithmetic.

**Not changed.** The audit's floating-tab-bar clipping was not reproduced in
source review and needs a device pass. Its reading of `join.html` ("coming to the
App Store shortly") is accurate today, since the app is prelaunch; that line is a
release gate, not a bug, and has to change in the same pass that submits.

---

## 19. Whose phone is this, and the size of everything (2026-08-10)

A second round of the same complaint as §16, from the same direction: a TestFlight
build of the Today tab, and the reaction was that the setup checklist was at the
bottom rather than the top, that it was visibly narrower than the cards above it,
that "Doses" was a strange thing to head the screen with when no medication had
been entered, that "Medical" behaved differently from every chip beside it, that
the controls were small, and that nothing anywhere said whether the phone belonged
to the person giving care or the person getting it.

### The screen

- **The setup card leads.** It was last on the argument that getting set up is not
  what today is. That is true of a record with a month of history and wrong of the
  only screen a new user ever sees: a checklist below the fold is a checklist
  nobody works through. What makes leading fair is that it now dismisses **per
  row** (`SetupStepPreferences`, keyed by person and step) as well as whole
  (`SetupCardPreferences`). The reasons are per row: "I am the only one looking
  after him" is a fair answer to inviting a sibling and a terrible reason to lose
  the other five. `PersonDetailView` and Settings both offer the way back, and
  `PeopleView`'s "3 of 6" line counts the visible steps so the two agree.

  **This reverses §16's ordering, and the cost is named here rather than
  discovered later.** The card was put last because an emergency card you have
  to scroll a checklist to reach is the one thing this app cannot afford. That
  cost is now paid, but only on a record with nothing in it: the checklist plus
  the action grid push the two big cards below the fold on first launch, and
  `NavigationFlowUITests` had to start scrolling to find them. It is acceptable
  in that state and nowhere else, because a record with an unfinished checklist
  at the top is a record whose emergency card is mostly "Not recorded" - there is
  nothing on the page being buried. The moment the checklist is finished or
  dismissed it disappears and the cards move back up. If the checklist ever
  becomes undismissable, or starts persisting on records that are actually in
  use, this ordering has to go back.
- **Card rows lost their double inset.** Every `listRowInsets` on a card row
  carried `leading: 16` on top of the inset-grouped section's own margin, so the
  setup card, the tile grids and the header card were all 16pt narrower on each
  side than the ordinary list sections next to them. They are `leading: 0` now,
  which is what makes a card the same width as the section above it.
- **Doses appear only once a medication does.** A "Doses" heading over "No
  medications yet" is a section about an absence, taking the top of the daily
  screen to announce that a feature exists, on the one record where the card above
  it is already saying so and offering the button. Most people this app is for
  have medications; the empty case should not be what the layout is built around.
  With medications and nothing scheduled it still says so, because that is a fact
  about the day rather than about the app.
- **Medical pushes `MedicalRecordView` instead of dropping a menu.** One tap
  gesture producing two different kinds of thing is disorienting on its own, and
  the menu also offered six bare words with no indication of what was in any of
  them. The new screen is the same six as `FeatureTile`s, reading
  `QuickAction.medical.members` so the chip and the screen cannot drift.
- **Bigger, throughout.** `QuickActionChip` is a 56pt glyph on a card at body
  weight rather than a 44pt glyph and a subheadline; the emergency card and the
  full record are `BigNavCard`s rather than two list rows carrying the same visual
  weight as a settings toggle; the setup rows are 40pt glyphs with subheadline
  detail. The audience is mostly over fifty and often reading in a waiting room.

### Onboarding

`OnboardingDetailsFlow` runs after the person is named: date of birth, allergies,
conditions and blood type, an emergency contact, a first medication, a doctor and
a pharmacy, dose reminders, and the family. **Every step skips**, in the same
place with the same weight on every screen. That is not politeness, it is what
makes a flow this long safe to put in front of someone on the day their mother
came out of hospital. The add-things steps present the *real* editors
(`MedicationEditorSheet`, `EmergencyContactEditorSheet`, `ProviderEditorSheet`)
rather than cut-down copies, so the two cannot drift. Anything skipped reappears
on the Today checklist, and Settings → "Set up \<name> again" re-runs the whole
flow and restores every dismissal.

### Whose phone is this

Two axes, deliberately named differently everywhere, because conflating them is
how this ends up wrong:

| | `GroupRole` | `DeviceMode` |
|---|---|---|
| what it says | what this **account** may read and write | who is holding **this handset** |
| where it lives | `group_members`, enforced by RLS | `UserDefaults` on one device |
| who changes it | the circle's organizer | whoever has the phone |
| how often | once | several times a day |

`DeviceModeService` is the second one. Settings names both ("This phone" /
"In this care circle"), which is the first time the app has said either outside
the Sharing tab. Handing over swaps the root to `CheckInHomeView` — the same
screen the subject role gets, because it is the same person in the same
situation — and a four-digit caregiver code swaps it back. The code is a salted
SHA-256 in `UserDefaults`; it guards against a confused tap in a family, not
against an adversary, and the data it covers is on the same screen by design.

Three rules the lock does not get to break:

1. **The emergency card is never behind it.** It is on the handed-over screen and
   reachable without the code. The whole point of that page is the ten minutes
   when nobody can remember a passcode.
2. **No billing check, at any depth.** `DeviceModeService` does not import
   `StoreService` (I2), the same as `CheckInService`.
3. **Removing the code returns to the caregiver's app**, or a phone left in
   recipient mode is a door with no handle.

A subject whose *account* holds the subject role sees no unlock button: their
reduced surface is RLS, not a local preference (I4), and offering them a keypad
would imply otherwise.

**The handover names its person (2026-08-11).** The first version stored only the
mode, so `CheckInHomeView` had to work out whose screen it was showing: the row
linked to the account's user id, and failing that `isSelf`, and failing that the
first person in the store. On the household this app is actually built for, two
recipients is the ordinary case, and that last fallback hands Dad the phone
showing Mom's medications and logs *her* check-in when he presses the button.
Wrong person is worse than no person. So `DeviceModeService.handOver(to:)` takes
the id, Settings asks with a button per candidate whenever there is more than one
(the user's own record is not a candidate), and the check-in screen prefers that
id over any inference. Coming back to the caregiver clears it, including via
`clearPIN`, so the next handover cannot silently reuse whoever held it last. Nil
stays a valid state: one record, or a handset handed over by an older build,
falls back to the old resolution rather than showing nothing.

## 20. Whose errand is this (2026-08-11)

Two gaps in the shared to-do list, both of them the same shape: the data was
already there and nothing read it.

### The periods a family actually repeats on

`CareTaskRecurrence` offered never / daily / weekly / monthly / yearly. Almost
everything a family repeats for a parent sits in the gap: reorder hearing aids,
book the audiologist, review the repeat prescription, change the water filter.
With only monthly and yearly available the choice was between dismissing a
reminder five times and missing it once, and both teach people to stop trusting
the list. `quarterly` and `halfYearly` close it, with the same labels and the
same `DateComponents` steps `BillRecurrence` has had from the start.

No migration. `recurrenceRaw` is a string in a column that already exists, and
an older client reading a value it does not know falls back to `never` rather
than crashing, which is the entire reason the enums are stored as strings. A
test asserts every case except `never` has a step, so adding one later cannot
quietly turn a repeat into a one-off.

### Reading the assignee

`assigneeUserID` was written by the editor and pushed by the sync engine, and
that was the end of it: nothing filtered, counted or displayed by it, and the
editor said outright that assigning someone was "a note for the family". With
three siblings in a circle that is where assignment starts paying.

`TaskPlanner.isAssigned(_:to:named:)` is the single matching rule:

- The id wins whenever both sides have one. Two siblings called Chris is exactly
  the case a name cannot answer, so the name must not second-guess the id.
- The name is the fallback, not the rule. `assigneeUserID` is only set when the
  assignee was picked from a loaded member list, and typing a name on a phone
  that has never been online is a supported way to assign someone (I1).
- A task that *has* an id, read on a device whose member list has not loaded
  yet, falls back to the name too. `selfUserID` is nil until `loadMembers()`
  has run, and reading that as "nothing is yours" would leave the filter empty
  on every launch.

Where it surfaces:

- **Tasks screen**: an Everyone/Mine segmented control, shown only when someone
  else is actually in the circle. Alone, the device has neither an id nor a name
  to match on, so the control could only ever be empty. It is not persisted: a
  filter that survives relaunch is one people forget is on, and what that
  produces here is a sibling concluding the family has nothing left to do. An
  empty "Mine" says how many open tasks the filter is hiding and offers the way
  back, because an empty result and an empty list are otherwise the same picture.
- **Today**: not filtered. Today answers "what is left for her", and a screen
  that hides a sibling's overdue errand answers a different question. Whose it
  is goes on the row instead, and the reader's own name is replaced with "You".

Assignment still notifies nobody, and the editor footer still says so in the
place it matters: filtering a list is a long way from telling someone.

`-uitest-family` (DEBUG only) seeds a two-person circle straight into the local
membership cache, because none of the above is visible without one and a real
circle needs an account and a server round trip a headless simulator has
neither of. It reseeds with new ids every launch: the pool devices keep their
store between runs, so a circle carried over would leave the previous run's
tasks still assigned to this run's reader and no test could assert that nothing
is.
