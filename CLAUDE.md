# Aging (Elderhub) — Project Guide

Multi-person medication and medical-record tracker for people looking after a parent
or spouse. XcodeGen project/scheme: `Aging`, sim lease owner `elderhub`.

App Store title is **Elderhub: Family Care Log**, home-screen name **Elderhub**; the
Xcode scheme and bundle id stay `Aging` / `com.jackwallner.aging`; the source
repository is `elderhub`.

Renamed from "Med List: Family Meds" on 2026-08-05. The medication-list title was an
ASO bet on `medication list` (pop 23 / diff 23), the one soft keyword in the category.
That bet is off: the product pivoted past meds-only, and acquisition is planned outside
App Store search. Everything in `aso-plan.md` about *what not to claim* still stands
(see below); only the title strategy changed. Note that **Elder Hub** (App Store id
1589043147, Elder Technologies, Medical) is a live same-category app with a near
-identical name, so watch for a name-confusion rejection at review.

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
  `Person.displayLabel` is the **entered name**, never the relationship: two
  labels for one row (Today saying "Mom" while the emergency card says
  "Eleanor") is unreadable in an ER, and the relationship-first version also
  produced "Me's care record". Relationship is the subtitle.
- `Services/CareModelStore.swift` — the container. Falls back to a wiped store, then
  to memory, rather than crashing on a schema change.
- `Services/ScheduleEngine.swift` — pure functions turning a `Medication` schedule
  into `DoseSlot`s for a day, matched against logged doses. All the testable logic
  lives here, not in views.
- `Services/BillPlanner.swift` — the same shape as `TaskPlanner`, for `Bill`:
  bucketing (overdue / due soon / later / no date / autopay), recurrence
  arithmetic and the outstanding total. Autopay is checked *before* the date, so
  a direct debit is never called overdue; without that the overdue section stops
  meaning anything. Marking a recurring bill paid creates a **new row** for the
  next period rather than moving this one's date, exactly as `CareTask` does,
  because "did anyone pay the March invoice" is what the history is for.
- `Services/TaskPlanner.swift` — pure bucketing (overdue / today / …), recurrence
  arithmetic and `CareTaskMerge`, the task-specific sync rule. Two siblings
  ticking off the same errand is agreement, not a conflict; two people editing
  the same task's text is a conflict. Genuine LWW, unlike `applyVisit`.
  `isAssigned` is the one matching rule for "whose errand is this": the id wins
  whenever both sides have one (two siblings called Chris), and the name is the
  fallback, because `assigneeUserID` is only set when the assignee was picked
  from a loaded member list and typing a name offline has to keep working. A
  task that has an id, read on a device whose member list has not loaded yet,
  falls back too, so **Mine** is never silently empty on launch.
  `CareTaskRecurrence` carries quarterly and half-yearly for the same reason
  `BillRecurrence` always did: most of what a family repeats (reorder hearing
  aids, book the audiologist, review the repeat prescription) sits between a
  month and a year, and offering only those two means dismissing a reminder five
  times or missing it once. Cases are free to add: `recurrenceRaw` is a string
  in a column that already exists, and an unknown value falls back to `never`.
- **The tasks screen filters by assignee, and only in a shared circle.** Alone,
  the device has neither a user id nor a name to match on, so the Everyone/Mine
  control would only ever be empty and is not shown. The filter is not
  persisted: one that survives relaunch is one people forget is on, and what it
  produces here is a sibling concluding the family has nothing left to do.
  Today is deliberately *not* filtered (it answers "what is left for her", not
  "what is left for me"); it marks the reader's own rows with "You" instead.
  Assignment still notifies nobody, and the editor footer still says so.
- `Services/CareOverview.swift` — the feature catalog (`CareFeature`: title, blurb,
  symbol, colour), the per-tile count lines, and `SetupChecklist`. One list, read by
  the person hub, the Today quick actions and the People rows, so a feature cannot
  be added in one place and go missing in the other two. Copy here is always a
  statement of what is recorded, never an assessment (I6). `QuickAction.todayRow`
  is the Today tab's six chips: meds, tasks, bills, Medical, notes, contacts. Six,
  not seven, because the seven-chip row ran off the right edge, so its last entries
  were effectively not in the app. Anything new goes behind Medical, not into the
  open row; a unit test asserts the row plus `QuickAction.medical.members` still
  reaches every feature except check-in. **Medical pushes `MedicalRecordView`, it
  does not drop a menu**: every other chip pushes, and one tap gesture producing
  two kinds of thing reads as a mis-tap. That screen renders `.medical.members` as
  tiles, so the chip and the screen cannot drift. Check-in stays out of the row,
  but Today does carry a check-in *status* section once one is enabled for the
  person: setting it up is a hub job, "has she pressed it today" is a daily one,
  and it was two taps away on another tab.
- **The setup checklist leads the Today tab, and dismisses per row.**
  `SetupStepPreferences` (per person, per `SetupStep.Kind`) is the row-level
  dismissal; `SetupCardPreferences` is the whole-card Hide. Putting it first is
  only fair because both exist, so anything that makes it harder to dismiss has to
  move it back down. `PersonDetailView` and Settings → "Set up … again" restore
  every dismissal; `PeopleView`'s "3 of 6" line counts the *visible* steps so the
  two screens agree.
- **Card rows use `listRowInsets(leading: 0, trailing: 0)`.** The section is
  already inset by the inset-grouped list; a further 16 made every card in the app
  visibly narrower than the plain list sections beside it.
- `Services/DeviceModeService.swift` — who is holding *this handset*
  (`.caregiver` / `.recipient`) and the four-digit caregiver code that swaps back.
  A different axis from `GroupRole`, which is what an *account* may do in the
  circle and is enforced by RLS; keep the two named apart in code and in copy. The
  emergency card is never behind the code, the service never imports
  `StoreService` (I2), and clearing the code returns to the caregiver's app so a
  handed-over phone is never a door with no handle. See `docs/architecture.md` §19.
- `Models/CareModels.swift` also holds `CareNote`, the deliberately unstructured
  per-person note. It is **not** a password vault and must never become one by
  drift: no field is typed as a credential, no copy invites one, and the body is
  plaintext under the same RLS as everything else. The editor footer says so at
  the point of entry, which is the only place the boundary is any use. See
  `docs/architecture.md` §14 for what a real vault would require.
- **`Bill` is on that same line and is the likeliest place to cross it.** A
  screen headed "Bills" is where a family will put the online banking login if
  a box is left open for it, so there is no account-number, reference, card or
  login field, the editor footer says so at the point of entry, and `notes` is
  plaintext under the same RLS as everything else. The other half: nothing here
  pays anything. `paidAt` records that a human says they paid it, the way a
  `DoseLog` records that a human says a tablet was swallowed.
- `Services/MedListExporter.swift` — the plain-text one-pager. It prints every
  critical section even when empty ("ALLERGIES: not recorded"), because a
  section that simply vanishes reads as a negative answer to whoever is holding
  the page. `EmergencyCardView` follows the same rule, and the two must stay in
  step on what they include: the export used to omit the provider block the card
  showed.
- `Services/StoreService.swift` — RevenueCat. `identify()` ties the RC customer to
  the Supabase user id; without it the billing webhook has no group to credit.
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

## App-specific notes
- **Acquisition is not App Store search.** The eldercare/caregiving vocabulary has no
  search demand (every term at Astro's popularity floor; ~30 competing apps, category
  ceiling 35 ratings since 2016), and as of the Elderhub rename the title no longer
  chases the one soft term. Plan the channel outside search. `aso-plan.md` is still the
  reference for what the category is; read it before touching metadata.
- Still true regardless of channel: do not put `caregiver`, `senior care` or `home care`
  in any ASC field. They are the only high-volume terms nearby and they resolve to job
  seekers and B2B agency software, so they buy wrong-intent installs and bad reviews.
- Free keyword-field trophies, since the field costs nothing: the `dementia` cluster
  (diff 5-13, unowned) and `medical id`.
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
- **`DoseLog.id` is derived from (medication, scheduled time), so re-recording a
  slot must reuse its row.** Undoing a dose tombstones the log, and the tombstone
  keeps the id any replacement would be given. Anything that logs a dose therefore
  searches `medication.doses`, not `liveDoses`, and clears `deletedAt` on the row
  it finds. Two rows with one server key is the failure this avoids.
- Roles are cached in `CareGroup` so gating works offline. The UI mirrors the RLS
  policies; it never is the enforcement.
- **The marketing site lives in this repo's `docs/` directory.** GitHub Pages
  serves the current pages from `jackwallner.github.io/elderhub/`, and the
  `sync-landing-page.yml` workflow mirrors them to
  `jackwallner.com/ios/elderhub/`. The privacy, terms, and support URLs are
  compiled into shipped builds (`SettingsView`, `PaywallView`) and the ASC
  listing. Format and checklist: `~/ios/landing-pages/README.md`.
- **`docs/join.html` is part of the app, not a separate site.** Every
  invitation message points at it (`InviteLink.webBase`), and those messages sit
  in inboxes longer than the build that wrote them, so the page has to stay
  published at that exact path and the app must ship no build whose invite link
  is live before the page is. It is what makes an invitation openable from a
  desktop client or a phone with no app; `elderhub://` alone never was. §17 of
  `docs/architecture.md` has the rest.
- Not sold in the EU or UK (`scripts/asc-restrict-territories.py`).
- Migrations are append-only once applied. Fix forward, never edit a shipped file.
  Apply them with `./scripts/db-apply.sh` **before** shipping the client that
  sends the new column, or every push 400s on an unknown field.
- **`Medication.tracksRefills` is a real column, not a sentinel.**
  `quantityRemaining == 0` used to mean both "not tracked" and "empty", so the
  moment a bottle ran out the medication dropped off Running low, loaded with
  the toggle off, and could not have its last dose undone. Migration 0016 splits
  them; zero while tracking now means out of stock, and `daysRemaining` returns
  0 rather than nil.
- **The Care tab shows group records and local-only records in separate named
  sections, and joining a circle adopts nothing.** Every people query used to
  return every `Person`, so a private record sat in the family list looking
  shared. `SyncEngine.adoptPerson` moves one across, only from an explicit tap:
  uploading the rest of someone's phone because they accepted an invitation is a
  disclosure, not a migration.
- Full design record, including the open environment setup, is `docs/architecture.md`.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, review
funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.

After any app-code push, run `./scripts/testflight.sh`.
