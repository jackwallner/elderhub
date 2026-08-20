# plan84: what stands between this build and a guaranteed-working 1.0

Written 2026-08-04 against commit `68556bc`. Every claim below was checked against
the live systems (App Store Connect, the `oygrxltpydcmmdtbreec` Postgres, the
Supabase Functions API, the RevenueCat offerings API, a leased simulator), not
against the docs. Where a doc and reality disagree, reality is recorded here.

The short version: **112 unit tests, 3 UI tests and 105 SQL assertions are green,
and the app does not sync at all.** Not partially, not for one entity, nothing
leaves the phone and nothing arrives, on every cycle, for every user. The tests
pass because the fake remote used to test sync cannot fail the way the real one
does, and the app looks healthy because the "Last synced" indicator reports
success on a failed cycle.

Around that sit the environment gaps: the production database is three migrations
behind the client, no edge function has ever been deployed, no secret is set,
push notifications were never enabled on the App ID, and the marketing site the
App Store listing points at does not exist.

The good news is that the pure logic is genuinely solid, the structural
invariants hold, and the worst defect is fixed by one script plus about thirty
lines of error handling.

---

## 0. Verified-green baseline (do not re-litigate these)

| Check | Method | Result |
|---|---|---|
| Build + full test suite | `xcodebuild test` on leased sim `2C7A80C1` | exit 0 |
| Unit tests | Swift Testing `@Test` count | 112 passing |
| UI tests | XCTest | 3 passing |
| SQL assertions | `scripts/test-db.sh` (local pg17, no Docker) | 105 passing, all 11 migrations apply clean |
| App launches and renders | `simctl install` + `launch` + screenshot | Today tab renders, tab bar correct |
| I2 (no billing in check-in path) | grep `StoreService|isPro|hasPlus` in `CheckInService` + `Views/CheckIn/` | zero hits outside comments |
| I6 (no emergency claims) | grep `911\|emergency services\|detect\|dispatch\|monitoring` | zero hits outside one comment |
| Medical disclaimer | `SettingsView.swift:63`, `EmergencyCardView.swift:60` | both present |
| Account deletion (5.1.1(v)) | `AuthService.swift:221` → `delete_account` RPC, `0004:498`, tested `lifecycle_test.sql:268` | wired and tested |
| RevenueCat offerings | live probe of `/v1/subscribers/.../offerings` with the public key | `default` offering, all 3 products attached |
| RC simulator guard | `StoreService.swift:177` | `#if targetEnvironment(simulator) return`, prod customers protected |
| Feature reachability | grep for view construction | `VisitsView`, `ProvidersView`, `VitalsView`, `CareEventsView`, `TimelineView` all reachable from `PersonDetailView`; search on `PeopleView:61` |
| Encryption declaration | `Info.plist` | `ITSAppUsesNonExemptEncryption = false` |
| I3 (solo caregiver gets the whole app) | traced every `auth.isSignedIn` / `activeGroupID` / role check | every one gates sharing or sync only, never core tracking. A signed-out solo user gets the full med tracker. |
| D16/D17 offline session rules | `AuthService.swift:69, 78-87, 123-143, 214, 223` | `emitLocalSessionAsInitialSession: true` is set, first paint reads the synchronous Keychain-backed `currentSession`, and the only two session-clearing call sites are unreachable from a transport failure. Well covered by `AuthOfflineTests`. |
| Entitlement expression | `PeopleView.swift:30`, `SettingsView.swift:13` | `store.isPro \|\| groups.hasPlus` at both gates; `hasPlus` is a network-free computed property over cached fields (I1 holds) |
| Free-tier tombstone handling | `PeopleView.swift:7` | filters `deletedAt == nil` before counting, so delete-then-add does not wrongly trip the paywall |
| Paywall cannot be bypassed via invite | `0004:281-288`, `InviteSheet.swift:100-118` | a subject invite links an existing recipient and never creates one |
| Role gating vs the capability matrix | `FamilyView.swift:43-50, 126, 138, 178-181`, `RootView.swift:35`, `CheckInHomeView.swift:184-203` | no UI site is more permissive than the RPC layer |
| Mid-join network drop | `0004:251-265`, `JoinGroupView.swift:79-92` | `accept_invite` checks existing membership before used/expired, so a retry after a dropped connection succeeds |

One caveat on the first two rows: a green suite here means "the logic is right",
not "the app works". Read §3.4–3.4e before drawing comfort from the test count:
the most severe defect in the codebase sits under 112 passing tests.

---

## 1. P0: the app is silently broken in production right now

### 1.0 Sync is not degraded. It is dead, for every entity, on every cycle.

Two independent defects compound into total failure, and each was verified in the
source rather than inferred.

**The trigger:** `SyncEntity.pullOrder` (`Shared/Models/SyncModels.swift:232-235`)
is `[.person, .provider, .medication, …]`, `providers` is pulled **second**, and
that table does not exist in production (§1.1).

**The amplifier:** `pull(entity:)` has no catch, `pullAll` has no per-entity catch
(`SyncEngine.swift:53-62`), and `sync()` runs
`try await pullAll(...)` and `try await pushOutbox(...)` **inside the same `do`
block** (`SyncEngine.swift:36-39`). So the 404 on `providers` throws out of
`pullAll` and `pushOutbox` **is never called at all**.

The result is not "providers don't sync". The result is that **nothing syncs, in
either direction, ever**, no medication, no dose, no visit, no vital, no
emergency contact leaves the phone, and nothing arrives from family. The app is,
today, a single-device local tracker wearing a family-sync UI.

`SupabaseSyncRemote.classify()` (`SyncRemote.swift:295-306`) special-cases only
`42501` and `PGRST301`; every other PostgREST code including `PGRST205`
(no such table) and `PGRST204` (no such column) falls through to `.server`, which
is not `.offline`, which brings us to:

### 1.0b The "Last synced" timestamp actively lies

`SyncCoordinator.syncNow()` sets `lastSyncedAt = Date()` on every cycle where
`!outcome.wasOffline` (`SyncCoordinator.swift:49`), and `wasOffline` is set only
for the `.offline` case (`SyncEngine.swift:41`). A `.server` failure, which is
what total sync death looks like, leaves `wasOffline == false`.

So `SettingsView:93` cheerfully reports "Last synced: just now" on a cycle that
pulled one table and pushed nothing. **This is why §1.1 shipped.** There was no
signal anywhere that anything was wrong, on any device, at any time.

Fixing the schema (§1.1) makes sync work again. It does not fix either defect
here, and both will hide the next outage exactly as well as they hid this one:

- Catch per entity in `pullAll` so one bad entity cannot abort the cycle, and
  move `pushOutbox` out of the pull's `do` block so a pull failure can never
  prevent a push. A queued dose log must reach the server even if some unrelated
  table is having a bad day.
- Track a `lastError` on the coordinator, and only advance `lastSyncedAt` on a
  cycle that actually completed.

### 1.1 The production database is three migrations behind the client

**This is the single most serious finding.** `schema_migrations` on
`oygrxltpydcmmdtbreec` records `0001`–`0008`. Migrations `0009_refill_tracking`,
`0010_providers` and `0011_care_events` have **never been applied**, but the
client shipped in build 6/7 sends their columns.

Live `medications` columns, dumped from `information_schema`:

```
care_recipient_id, created_at, created_by, created_by_name, deleted_at, end_date,
form, group_id, id, instructions, is_active, is_as_needed, label_photo_path, name,
pharmacy, prescriber, purpose, schedule_minutes, start_date, strength, updated_at,
updated_by, updated_by_name, weekdays
```

`MedicationDTO` (`Shared/Services/SyncRemote.swift:55-85`) additionally sends
`provider_id`, `pharmacy_id`, `quantity_remaining`, `units_per_dose`,
`refill_threshold_days`, `last_filled_at`. PostgREST answers an upsert containing
an unknown column with `PGRST204`, so **every medication push would fail**,
and today it does not even get that far, because §1.0 means no push is attempted
at all. Medications are the entity the entire App Store listing is about.

Same failure on `visits`: `VisitDTO` sends `provider_id`, the live table has no
such column. And `providers` and `care_events` have no table at all, so those two
entities 404 outright.

Worse, the outbox treats this as a retryable error. `classify()` buckets
`PGRST204` as `.server`, so the entry retries with exponential backoff up to
`maxAttempts = 6` (`SyncEngine.swift:20-21, 513-521`) and then parks permanently
as `needsReview`, excluded from every future push by the outbox predicate
(`SyncEngine.swift:466`). A schema mismatch is not a conflict and no user action
can resolve it, so once §1.0 is fixed these entries will surface to the family as
"N changes need a look" that can never be cleared.

Consequence: a family installs the app, one sibling adds Mom's medications, and
they never appear on anyone else's phone. Locally everything looks fine, because
the app is offline-first and renders from SwiftData. This would have shipped.

**Fix:** `./scripts/db-apply.sh` (already verified `--dry-run`-safe; the ledger
makes it idempotent). All three migrations apply cleanly against a fresh cluster
in `test-db.sh`, so the risk is low. Do this before anything else on this list.

**Update 2026-08-04:** `0012_care_tasks` was added after this audit, so the gap
is now **four** migrations, not three, and `care_tasks` is a fourth table that
404s on every pull. It applies clean in `test-db.sh` with 13 RLS assertions, and
it changes nothing about the fix: run `db-apply.sh` once and all four land.

**Verify after:**
```
./scripts/db-apply.sh --sql "select filename from public.schema_migrations order by filename;"
./scripts/db-apply.sh --sql "select column_name from information_schema.columns
                             where table_name='medications' and column_name like '%refill%';"
```
then a real two-device round trip (§5.2).

**Root cause worth fixing too:** plan82's slice contract (`archive/plan82.md` §Contract)
required a migration file and `scripts/test-db.sh`, but never required applying
it to the live project. Three agents in a row satisfied the contract and left
production behind. Add "run `./scripts/db-apply.sh` and paste the ledger" to any
future slice contract.

### 1.2 No edge function has ever been deployed

`GET /v1/projects/oygrxltpydcmmdtbreec/functions` returns an empty list. Neither
`escalate-check-ins` nor `revenuecat-webhook` exists in production.

Consequences, both silent:

- **Escalation never fires.** The pg_cron job `aging-escalate-check-ins` is
  active and has been running every 15 minutes (last runs all `succeeded`), but
  it calls a URL read from Vault, and `vault.secrets` is **empty**. So the
  headline retention feature, "if Mom doesn't press the button the family gets
  told", has never told anyone anything.
- **Group billing never gets written.** `group_billing` is fed exclusively by the
  RevenueCat webhook. With no function deployed, `groups.hasPlus` is always
  false for everyone except the payer, whose own device resolves through the RC
  SDK. So a sibling on a paid family gets the free tier and there is no error
  anywhere. This is D30's whole mechanism, unbuilt in production.

Concretely, today: **the payer is fine and everyone else is locked out.**
`StoreService.apply(_:)` (`:169-173`) sets `isPro` straight from RevenueCat's
`customerInfo` with no dependency on the webhook, so the buyer's own device
unlocks. Every other member calls `GroupService.refreshBilling()` (`:172-206`),
finds no row, and takes the else branch that explicitly writes
`group.entitlement = "free"` (`:196-198`).

And the app says so out loud. `SettingsView.swift:32` shows the footer *"One
person in the family pays and everyone in the group is covered."* That sentence
is false in production right now. A sibling either pays a second time for
something the family already bought, or concludes the app is broken.

**Fix:** `./scripts/deploy-functions.sh`, then set the secrets and the two Vault
rows exactly as documented in that script's header. Blocked on §1.3.

The client side of this is correct and should not be touched: the webhook source
is a complete and correct writer of `group_billing`, and the resolution
expression `store.isPro || groups.hasPlus` is used identically at both gate sites
(`PeopleView.swift:30`, `SettingsView.swift:13`). `CareGroup.hasPlus`
(`SyncModels.swift:54-59`) is a plain computed property over locally persisted
fields, so reading it is synchronous and network-free and I1 holds. Only the
deployment is missing.

### 1.3 Push notifications were never enabled, at any layer

Four separate things are missing, and each one alone is fatal to the feature:

| Layer | State | Evidence |
|---|---|---|
| App ID capability | `IN_APP_PURCHASE`, `APPLE_ID_AUTH` only | `GET /bundleIds/55DU8LMCJB/bundleIdCapabilities` |
| Entitlements file | no `aps-environment` | `Aging/Aging.entitlements` |
| APNs auth key | none on disk (`~/.private_keys` holds ASC keys, not a push key) | `ls` |
| Supabase secrets | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_ENV`, `APNS_BUNDLE_ID` all unset | `GET /v1/projects/.../secrets` returns `[]` |

`NotificationService.registerIfAuthorized()` (`:58`) calls
`registerForRemoteNotifications()` unconditionally once authorized. Without
`aps-environment` that call fails 100% of the time on device, and
`AppDelegate.didFailToRegister` (`:102`) only writes an OSLog line. Nothing in
the UI ever says push is not working. The user who turns on check-in reminders is
told nothing and gets nothing.

**Fix, in order:**
1. Add Push Notifications to the App ID (Developer portal, or `POST
   /v1/bundleIdCapabilities` with `capabilityType: PUSH_NOTIFICATIONS`).
2. Add `aps-environment` = `development` to `Aging/Aging.entitlements`
   (Xcode rewrites to `production` on export).
3. Create an APNs auth key (`.p8`) in the Developer portal → Keys, note key id
   and team id `YXG4MP6W39`, store it beside the other keys but **never** in the
   repo.
4. `supabase secrets set` the five `APNS_*` values plus
   `REVENUECAT_WEBHOOK_SECRET`.
5. `./scripts/deploy-functions.sh`.
6. Create the two Vault secrets (`escalation_function_url`,
   `escalation_service_key`) with the SQL in `deploy-functions.sh`'s header.
7. Point the RevenueCat webhook at the deployed function URL with the matching
   secret header.

**Verify:** the real end-to-end test in §5.3. Nothing short of an actual push
landing on a real phone counts here.

### 1.4 Sync failures are invisible to the user

`SyncCoordinator` (`Shared/Services/SyncCoordinator.swift`) exposes `isSyncing`,
`lastSyncedAt` and `conflictCount`, and no error state at all. `SettingsView:93`
shows a "last synced" timestamp that simply stops advancing when sync breaks.

Combined with §1.1 this is how a total sync failure ships unnoticed: the app looks
completely healthy on the device that made the change. Add a `lastError` to the
coordinator and surface it in Settings ("Couldn't sync, tap for details") and
nothing more; do not put it in front of a read (I1).

### 1.5 Two documented conflict rules are not implemented as documented

These only become visible once §1.0 and §1.1 are fixed and sync actually runs,
which is precisely why they need fixing in the same pass.

**Dose-log dedupe does not dedupe.** D21 says dose logs are deduped rather than
conflict-resolved, and `SyncEngine.swift:239-242` states the unique index
collapses them. The server index is
`dose_logs_dedupe_idx on (medication_id, scheduled_at) where deleted_at is null`
(`0002_care_data.sql:230-232`), but `SupabaseSyncRemote.push` always upserts
`onConflict: T.idColumn` = `"id"` (`SyncRemote.swift:278-281`), and each device
generates its own random `DoseLog.id` (`CareModels.swift:367`). Two devices
logging the same dose therefore produce two different ids, the second one
violates the dedupe index, and Postgres raises `23505`, which `ON CONFLICT (id)`
does not absorb and `classify()` does not recognise.

Consequence: two family members both marking Mom's 8am pill as taken, the single
most likely concurrent action in the entire app, produces a stuck, unresolvable
"needs a look" item instead of the silent no-op the design promises. Fix by
upserting dose logs on the dedupe key, or by deriving the id deterministically
from `(medication_id, scheduled_at)`.

**Visits and vitals are not last-writer-wins; they are pull-clobbers-local.**
`applyVisit` (`SyncEngine.swift:273-300`) and `applyVital` (`:302-326`) never call
`isRealConflict`, only `applyPerson`, `applyMedication` and
`applyCheckInSettings` do (`:151-156`, `:192-197`, `:442-446`). Both unconditionally
overwrite every field and then set `isDirty = false` (`:299`, `:325`). Because
`pullAll` always runs before `pushOutbox` in the same cycle, a local edit that has
not yet been pushed is silently discarded the moment any newer-by-cursor row for
that id arrives, regardless of which edit was actually made later.

Consequence: a caregiver types up a visit note, sync runs, and the note vanishes
with no warning and no conflict prompt. D21 promises LWW, which requires comparing
timestamps; this compares nothing.

---

## 2. P0: App Store submission is blocked on eight things

Version `1.0` (`3cf8dc3f`) is `PREPARE_FOR_SUBMISSION` with build 6 attached
(build 7 is uploaded and valid but unattached). Text metadata is uploaded and
good. What is missing:

| # | Missing | Evidence | Fix |
|---|---|---|---|
| 2.1 | **Screenshots: zero.** `appScreenshotSets` is empty for en-US, and `fastlane/screenshots/en-US/` is an empty directory. | ASC API | Capture 6 on a leased sim, compose with `~/ios/app-previews/`, upload with `upload_preview.py`. Watch the 1290x2796 = `IPHONE_67` bucket. |
| 2.2 | **Primary/secondary category unset.** `MEDICAL` / `HEALTH_AND_FITNESS` sit in `fastlane/metadata/en-US/` but were never pushed. | `GET /appInfos/{id}/primaryCategory` → null | PATCH the `appInfos` category relationships. |
| 2.3 | **Age rating declaration entirely unanswered** (all 25 keys null). For a Medical app `medicalOrTreatmentInformation` and `healthOrWellnessTopics` are the ones that matter. | `GET /appInfos/{id}/ageRatingDeclaration` | PATCH `ageRatingDeclaration`. |
| 2.4 | **App Review detail missing**, `appStoreReviewDetail` is null. No contact name, phone, email, and no demo account. | ASC API | Create it. **A demo account is mandatory here**: family groups, roles and the subject's check-in screen are unreachable without Sign in with Apple, and a reviewer cannot create an Apple ID for a review. Provide a pre-seeded account already in a group with a care recipient, plus notes explaining the three onboarding paths. |
| 2.5 | **`copyright` is null** on the version. `fastlane/metadata/en-US/copyright.txt` has the string. | ASC API | PATCH the version. |
| 2.6 | **Regulated Medical Device declaration**, UI-only, not in the API, and submission is hard-blocked until it is set. | known fleet gotcha | Set in the ASC UI. |

### 2.7 The marketing site does not exist, and the URLs disagree with each other

Three separate problems stacked:

- `https://jackwallner.github.io/aging/privacy` → **404**. So does `/support`.
  There is no `jackwallner/aging` repo and no `jackwallner/medlist` repo on
  GitHub. `~/aging` is not even its own git repo, it lives inside the `~`
  repo, which has no remote.
- **The in-app links and the store metadata point at different sites.**
  `SettingsView.swift:133-139` links to
  `jackwallner.github.io/**medlist**/privacy-policy.html`; ASC and
  `fastlane/metadata/en-US/privacy_url.txt` say
  `jackwallner.github.io/**aging**/privacy`. `docs/site/index.html:10` declares
  its canonical as `/medlist/`. Pick one (`medlist`, per `architecture.md` §15)
  and make all three agree.
- **The ASC URLs are extensionless and the files are not.** `docs/site/` holds
  `privacy-policy.html`, `support.html`, `terms.html`. GitHub Pages will not
  serve those at `/privacy` or `/support`. Either rename to
  `privacy/index.html` style or use the real `.html` paths in ASC.

A dead privacy-policy URL is a guaranteed review rejection, and it is also the
link a Washington MHMDA consent claim would turn on.

**Fix:** create the public repo, push `docs/site/` as the Pages source, **enable
Pages explicitly via `gh api`** (pushing `docs/` does not publish a site), then
`curl` all three URLs for a 200 before touching ASC.

### 2.8 Territory restriction (D33) still cannot run

`GET /apps/6796916172/appAvailabilityV2` → 404. There is no availability record
until first-release availability is configured in the ASC UI, so
`scripts/asc-restrict-territories.py` has nothing to restrict.

This is not a nice-to-have. D33 is the reason the app is legally shippable at all
without a GDPR posture: it holds Article 9 data about third parties who never
consented. **Sequence matters:** configure availability in the UI, immediately run
`--backup` then `--apply`, and confirm EU/UK are gone *before* the app is
approved for sale, not after.

### 2.9 Compliance gaps App Store Connect will not catch for you

Not legal advice, and it does not discharge the lawyer's hour `architecture.md`
§10 already recommends. But two concrete things are missing against that
document's own stated plan:

- **No consumer-health-data privacy policy.** `docs/site/privacy-policy.html`
  is thorough (14 sections, including "Information About Other People", which is
  the hard one) but contains **zero** mentions of Washington, My Health My Data,
  or consumer health data. `architecture.md` §10 rates MHMDA as the single
  highest legal exposure, above HIPAA and GDPR, and MHMDA contemplates a
  separately linked consumer health data policy rather than a section buried in
  the general one.
- **Surrogate attestation is built; first-party consent is not.** D28's
  attestation for a no-account recipient exists and works
  (`PeopleView.swift:245`, stamped server-side, `CareModels.swift:28`). What
  `architecture.md` §10 also called for, a specific, opt-in, not-bundled-into-terms
  consent for collecting the user's own health data, has no corresponding UI.

Both are cheap to add and much more expensive to retrofit after launch, and both
are the kind of thing the lawyer hour should be spent confirming rather than
discovering.

---

## 3. P1: defects and test gaps that would let a real regression through

The suite is genuinely good on pure logic (`ScheduleEngine`, `CareSearch`,
`TimelineBuilder`, refills, reminders). The gaps are all at the seams.

| # | Gap | Why it matters |
|---|---|---|
| 3.1 | **No offline-launch UI test.** `architecture.md` §6 calls this "the one test that must never be allowed to go red" and §12 phase 2 lists it as outstanding. It was never written. | I1 is the app's entire reason to exist and nothing guards it. A future change that puts an `await` in front of first paint would go unnoticed. |
| 3.2 | **No schema-drift test.** Nothing anywhere compares the DTO coding keys to the live table columns. This is exactly what §1.1 was. | Cheap to fix: a script that reads `information_schema.columns` and asserts every DTO field exists. Run it in the ship script. |
| 3.3 | **No check-in UI test.** `CheckInHomeView` is the subject's entire app and has no UI coverage; I2 is currently enforced only by grep. | A paywall wrapper added upstream would silently violate I2. |
| 3.4 | **`FakeRemote.pull` can never throw** (`SyncEngineTests.swift:35-50`). The pull-abort bug in §1.0 is structurally invisible to the entire suite. | The most severe defect in the codebase had 112 passing tests over it. |
| 3.4b | **`SyncError.server` is never exercised.** Only `.offline` (`SyncEngineTests.swift:182`) and `.rejected` (`:206`) are injected, so `classify()`'s handling of `PGRST204`/`PGRST205`/`23505` and the `maxAttempts`→`needsReview` path are wholly untested. | Every failure mode in §1.0–§1.5 lives in the untested branch. |
| 3.4c | **`FakeRemote` validates no columns** (`SyncEngineTests.swift:12-74`) and dedupes purely by `id` (`:52-66`), mirroring the client's own incorrect assumption. | A schema mismatch (§1.1) and the dose-log collision (§1.5) both *cannot* fail in this suite by construction. |
| 3.4d | **`Visit` and `Vital` have zero conflict tests**, the only conflict test is `dosageConflictIsSurfaced` (`SyncEngineTests.swift:383-406`) on `Person`/allergies. Those are the two entities D21 explicitly names for LWW. | §1.5's silent data loss is untested. |
| 3.4e | **No `SyncCoordinatorTests.swift` exists at all**, so the lying `lastSyncedAt` (§1.0b) has no coverage. | The indicator that hid everything is itself unguarded. |
| 3.5 | **Three UI tests emit Swift 6 actor-isolation warnings** (`PaywallRenderUITests.swift:57-65` etc.). | Warnings today, errors in a future toolchain. Add `@MainActor` to the helpers. |
| 3.6 | **No screenshot-verified pass over the real UI.** The fleet standard is sim screenshots checked against a strict list (no em dashes, no truncation, no clipped prices, real seeded values), not "the test asserts the sheet presents". | This is also how §2.1's screenshots get produced, so it is one job not two. |

### 3.7 Onboarding has two dead ends with no way back

`OnboardingFlow.swift` has no `NavigationStack`, no `dismiss`, and no back
affordance anywhere in its `switch step`. Two steps are one-way doors:

- `.signIn` with `onSkip: path == .subject ? nil : …` (`:58`). On the subject
  path the skip button is deliberately absent, because there is nothing to join
  without an account. Reasonable, except there is also no way back to the path
  picker.
- `.joinCode` (`:66-69`), which only ever moves forward to `.transparency`.

Recovery exists but is not discoverable: because `hasCompletedOnboarding` is
still false and `people` is still empty, a cold relaunch lands back on the path
picker (`RootView.swift:69-71`). So the fix is small, but "force quit the app" is
not a recovery path you can expect from this app's demographic.

Consequence: someone who taps "Someone is looking after me" by mistake, or who
cannot get Apple sign-in to succeed, is stuck on that screen. Add a back button.

### 3.8 The free-tier person count is not scoped to a group

`PeopleView.swift:7-8` counts with `@Query(filter: #Predicate<Person> { $0.deletedAt == nil })`
and no `groupID` filter, then gates on `people.count < freePersonLimit`
(`:71`). Tombstone handling is correct, so deleting a person and adding a
replacement does **not** wrongly trip the paywall. The gap is cross-group: a
caregiver who tracks someone locally, then joins an existing family through
`JoinGroupView` (which never runs `adoptLocalData`), ends up counting their own
pre-existing local person **plus** the synced group recipient. Their free slot is
consumed without them having added a second person in any sense they would
recognise.

Narrow, but it lands on exactly the user who was doing the right thing.

### 3.9 A dead authorization check in `generate_invite_code`

`0004_invites_lifecycle.sql:125` and `:135` both call `is_group_staff(v_group_id)`.
The second is unreachable, since the first already raised for a non-staff caller,
and its comment promises something it does not do ("only an owner can create
another owner"). Not exploitable today, because `p_role` is constrained to
`caregiver`/`subject` at `:129` and the client never offers an owner invite
(`InviteSheet.swift:22-24`). So the documented "caregiver capped at
caregiver-or-below" rule holds by omission rather than by the check that claims
to enforce it. Fix the check before anyone adds an owner-invite path.

### 3.10 Further untested surfaces

Beyond the sync gaps above, nothing covers: the `isUnlocked` gate expression
itself at either site (only the underlying `CareGroup.hasPlus` model logic is
tested, in `CheckInTests.swift:155-169`); `PeopleView`'s free-tier counting,
including §3.8; `StoreService` at all (no unit test file references it, and
`PaywallRenderUITests` only exercises the trigger, never purchase, restore or
group propagation); the three onboarding forks as a state machine, including
§3.7; every `GroupService` invite/join RPC wrapper; `SignInView` and the Apple
sign-in completion path; and `FamilyView`'s owner-only controls and the
last-owner branching in `LeaveOrDeleteView`.

---

## 4. P2: known-deferred, decide explicitly rather than drift

- **Appendix B items 6 and 7 were never built.** Slices A–F covered items 1–5.
  Item 6 (paperwork photos on a `Visit`) and item 7 (weekly family digest) are
  still open. Neither is a 1.0 blocker; both should be written down as post-1.0
  rather than quietly forgotten.
- **Silent push (D22) is not implemented.** `Info.plist` has no
  `UIBackgroundModes: remote-notification`, and `escalate-check-ins` sends
  `apns-push-type: alert` only. Foreground sync plus scene-phase sync covers the
  common case; this is a deliberate gap, not a bug, but D22 currently overstates
  what ships.
- **The `Aging+` entitlement identifier is unverified.** The offerings probe
  confirms products but not entitlements. `StoreService.swift:31` hardcodes
  `Aging+` with `pro`/`AgingPro` fallbacks. Confirm on the RC dashboard that a
  purchase actually grants `Aging+`; the fallbacks make this survivable but not
  guaranteed.
- **Build 7 is uploaded but build 6 is attached** to the version. Attach the
  build that actually contains all the fixes from this document, and bump.

---

## 5. The verification plan: what "guaranteed working" has to mean

Everything above is a fix. This section is how each one gets *proved*. None of
these can be satisfied by a unit test.

### 5.1 Static gates (fast, run every time)
```
xcodegen generate
xcodebuild test -scheme Aging -destination "id=$(agent-sim checkout aging)"
./scripts/test-db.sh
```
Plus the new schema-drift check from §3.2.

### 5.2 Two-device sync round trip (proves §1.1)
Two leased simulators, two Apple IDs, one group. On A: add a care recipient, a
medication **with refill fields set**, a provider, a visit **with a provider
linked**, a care event, a vital, a dose log. Confirm every one appears on B.
Then edit on B and confirm it comes back to A. Then kill the network on A,
make three changes, restore, and confirm all three land. Screenshot each side.

This is the test that would have caught §1.1 on day one.

### 5.3 Escalation end to end (proves §1.3)
Real device, real APNs. Link a subject, set a check-in window that closes in
five minutes, do not press the button, and wait for the caregiver's phone to
buzz. Confirm the body is the exact string from migration 0007 and contains no
word from the I6 forbidden list. Nothing simulated counts.

### 5.4 Billing end to end (proves §1.2)
Sandbox purchase on device A (the owner). Confirm: RC shows the entitlement,
the webhook fires, one `group_billing` row appears with the right `expires_at`,
and **device B, a sibling who paid nothing, unlocks the second care
recipient**. Then put B in airplane mode and confirm it stays unlocked from the
local cache.

### 5.5 Offline cold launch (proves I1, and §3.1's missing test)
Airplane mode, force quit, cold launch. The emergency card must be on screen with
real data, no spinner, no login wall. Write this as the UI test §3.1 asks for, and
never let it go red.

### 5.6 Role enforcement against the live database (proves I4)
The UI mirrors the RLS policies; it is not the enforcement. With a real subject
token, hit PostgREST directly and confirm a subject cannot read another
recipient's medications, cannot write meds, and cannot enumerate members' APNs
tokens. The local `rls_test.sql` asserts this against a local cluster; do it once
against production too, because production is where the policies actually run.

### 5.7 Screenshot pass (proves §3.6, produces §2.1)
Drive a seeded sim through every screen, Today, People, person detail, each of
the six sub-sections, emergency card, timeline, search, family, invite,
transparency, check-in home, check-in settings, paywall, settings, and read every
screenshot against the checklist. Clipped price, truncated label, doubled badge,
em dash in copy: each is a fail.

---

## 6. Recommended order

1. `./scripts/db-apply.sh` (§1.1). Fifteen seconds, and it is the difference
   between a working app and a broken one.
2. Fix the two sync-structure defects (§1.0). Per-entity catch in `pullAll`, and
   `pushOutbox` moved out of the pull's `do` block. Without this, the next missing
   table kills the whole app again just as silently.
3. Fix `lastSyncedAt` and add `lastError` (§1.0b, §1.4). Small, and it is the
   entire reason nobody noticed §1.1 for two builds.
4. Fix dose-log dedupe and visit/vital LWW (§1.5). Do this before real data
   exists, because the visit bug destroys user input.
5. Give `FakeRemote` the ability to throw on pull and to reject unknown columns,
   then write tests for §1.0, §1.0b and §1.5 (§3.4–3.4e). These tests are what
   make the fixes above stick.
6. Run §5.2, the two-device round trip. Do not proceed until it is clean.
7. Push notifications, all four layers (§1.3).
8. Deploy the functions and set every secret (§1.2).
9. Run §5.3 and §5.4.
10. Write the offline-launch UI test and the schema-drift check (§3.1, §3.2).
10b. Add a back button to the two onboarding dead ends (§3.7), scope the
    free-tier count to the active group (§3.8), and fix the dead invite check
    (§3.9). Small, independent, and none of them blocks anything else.
11. Create the site repo, enable Pages, reconcile the three URL conventions,
    `curl` for 200 (§2.7).
12. Screenshot pass, which produces the store screenshots (§5.7, §2.1).
13. Category, age rating, copyright, review detail with a demo account (§2.2–2.5).
14. Regulated Medical Device declaration and first-release availability in the
    ASC UI (§2.6, §2.8).
15. Immediately run `asc-restrict-territories.py --backup` then `--apply`, and
    confirm EU/UK are gone (§2.8).
16. `./scripts/testflight.sh`, attach the new build, submit.

Steps 1–10 are code and infrastructure and are the real work. Steps 11–16 are the
store checklist and are mostly clerical, but 11 and 15 both have a trap in them.

---

## 7. What this document deliberately does not claim

- It does not say the sync engine's conflict rules are correct. Two of them are
  provably not (§1.5), and the rest have only ever run against a fake remote that
  cannot reject a write. §5.2 is what turns the remainder from an assumption into
  a fact.
- It does not say the app is legally clear. `architecture.md` §10 flags
  Washington's MHMDA as the top exposure and recommends a lawyer's hour before
  launch. That recommendation still stands and nothing here discharges it.
- It does not re-price any feature. `aso-plan.md` Appendix B's refusals hold.
- It does not audit the check-in and reminder scheduling logic beyond confirming
  I2 holds and the tests pass. `DoseReminderScheduler` and `CheckInService` were
  read, not stress-tested against timezone changes or the 64-notification limit.

---

## Appendix: the commands that produced these findings

Reproducible, so the next person does not have to take any of this on trust.
`asc_lib` needs a newer interpreter than the system 3.9; use
`/opt/homebrew/bin/python3.14`.

```bash
# Which migrations production actually has
./scripts/db-apply.sh --sql "select filename from public.schema_migrations order by filename;"

# Which columns production actually has (compare against the DTOs in SyncRemote.swift)
./scripts/db-apply.sh --sql "select column_name from information_schema.columns
                             where table_name='medications' order by column_name;"
./scripts/db-apply.sh --sql "select table_name from information_schema.tables
                             where table_schema='public' order by table_name;"

# The escalation cron is alive but has nothing to call
./scripts/db-apply.sh --sql "select jobid, schedule, jobname, active from cron.job;"
./scripts/db-apply.sh --sql "select name from vault.secrets;"          # empty

# No function deployed, no secret set
source ~/.aging_credentials
curl -sS "https://api.supabase.com/v1/projects/$AGING_SUPABASE_PROJECT_REF/functions" \
     -H "Authorization: Bearer $AGING_SUPABASE_ACCESS_TOKEN"           # []
curl -sS "https://api.supabase.com/v1/projects/$AGING_SUPABASE_PROJECT_REF/secrets" \
     -H "Authorization: Bearer $AGING_SUPABASE_ACCESS_TOKEN"           # []

# RevenueCat offerings are correctly configured (this one is good news)
curl -s -H "Authorization: Bearer $REVENUECAT_PUBLIC_APP_KEY" -H "X-Platform: iOS" \
     "https://api.revenuecat.com/v1/subscribers/probe/offerings"

# The site the App Store points at
curl -s -o /dev/null -w "%{http_code}\n" https://jackwallner.github.io/aging/privacy   # 404
```

App Store Connect (app `6796916172`, version `3cf8dc3f-d10f-42ec-a70e-b633dee7b692`,
app info `3c26663e-f658-43b6-918e-08a1220f9f17`, bundle id resource `55DU8LMCJB`):

```
GET /appStoreVersionLocalizations/{id}/appScreenshotSets   -> []      (§2.1)
GET /appInfos/{id}/primaryCategory                         -> null    (§2.2)
GET /appInfos/{id}/ageRatingDeclaration                    -> 25 nulls (§2.3)
GET /appStoreVersions/{id}/appStoreReviewDetail            -> null    (§2.4)
GET /appStoreVersions/{id}                                 -> copyright null (§2.5)
GET /apps/{id}/appAvailabilityV2                           -> 404     (§2.8)
GET /bundleIds/55DU8LMCJB/bundleIdCapabilities             -> IAP + Apple ID auth only (§1.3)
```
