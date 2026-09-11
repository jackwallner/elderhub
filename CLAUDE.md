# Aging (Elderhub) — Project Guide

Multi-person medication and medical-record tracker for people looking after a parent
or spouse. XcodeGen project/scheme: `Aging`, sim lease owner `elderhub`.

App Store title is **Elderhub: Family Care Log**, home-screen name **Elderhub**; the
Xcode scheme and bundle id stay `Aging` / `com.jackwallner.aging`; the source
repository is `elderhub`.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency)
- SwiftData as the local mirror, plus Supabase (project `oygrxltpydcmmdtbreec`) for
  family groups. No CloudKit.
- XcodeGen (`project.yml`). Targets: iOS 17+
- RevenueCat, entitlement `Aging+`, resolved as `store.isPro || groups.hasPlus`

## Targets / bundle IDs
- `Aging` — `com.jackwallner.aging`
- `AgingTests` — `com.jackwallner.aging.tests`
- RevenueCat app: `appl_dvyPWLaZxKyjLUrFVzDynNGjVGb`
- No App Group (no widget or watch target in v1)

## Architecture
`Shared/` holds everything not view-layer:
- `Models/CareModels.swift` — `Person`, `Medication`, `DoseLog`, `Visit`,
  `VitalReading`, `EmergencyContact`, `Provider`, `CareEvent`, `CareTask`,
  `Bill`. Enums are stored as `*Raw` strings with a computed accessor, so
  SwiftData migrations stay cheap.
- `Services/CareModelStore.swift` — the container. Falls back to a wiped store, then
  to memory, rather than crashing on a schema change.
- `Services/ScheduleEngine.swift` — pure functions turning a `Medication` schedule
  into `DoseSlot`s for a day, matched against logged doses. All the testable logic
  lives here, not in views.
- `Services/AuthService.swift` — Sign in with Apple, and the offline-session rules
  that keep a transport failure from being read as a sign-out.
- `Services/GroupService.swift` — membership, roles, invites. Every mutation is a
  security-definer RPC; `group_members` has no client write policy at all.
- `Services/SyncEngine.swift` / `SyncRemote.swift` / `SyncCoordinator.swift` —
  offline-first two-way sync: outbox, compound server-time cursor, per-entity
  conflict rules.
- `Services/CheckInService.swift` — the proof-of-life button and the one local
  notification that has to be reliable.

`Aging/Views/` is the UI. `Aging/Support/SampleData.swift` seeds previews and sim runs.
`Aging/Views/Components/HubComponents.swift` holds the shared visual vocabulary
(`FeatureTile`, `StatTile`, `QuickActionChip`, `SetupProgressCard`,
`EmergencyCardBanner`, `PersonHeaderCard`).

**Discoverability is a product requirement here, not polish.** The app shipped with
every capability behind an identically-styled grey list row and the first user
reaction was that it was not clear what the app did. `PersonDetailView` is now a hub
(header stats, setup checklist, tiles that say what each feature is *for*), and the
Today tab carries a quick-action row. A new feature is not done until it has a
`CareFeature` case with a blurb and appears on that hub. Feature tiles are `Button`s
driving one `navigationDestination`: nested `NavigationLink`s inside a `LazyVGrid`
inside a `List` row do not push.

Schedules are stored as **minutes from midnight** (`scheduleMinutes`), not `Date`s, so
a dose time survives time-zone changes. `weekdays` uses `Calendar`'s 1-indexed,
Sunday-first numbering; empty means every day.

## Rules that hold everywhere
Condensed from the deep notes below; the reasoning and the bugs behind each one live there.
- Never add a `date` column. Day-valued columns are `timestamptz`, converted at noon UTC (migration 0021); `check_in_settings.last_escalated_on` stays a `date` as the one deliberate exception, because `CheckInSettingsDTO` does not declare it.
- A pulled child row is bound to its parent on every apply, not only on insert.
- `DoseLog.id` is derived from (medication, scheduled time), so re-recording a slot reuses its row: search `medication.doses`, not `liveDoses`, and clear `deletedAt`.
- Every authored row resolves its name through `CareTaskAuthor.name(from:)`. `recorded_by_name` is a synced column, so a literal "You" written locally shows up on everyone else's phone.
- Restricting someone's access purges what their phone downloaded with `context.delete`, **never** `tombstone()` (`GroupService.applySelfAccess`): losing access to Dad's record must not delete Dad's record (I5). This is the second deliberate hard delete beside `GroupService.forgetGroupLocally`; every other local delete goes through `tombstone()` (see "Every local write goes through `SyncableRecord`" below).
- `CareNote` and `Bill` never get a credential, account-number, reference, card or login field, and no copy invites one.
- `MedListExporter` and `EmergencyCardView` print every critical section even when empty and must stay in step on what they include.
- Dose reminders are one request per person per dose time and share the device's 64 pending requests with refills and appointments.
- `docs/join.html` must stay published at that exact path: every invitation links to it (`InviteLink.webBase`). Never rename the `elderhub` repo.
- Never put `caregiver`, `senior care` or `home care` in any ASC field. A same-category app is named **Elder Hub**, so watch for a name-confusion rejection.

## Deep notes (load on demand)
These files load automatically when you read a file matching their `paths:`. Agents that do not auto-load rules (AGENTS.md readers) should open the file for the area they are touching. Record new area-specific learnings in the matching file, not here. The full design record stays `docs/architecture.md`.

| File | Covers | Read when |
|---|---|---|
| `.claude/rules/today-tasks-and-schedules.md` | `TaskPlanner`, the assignee filter, appointments, stopped medications, weekdays, `TodayDigest`, Everyone mode, `CareOverview`, the setup checklist, card insets, undo | Today, Care, tasks, visits, medications, the person hub |
| `.claude/rules/reminders.md` | Grouped dose reminders, reminder routing, `NotificationPermission` | Notifications and reminder toggles |
| `.claude/rules/records-emergency-and-bills.md` | Person labels, `BillPlanner`, `DeviceModeService`, `CareNote` and `Bill` boundaries, `MedListExporter`, CALL FIRST, `telURL` | The emergency card, export, notes, bills, handover mode |
| `.claude/rules/sync-circles-and-database.md` | One account one circle, per-recipient access, conflicts, author names, no `date` columns, parent binding, `DoseLog` ids, `tracksRefills`, adopting records | Sync, groups, invitations, migrations, RLS, edge functions |
| `.claude/rules/paywall-and-review.md` | The three paywall states, the review prompt gate | `StoreService`, the paywall, the rating funnel |
| `.claude/rules/listing-site-and-screenshots.md` | The Elderhub rename, acquisition and keywords, the marketing site, `join.html`, the old medlist URLs, App Store screenshots | Metadata, `docs/`, screenshots, ASO |

## App-specific notes
- **Nothing may be asked for on a screen that follows Sign in with Apple.** 1.0.1 was
  rejected under Guideline 4.0 for signing in and then showing a required name field on
  the next screen. Onboarding now names the care recipient *before* the account
  (`OnboardingFlow.firstStep(for:)`), the circle is created once sign-in completes
  (`attachGroupAndContinue`, still named after the person), and `SignInOrderUITests`
  asserts the sign-in step carries no text field at all. `prepareAppleRequest` asks for
  `[.fullName, .email]`: whatever the framework gives us, the app must not ask for
  again. `docs/architecture.md` §22.
- **Compliance**: Medical category. Never claim to treat, cure or diagnose (App Review
  1.4.1). The disclaimer lives in `SettingsView` and on the emergency card, and both
  must stay. Submission is blocked until the Regulated Medical Device declaration is
  set in the ASC UI (not exposed in the API).
- Free tier is one *care recipient*, not one member. Siblings joining are never
  charged for; the second parent is the paywall trigger (`PeopleView`).
- **Offline-first is the product, not an optimisation.** Every screen renders from
  SwiftData; sync writes into that store and never sits in front of it. The scenario
  the app exists for is an ER with no bars.
- **Two invariants that are structural, not stylistic.** The check-in path contains
  no billing check at any depth (`CheckInService` does not import `StoreService`),
  and nothing anywhere may claim to detect an emergency or summon help. Push copy is
  written in SQL (migration 0007) so it cannot drift per app version.
- **Every local write goes through `SyncableRecord`.** After a create or an edit,
  call `recordLocalChange()`; to delete, call `tombstone()`. Never `context.delete`
  a synced row: the push reads the row to build its DTO, so a row removed outright
  can never be sent and the delete dies on that one phone. Tombstones live in the
  store until `markSynced` purges them, which is why reads go through
  `person.liveMedications` and friends rather than the raw relationship. (The one
  legitimate hard delete is `GroupService.forgetGroupLocally`, which is a wipe, not
  a delete.)
- Roles are cached in `CareGroup` so gating works offline. The UI mirrors the RLS
  policies; it never is the enforcement.
- Not sold in the EU or UK (`scripts/asc-restrict-territories.py`).
- Migrations are append-only once applied. Fix forward, never edit a shipped file.
  Apply them with `./scripts/db-apply.sh` **before** shipping the client that
  sends the new column, or every push 400s on an unknown field.
- Full design record, including the open environment setup, is `docs/architecture.md`.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, review
funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
