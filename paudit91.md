# Elderhub persona audit 91

Audit date: 2026-09-03

Scope: Sarah, Chris, Eleanor, and the ER clinician. This is a read-only source
and existing-test audit of the onboarding, sharing, Today, task, recipient,
emergency-card, and export paths. No app code or project settings were changed.

## Executive verdict

The normal solo-caregiver path is coherent: the app has a discoverable person
hub, an Everyone Today mode, an intentionally large recipient check-in path,
and an emergency card with a primary contact. The most serious risks are at
state boundaries rather than in the happy path:

1. Explicit sign-out does not remove the prior account's local records or
   cached group from the visible app.
2. Access revocation is not applied to the local mirror on the ordinary launch
   path, so previously downloaded records can remain readable offline.
3. Chris's default Everyone view does not include check-in status, so it cannot
   answer "is Mom OK?" and can place a person with no check-in under "Nothing
   due today."
4. The ER handoff changes depending on whether the clinician sees the live card
   or the exported one-pager. A completely blank card is also ambiguous, and
   the collected date of birth is absent from both handoffs.

Release posture: PA-01 through PA-11 should be treated as release-blocking
findings until each is reproduced and dispositioned. PA-12 through PA-18 are
important usability, trust, and safety follow-ups.

## Priority matrix

| ID | Priority | Persona | Finding | Confidence |
| --- | --- | --- | --- | --- |
| PA-01 | P0 | Sarah, Chris | Sign-out leaves prior records, group state, reminders, and possibly store entitlement state active. | High, source confirmed |
| PA-02 | P1 | Sarah, Chris, Eleanor | Per-recipient access changes do not reliably purge the local mirror on launch. | High, source confirmed |
| PA-03 | P1 | Chris | Everyone Today omits check-in state and can label a person with no check-in as clear. | High, source confirmed |
| PA-04 | P1 | Sarah, Chris | Editing an assignee name can leave a stale assignee ID, breaking Mine and ownership trust. | High, source confirmed |
| PA-05 | P1 | ER clinician, Sarah | A completely empty emergency card shows a generic setup prompt instead of explicit unknown sections. | High, source confirmed |
| PA-06 | P1 | ER clinician, Sarah | The live emergency card and exported one-pager contain different medication detail. | High, source confirmed |
| PA-07 | P1 | ER clinician, Sarah, Chris | Finding the card takes selection and scrolling, especially in the multi-person default. | High for placement, medium for timing |
| PA-08 | P1 | ER clinician | Onboarding promises date of birth on the card, but neither handoff prints it. | High, source confirmed |
| PA-09 | P1 | Eleanor | Recipient mode does not show the recipient name and silently falls back when its stored person ID is stale. | High, source confirmed |
| PA-10 | P1 | Eleanor | A cold-start sync gap produces a blank recipient screen with no visible retry action. | High for flow, runtime timing untested |
| PA-11 | P1 | Sarah | Refill tracking accepts zero units per dose, silently disabling low-stock math. | High, source confirmed |
| PA-12 | P2 | Chris | There is no "since last visit" or unread change summary for a weekly sibling. | High, product gap confirmed |
| PA-13 | P2 | Sarah, Chris | Search mixes private and shared people without a scope label. | High, source confirmed |
| PA-14 | P2 | Sarah | A group-create failure can advance onboarding as though sharing setup succeeded. | High, source confirmed |
| PA-15 | P1 | Eleanor, Sarah | Transparency acknowledgement remains available when the member list is unavailable. | High, source confirmed |
| PA-16 | P2 | Sarah, ER clinician | Generic person details notes are excluded from the handoff without telling the person entering them. | High, source confirmed |
| PA-17 | P2 | Sarah, Chris | Task and bill completion controls do not receive the explicit minimum hit area used by dose controls. | Medium, source risk |
| PA-18 | P2 | ER clinician | The live card has no visible freshness timestamp, while the export does. | High, source confirmed |

## Detailed findings

### PA-01, P0: sign-out does not close the account boundary

Personas: Sarah, Chris. This also affects any family sharing a handset.

Observed behavior in source:

- `AuthService.signOut()` calls the auth SDK and then `forgetSession()`.
- `forgetSession()` only sets the auth state to signed out and clears the
  display name. It does not clear the SwiftData mirror, cached group, member
  cache, notification preferences, or pending local notifications.
- `RootView` does not gate the caregiver tabs on `auth.isSignedIn`. Its
  onboarding predicate can be false while the old people remain in the store,
  so the signed-out user can remain on the old Today, Care, Sharing, and
  Settings surfaces.
- `GroupService.refresh()` returns without clearing the cached group when the
  refreshed membership query has no row. A later account flow can therefore
  inherit stale group identity, and the onboarding adoption path can see that
  stale group.
- The dose reminder scheduler only removes or rewrites requests when its
  refresh path runs. Sign-out itself does not run a clear operation.
- RevenueCat identification is performed by `StoreService.start()` and sign-in
  handlers. Sign-out does not log out the RevenueCat customer or reset the
  observable entitlement state.

Evidence: `Shared/Services/AuthService.swift:245-266`,
`Aging/RootView.swift:34-87`, `Shared/Services/GroupService.swift:283-308`,
`Aging/Views/Onboarding/OnboardingFlow.swift:298-325`,
`Shared/Services/DoseReminderScheduler.swift:350-481`, and
`Shared/Services/StoreService.swift:211-230`.

Impact: A person who deliberately signs out can still see the previous
family's medical records on that handset. Old reminders can continue naming
the previous person. If another account subsequently uses the handset, the
identity and sharing boundary are difficult to reason about. This is a privacy
failure, not merely stale UI.

Suggested reproduction: create two local records, sign in as account A, sign
out from Settings, and verify whether the old tabs, records, routed reminders,
and Plus state remain. Then sign in as account B and inspect the group and local
record state before making any sharing choice.

### PA-02, P1: access revocation is not applied on the normal launch path

Personas: Sarah, Chris, Eleanor.

Observed behavior in source:

- The server's per-recipient RLS policy is scoped by `access_scope` and
  `recipient_access`.
- `GroupService.loadMembers()` fetches those values and calls `applySelfAccess()`.
  That method correctly hard-deletes inaccessible grouped `Person` rows from
  the local mirror and resets the pull cursors.
- The cached member representation does not retain access scope or listed
  recipient IDs.
- `RootView` calls `groups.refresh()` and `sync.syncNow()` on startup and
  foreground. It does not call `groups.loadMembers()` there.
- The member reload is reached from Sharing or Transparency surfaces, which
  requires the user to navigate to those surfaces first.
- Incremental sync has no way to infer that a row disappeared from a scoped
  server result and does not perform the access purge itself.

Evidence: `Shared/Models/SyncModels.swift:70-111`,
`Shared/Services/GroupService.swift:221-258,365-447,719-764`,
`Aging/RootView.swift:60-87`, `Aging/Views/Groups/FamilyView.swift:65-76`,
`Aging/Views/Groups/TransparencyView.swift:78-132`,
`Shared/Services/SyncCoordinator.swift:47-77`, and
`supabase/migrations/0018_per_recipient_access.sql:93-139`.

Impact: After Sarah narrows Chris's access, Chris's phone can retain and show
Dad's previously downloaded record while offline, until a path that reloads
members is reached. The server may correctly deny new reads while the local
mirror still answers the UI. Eleanor also cannot reliably know that the
records on her handed-over phone reflect the current access decision.

Validation gap: The source path is clear, but a two-device revocation test was
not completed in this audit.

### PA-03, P1: Everyone Today cannot answer the weekly sibling's check-in question

Persona: Chris.

Observed behavior in source:

- With two or more people, Today defaults to `.everyone`.
- The Everyone content renders doses, tasks, appointments, running-low counts,
  and bill counts. It has no check-in section or check-in field in its digest.
- `TodayDigest.PersonDigest.isClear` checks those same medication, task,
  appointment, refill, and bill collections. It does not include check-in.
- The per-person view alone renders "Checked in today" or "No check-in yet today."
- An otherwise empty person is therefore listed under "Nothing due today" in
  Everyone mode, even when check-in is enabled and no check-in has happened.

Evidence: `Aging/Views/TodayView.swift:78-92,289-381,478-510`,
`Shared/Services/TodayDigest.swift:15-46,74-105`.

Impact: Chris's primary weekly question, "is Mom OK?", is not answered by the
default landing state. The wording "Nothing due today" can be interpreted as
reassurance when the relevant fact is that no check-in was recorded. This does
not mean the app should infer an emergency. It means the recorded check-in
state is missing from the summary.

### PA-04, P1: assignee display name and identity can diverge

Personas: Sarah, Chris.

Observed behavior in source:

- The task editor allows a person to be selected from the family member menu or
  typed into the assignee name field.
- Saving writes the trimmed name, but preserves `assigneeUserID` whenever the
  name is nonempty. The comment describes dropping the ID after retyping, but
  the save condition only clears it when the name is empty.
- `TaskPlanner.isAssigned` gives the ID precedence whenever both sides have an
  ID, and only falls back to the name when IDs are absent.

Evidence: `Aging/Views/CareTasksView.swift:393-409,437-472`,
`Shared/Services/TaskPlanner.swift:75-93`.

Reproduction: choose Chris from the member picker, edit the displayed assignee
name to Sarah manually, and save. The row says Sarah but remains assigned by
ID to Chris. Sarah's Mine view can hide it, while Chris's Mine view can show it
under Sarah's name.

Impact: The exact feature Chris uses to answer "what's mine" becomes a source
of false ownership. A sibling can believe an errand is covered by somebody
else, or miss an errand assigned to them.

Coverage gap: `AgingUITests/CareTaskAssigneeFilterUITests.swift:89-111` covers
the picker path, not the picker-then-retype path.

### PA-05, P1: an empty emergency card is ambiguous

Persona: ER clinician, with Sarah as the person preparing the card.

Observed behavior in source:

- The live card switches to a single `emptyPrompt` when allergies, conditions,
  contacts, blood type, active medications, and providers with a phone are all
  empty.
- That prompt says the card has nothing on it yet and asks the user to add key
  information.
- When any content exists, the card instead renders named sections and uses
  "Not recorded" for empty sections.
- The exporter always prints critical headings, including `ALLERGIES` and
  `CONDITIONS`, even when they are empty.

Evidence: `Aging/Views/EmergencyCardView.swift:16-64,217-236`,
`Shared/Services/MedListExporter.swift:23-65`.

Impact: A clinician handed a completely blank live card cannot distinguish
"not recorded" from "not applicable" or from an omitted section. The generic
setup prompt is useful to Sarah during setup but is not a safe 30-second ER
handoff representation. The live and exported empty states also disagree.

### PA-06, P1: live card and export are not the same handoff

Personas: ER clinician, Sarah.

Observed behavior in source:

- The live medication block shows medication name, schedule or as-needed
  status, and purpose.
- The exported one-pager additionally includes form, instructions, prescriber
  and phone, and pharmacy and phone.
- Both are presented as the emergency information a clinician can use, but the
  source does not identify the live card as a summary with omitted fields.

Evidence: `Aging/Views/EmergencyCardView.swift:261-300`,
`Shared/Services/MedListExporter.swift:101-135`,
`Aging/Views/Components/HubComponents.swift:348-380`.

Impact: Sarah can show the live card and believe she has handed over the same
record as the exported page. The clinician may receive instructions,
prescriber context, or pharmacy contact information in one route but not the
other. In an ER, this creates route-dependent completeness.

### PA-07, P1: emergency retrieval is too deep for a 30-second handoff

Personas: ER clinician, Sarah, Chris.

Observed behavior in source:

- In a single-person Today, the emergency card link is after setup, tasks,
  appointments, refills, doses, and bills.
- In Everyone mode, which is the default for two or more people, there is no
  emergency-card link in the aggregate content. The user must first select the
  person.
- The person hub places the emergency card after setup, medication sections,
  reminder sections, and feature tiles.
- The card itself is a long scroll view. Existing UI tests scroll to reach the
  primary contact section.

Evidence: `Aging/Views/TodayView.swift:289-381,525-635`,
`Aging/Views/PersonDetailView.swift:150-179,204-321`,
`Aging/Views/EmergencyCardView.swift:31-66`,
`AgingUITests/RecordCorrectionUITests.swift:119-137`,
`AgingUITests/CareExperienceUITests.swift:33-50`.

Impact: The ER clinician is not the app's regular user and has no time to
learn its navigation. A populated record requires multiple visual decisions
before the relevant card opens, and the multi-person default adds person
selection first. Exact time was not measured on device, so the priority is
based on layout and interaction depth rather than a timed failure.

### PA-08, P1: date of birth is promised, then omitted from the handoff

Persona: ER clinician.

Observed behavior in source:

- Onboarding describes date of birth as information a hospital asks for and
  explicitly says it prints on the emergency card.
- The live emergency-card header shows the person's name, age, and blood type,
  but not date of birth.
- The exporter shows name, age, blood type, and generated time, but not date of
  birth.

Evidence: `Aging/Views/Onboarding/OnboardingDetailsFlow.swift:189-207`,
`Aging/Views/EmergencyCardView.swift:238-258`,
`Shared/Services/MedListExporter.swift:12-20`.

Impact: The user is given a false expectation about a high-value identity field.
Age is not an equivalent verification value in an emergency, especially when
the clinician is trying to match the page to a patient.

### PA-09, P1: recipient mode does not prove whose screen it is

Persona: Eleanor.

Observed behavior in source:

- Recipient mode resolves the displayed person by stored handover ID first,
  then an auth-linked row, then `isSelf`, then the first person in the local
  list.
- If the stored handover ID no longer resolves, the code silently uses the
  fallback chain.
- The recipient screen title is "Today" and does not visibly show the person's
  entered name. The check-in button, medication list, and emergency card do
  not provide a persistent identity confirmation.
- The handover selection itself is explicit and names the candidate, but that
  confirmation does not protect later launches from stale local state.

Evidence: `Aging/Views/CheckIn/CheckInHomeView.swift:41-99`,
`Shared/Services/DeviceModeService.swift:82-95,113-158`,
`Aging/Views/SettingsView.swift:145-169,197-249`.

Impact: Eleanor may press check-in or read medication information for the wrong
person without a clear way to detect the mismatch. Presbyopia, tremor, and low
confidence make silent fallback more dangerous than an explicit unavailable
state.

### PA-10, P1: recipient cold start can look broken and offer no visible recovery

Persona: Eleanor.

Observed behavior in source:

- If recipient mode cannot resolve a person, the screen shows "Nothing here
  yet" and says the family's list has not reached the phone.
- There is no visible retry button in that state. Recovery is the outer
  scroll view's pull-to-refresh gesture.
- Root sync runs asynchronously after the initial view is rendered, so this
  state is possible during a first launch or a slow connection.

Evidence: `Aging/Views/CheckIn/CheckInHomeView.swift:88-94,126`,
`Aging/RootView.swift:60-72`.

Impact: Eleanor can reach a blank screen without a check-in control, medication
context, or emergency card and conclude that she did something wrong. A hidden
gesture is a poor recovery path for a person with low confidence or tremor.

Validation gap: The source establishes the state and recovery path. The exact
window during a real cold start was not measured because the simulator test
worker did not complete.

### PA-11, P1: invalid refill units silently disable inventory warnings

Persona: Sarah.

Observed behavior in source:

- The medication editor offers refill tracking and an editable numeric units-per-
  dose value.
- Save writes the value without rejecting zero or another nonpositive value.
- `Medication.daysRemaining` returns nil when units per dose is nonpositive, so
  the medication stops participating in the running-low calculation even when
  tracking is enabled.
- The model's decrement arithmetic has no corresponding validation guard.

Evidence: `Aging/Views/MedicationEditorSheet.swift:118-140,281-290`,
`Shared/Models/CareModels.swift:382-402`,
`Shared/Services/TodayDigest.swift:175-181`.

Impact: A setup error at 6am can make a tracked medication disappear from
Sarah's refill work. The UI gives no indication that tracking has become
mathematically invalid. Existing refill tests cover positive values but do not
cover zero or nonpositive input.

### PA-12, P2: Chris has no catch-up model

Persona: Chris.

Observed behavior in source:

- Sync exposes last sync time, offline state, and last error, but no last-viewed
  marker, unread state, or change summary.
- Today answers what is currently outstanding, not what changed since Chris's
  previous visit.
- Timeline defaults to a three-month window and intentionally suppresses taken
  doses, so it is not a complete medication activity log.
- The task Done view is limited to the last 30 days.

Evidence: `Shared/Services/SyncCoordinator.swift:18-77`,
`Aging/Views/SettingsView.swift:294-327`,
`Aging/Views/TodayView.swift:289-381`,
`Aging/Views/TimelineView.swift:16-95`,
`Aging/Views/CareTasksView.swift:119-141`,
`Shared/Services/TimelineBuilder.swift:180-184`.

Impact: Chris must reconstruct "what did I miss" from current outstanding
items, a recent completed-task list, and per-person history. A clean Today
screen does not mean nothing changed since the last visit.

### PA-13, P2: search erases the shared versus private distinction

Personas: Sarah, Chris.

Observed behavior in source:

- The normal Care screen separates circle people, local-only people, stranded
  people, and private people into named sections.
- Search instead passes every local `Person` to `CareSearch.search()` and
  replaces those named sections with a flat result list.
- Search result rows show the person and matching text, but not whether the
  record is shared, local-only, stranded, or private.

Evidence: `Aging/Views/PeopleView.swift:45-107,356-409`,
`Shared/Services/CareSearch.swift:91-113`.

Impact: A private record can look like a shared family record after a search.
For Sarah this is a discoverability problem; for Chris it can create a false
expectation that a result is available to the circle or visible to siblings.

### PA-14, P2: group setup failure advances the flow without a durable recovery state

Persona: Sarah.

Observed behavior in source:

- After sign-in, onboarding refreshes or creates the group and may adopt local
  data.
- Errors are placed in an alert message, but the code advances to the details
  step unconditionally after the `do`/`catch` block.
- There is no persistent "sharing setup pending" state or required retry before
  the user reaches the care features.

Evidence: `Aging/Views/Onboarding/OnboardingFlow.swift:298-325`.

Impact: A transient network or RPC error can make Sarah believe account and
circle setup completed. She can continue entering records locally while the
family sharing state is incomplete, discovering the problem only when she
tries to invite somebody.

### PA-15, P1: transparency can be acknowledged without showing the member list

Personas: Eleanor, Sarah.

Observed behavior in source:

- Transparency shows a loading/error state when the member list cannot be
  loaded and says the user should try again once there is a signal.
- The `I understand` acknowledgement remains enabled in that state.
- The user's consent can therefore complete without showing who currently has
  access to the record.

Evidence: `Aging/Views/Groups/TransparencyView.swift:78-132`,
`Shared/Services/GroupService.swift:365-447`.

Impact: Eleanor can accept a sharing disclosure without seeing the people it is
supposed to disclose. Sarah can also pass onboarding while the access picture
is unknown, weakening trust in the sharing model.

### PA-16, P2: generic person notes can disappear from the emergency handoff

Personas: Sarah, ER clinician.

Observed behavior in source:

- The Details editor has a generic `Notes` field with the placeholder
  "Anything else worth knowing."
- That editor is reachable from the emergency-card flow.
- `Person.notes` is not included in either the live emergency card or the text
  export.
- The warning that notes are plaintext and not a password vault belongs to
  `CareNote`, a different model. The generic Details notes field has no copy at
  entry explaining that it is excluded from the ER handoff.

Evidence: `Aging/Views/PersonDetailsEditorSheet.swift:118-121,188-196`,
`Aging/Views/EmergencyCardView.swift:79-87`,
`Shared/Services/MedListExporter.swift:1-136`,
`Aging/Views/CareNotesView.swift:175-195`,
`Shared/Models/CareModels.swift:1230-1260`.

Impact: Sarah may put clinically useful context in a field presented near the
card and assume the clinician will see it. The issue is not that all free text
belongs on an ER card. The issue is that the exclusion is silent at the point
where the expectation is formed.

### PA-17, P2: task and bill completion controls have a weaker touch-target contract

Personas: Sarah, Chris.

Observed behavior in source:

- Today's dose completion control has an explicit minimum height of 44 points.
- The task and bill completion controls are image-only buttons without the same
  explicit minimum frame.
- The task and bill rows are likely to be used one-handed while moving through
  a morning routine.

Evidence: `Aging/Views/TodayView.swift:1084-1090,1131-1139,1261-1267`.

Impact: The source does not guarantee comparable hit areas across the three
completion actions. This is a static interaction risk, not a confirmed device
miss-tap measurement. It is more consequential for Sarah's one-handed use and
for Eleanor if a task is exposed to recipient mode in a future path.

### PA-18, P2: live card freshness is not visible

Persona: ER clinician.

Observed behavior in source:

- The exported one-pager prints a generated timestamp.
- The live emergency card shows the disclaimer at the bottom but no visible
  generated or last-updated timestamp in its header or summary.

Evidence: `Aging/Views/EmergencyCardView.swift:60-63,238-258`,
`Shared/Services/MedListExporter.swift:12-20`.

Impact: A clinician viewing the live card cannot quickly assess how current the
information is. The two handoff routes again communicate different trust
signals.

## Persona walkthrough notes

### Sarah, primary caregiver

The setup model is well aimed at Sarah: the care-recipient identity is
collected before Sign in with Apple, the person hub exposes the feature catalog,
and Today brings the daily actions forward. The main Sarah risks are account
boundary failure after sign-out (PA-01), refill math accepting invalid input
(PA-11), group setup that can appear complete after failure (PA-14), and
completion controls without the same explicit hit-area contract (PA-17).

### Chris, sibling

The invitation and shared-circle model, Everyone default, and in-place dose and
task actions fit a weekly sibling. The product does not yet give Chris a
reliable weekly readout: check-in state is absent from Everyone Today (PA-03),
there is no catch-up summary (PA-12), and an assignee name can disagree with
the ID behind Mine (PA-04). Access revocation and search scope also affect
whether Chris can trust what he sees (PA-02, PA-13).

### Eleanor, care recipient

The dedicated recipient branch has a large check-in action, undo, and direct
access to medications and the card. It avoids the billing path, which is the
right trust boundary. The highest risks are identity ambiguity after a stale
handover (PA-09), a blank first-launch state with hidden recovery (PA-10), and
consent without a visible access list (PA-15).

### ER clinician

The emergency card marks the primary contact, and the export names critical
empty sections when the record is partially populated. The clinician path still
has four trust and speed problems: card retrieval depth (PA-07), blank-card
ambiguity (PA-05), inconsistent live versus exported detail (PA-06), missing
date of birth (PA-08), and no live-card freshness signal (PA-18).

## Evidence and test status

The audit reviewed current Swift, SwiftData model, sync, and Supabase migration
source, then compared the relevant existing unit and UI tests. Historical audit
documents were used as context only; a historical finding was included here
only when current source still supported it.

The following headless simulator command was attempted on a leased
`agent-sim` device:

```text
xcodebuild -project Aging.xcodeproj -scheme Aging -destination "id=83A6AF7B-C144-4DDB-9929-74FCF25DCDC8" test -only-testing:AgingTests
```

The app and test targets compiled and testing started, but the Xcode test
worker did not materialize. The run was stopped after waiting and exited 75.
No test was counted as passing from that run. The findings above therefore
distinguish source-confirmed behavior from runtime validation gaps.

---

## Dispositions, 2026-09-03

Implemented in this pass. Every entry names the file the fix lives in; the
reasoning is in the source comment beside it, not here.

| ID | Disposition |
| --- | --- |
| PA-01 | Fixed. `SettingsView.signOutAndForget()` runs the same `forgetGroupLocally` the delete-account path already ran, logs the RevenueCat customer out (`StoreService.forgetCustomer()`), drops every pending notification and reschedules from what is left. Delete-account gained the RevenueCat and notification halves too. Local-only records are deliberately untouched: they were never the account's. |
| PA-02 | Fixed. `RootView` calls `groups.loadMembers()` on launch and on foreground, which is what applies a narrowed access scope to the local mirror. It was reachable only from Sharing and Transparency. |
| PA-03 | Fixed. `PersonDigest` carries `hasCheckIn` / `checkedInToday`, handed in by `TodayView` so `TodayDigest` stays pure functions over the models. An unpressed check-in makes a person outstanding rather than clear, prints "no check-in yet" in `statusLine`, counts in the Everyone headline, and renders as the first row of that person's section. |
| PA-04 | Fixed. The task editor remembers the name that was on screen when the id was picked (`assigneeNameForID`) and drops the id on save unless the field still says it. The comment claiming this already happened is now true. |
| PA-05 | Fixed. `EmergencyCardView` draws every critical section always. The setup prompt is additional, not a replacement, and only when the card is editable. |
| PA-06 | Fixed. The card's `detail(for:)` prints the same fields in the same order as `MedListExporter.line(for:)`: form, instructions, prescriber and pharmacy with their phone numbers. |
| PA-07 | Partly fixed. Everyone mode now carries an "Emergency cards" section directly under the headline, one row per person, pushing straight to the card with no person selection. Depth on the single-person screen and inside the card itself is unchanged. |
| PA-08 | Fixed. Date of birth prints in the card header and in the export, and both name it when it is missing. |
| PA-09 | Fixed. The recipient screen prints the person's name above the button, and a handover naming a person this phone does not hold no longer falls through to a guess: it says so and offers a retry. The caregiver unlock stays in the toolbar, so that state is never a dead end. |
| PA-10 | Fixed. A real "Try again" button, replacing pull-to-refresh as the only recovery. |
| PA-11 | Fixed. The editor warns before the tap and saves a nonpositive units-per-dose as 1, so refill tracking cannot be switched on and silently do nothing. |
| PA-12 | Not implemented. A catch-up model ("what changed since Chris last looked") needs a last-viewed marker synced per member and a change feed to read it against, which is a feature, not a fix. |
| PA-13 | Fixed. Search results carry "Only on this phone" for a private or stranded record, so the boundary the sectioned list is careful about is not erased by typing. |
| PA-14 | Fixed as copy. The onboarding alert now says the record is saved, that nothing is shared, and names Sharing → "Start a care circle" as the retry. The flow still advances: trapping someone on an onboarding screen with their data entered is worse. |
| PA-15 | Fixed. With no member list, "I understand" is replaced by a prominent "Try again" and a secondary "Continue without the list", so consent is not offered as though the disclosure had been shown. Not blocked: a recipient with no signal must never be stuck. |
| PA-16 | Fixed. The Details notes field has a footer saying it does not print on the card or the one-pager, and where clinical detail belongs instead. |
| PA-17 | Fixed. The task and bill completion controls take the same 44-point minimum and explicit hit shape as the dose control. |
| PA-18 | Fixed. The card header prints "Last updated", taken from the newest edit across the person, their active medications, contacts and printed providers. Deliberately not the time the screen was opened. |

Tests: `AgingTests` 316 tests green on a leased headless simulator, including four
new `TodayDigestTests` for the check-in rule and one `MedListExporterTests` for
the date of birth.
