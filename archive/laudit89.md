# Elderhub end-to-end user audit

Audit date: 2026-08-09

Scope: first launch, local-only use, solo use, family sharing, invited caregiver, invited subject, medication logging, setup, emergency use, offline behavior, account state, privacy, accessibility, and purchase paths.

Evidence used:

- Manual run on iOS 26.3, iPhone 17 Pro simulator, with a fresh local store and the seeded demo store.
- Source review of the SwiftUI views, SwiftData models, sync services, invite flow, and local web invitation page.
- Successful Debug build and app launch.
- The full UI test target was also started, but did not return within five minutes because the test runner stalled. It was stopped, so no UI test pass result is claimed.
- Supabase invite acceptance, push delivery, real Apple sign-in, and production purchase were not completed end to end. Those findings are identified as static or unverified.

Severity:

- P1: high risk for health-record accuracy, privacy, consent, or a core workflow.
- P2: material confusion or degraded workflow, but a workaround exists.
- P3: lower-risk inconsistency or polish issue.

## Findings requiring priority

1. P1, the app uses a relationship label as the primary identity in several screens, so a record entered as Eleanor becomes “Mom” or “Me”.
2. P1, signing out leaves the cached group and role active, which creates an unsafe account-switching and local-privacy state.
3. P1, joining a group can leave an unrelated local-only person in the same Care and Today lists.
4. P1, refill tracking stops working when the supply reaches zero, exactly when a refill warning is most needed.
5. P1, medication and other health rows can be deleted with a swipe and no confirmation or undo.
6. P1, the subject transparency screen has no cached member list and can be blank after an offline relaunch.
7. P2, the six-step setup card only displays three unfinished steps, hiding family invitations and check-in setup.
8. P2, the emergency card explicitly shows an unknown blood type, but the shared text export omits that field.

## Detailed findings

### AUD-01, P1: record identity changes from the entered name to the relationship

Personas: first-time supporter, solo user, caregiver managing multiple people, ER user.

Status: reproduced manually and confirmed in source.

Reproduction:

1. Start from a fresh store.
2. Choose `Start a care record`.
3. Skip sign-in with `Not now`.
4. Enter `Eleanor`, leaving the default relationship as `Mom`.
5. Open the record.

Observed:

- The onboarding completion screen says `Mom's care record is ready` and `Open Mom's record`.
- Today labels the selected person `Mom`.
- The person detail navigation title is `Mom`.
- The Care tab row and the emergency card use `Eleanor`.
- The detail header shows `Eleanor` with `Mom` underneath.
- In the solo path, entering a real name with the relationship `Me` produces copy such as `Me's care record`.

The root cause is `Person.displayLabel`, which returns the relationship whenever it is nonempty, at `Shared/Models/CareModels.swift:133-135`. Onboarding stores that value as the created person's display name at `Aging/Views/Onboarding/OnboardingFlow.swift:219`, while Today and person detail use it at `Aging/Views/TodayView.swift:75-85,217-221` and `Aging/Views/PersonDetailView.swift:141-148`. The emergency card correctly uses `person.name` at `Aging/Views/EmergencyCardView.swift:187-203`, which makes the mismatch visible across adjacent screens.

Impact: a caregiver can be looking at the correct underlying row but not trust that fact. In a medication or ER context, seeing “Mom” on one screen and “Eleanor” on the card can cause the wrong record to be selected or shared. With two parents, relationship-only labels also make the person menu ambiguous.

Expected: the entered name should remain the primary identity everywhere. Relationship should be supporting context.

### AUD-02, P2: persona and onboarding copy do not match the people using the app

Personas: subject, partner caregiver, non-family helper, solo user.

Status: source review, with the first-launch path manually reviewed.

Issues:

- The subject path is named `I have an invitation`. A parent who was told “your family set this up for you” may not think of that as an invitation, especially if the code was read over the phone.
- The supporter sign-in copy says an account lets “your brothers and sisters” see the same list, although the preceding path promises support for a partner or anyone else being helped. See `Aging/Views/Onboarding/SignInView.swift:19-26`.
- The solo screen asks `What should we call you?` but the field placeholder remains `Their name`, at `Aging/Views/OnboardingView.swift:27-43`.
- The path picker says `You can change this later`, at `Aging/Views/Onboarding/OnboardingFlow.swift:279-282`, but there is no visible way to change the selected persona later. Sharing, adding a person, and joining a group are different actions from changing the original path.

Impact: a user can choose the wrong branch, assume a non-existent persona switch exists, or interpret the app as intended only for siblings. The wrong branch is recoverable with the visible back control, but the copy still creates hesitation at the most important decision point.

### AUD-03, P1: failed group creation still presents a ready care circle

Persona: signed-in supporter who begins sharing during onboarding.

Status: static finding, not completed against a live server failure.

`createFirstPerson` inserts and saves the person locally, attempts group creation, catches any error into `errorMessage`, then unconditionally assigns `createdPersonName` and advances to the feature overview at `Aging/Views/Onboarding/OnboardingFlow.swift:188-220`.

If group creation fails, the user can see an error alert and then see `care record is ready` and `Open ... record`. The local record is usable, but the shared care circle was not created. The user is not told in the feature overview that the record is local-only or that family sharing still needs to be completed. The next visit to Sharing will show no group, which looks like data loss or a failed signup.

Expected: distinguish “local record ready” from “care circle ready”, and make the sharing failure state explicit.

### AUD-04, P1: joining a group can mix unrelated local data into the family record UI

Personas: local-only caregiver who later accepts a family invitation, and the other family members whose health data is displayed on that phone.

Status: static finding, strongly supported by the current query and join paths.

Scenario:

1. A caregiver creates a local-only record for a parent.
2. The caregiver later signs in and accepts a sibling's invitation.
3. The old local row remains ungrouped because `JoinGroupView` calls `acceptInvite` and refreshes membership, but does not adopt local data. See `Aging/Views/Groups/JoinGroupView.swift:104-111` and `Shared/Services/GroupService.swift:418-447`.
4. `PeopleView` and `TodayView` query every non-tombstoned `Person`, without a group filter, at `Aging/Views/PeopleView.swift:4-8` and `Aging/Views/TodayView.swift:4-8`.

The code comments in `PeopleView.swift:30-41` explicitly recognize that two worlds can coexist, but only the billing count is group-scoped. The visible list, search, Today selection, invite picker, and person menu still use all rows.

Impact:

- A private local record can appear beside the family record and look shared.
- The first person shown by Today can be the wrong person.
- A caregiver can edit or invite against a row that is not in the active family group.
- The caregiver can treat the local row as shared, invite against it, or make edits while believing they will reach the family.

This is a data-boundary problem, not just a list-label issue.

### AUD-05, P1: signing out leaves the previous group identity active

Persona: anyone sharing a phone, especially a caregiver who signs out before handing it to another person.

Status: static finding. The full account-switch scenario was not run because it requires real authentication.

`AuthService.signOut()` clears only the auth session at `Shared/Services/AuthService.swift:233-240`. It does not call `GroupService.forgetGroupLocally()`. That cleanup is used for leaving or deleting a group at `Shared/Services/GroupService.swift:495-527`. `GroupService.refresh()` also returns without clearing the cached group if a signed-in account has no membership, at `Shared/Services/GroupService.swift:182-185`.

RootView chooses caregiver tabs from the cached group role, not from the auth state, at `Aging/RootView.swift:39-49`. The signed-out Settings account section only says `You are not signed in`, with no sign-in action, at `Aging/Views/SettingsView.swift:142-158`.

Likely result:

- After sign-out, the old shared people and Sharing membership can remain visible locally.
- A different account signing in on the same phone can inherit the old cached group context until another state transition changes it.
- Local edits carry the old group ID but cannot sync while signed out.

Keeping an offline copy after sign-out may be an intentional product choice, but the active group, role, sync identity, and account-switch behavior are not separated or explained. As implemented, `Sign out` does not behave like a reliable privacy or account-switch boundary.

### AUD-06, P2: the setup card reports six steps but shows only three

Personas: first-time supporter and any caregiver setting up a new person.

Status: reproduced manually on Today and the person hub.

On a fresh record, the card says `0 of 6 set up` but displays only:

- Add a medication
- Turn on dose reminders
- Add allergies and conditions

Emergency contact, invite family, and daily check-in are omitted. The implementation deliberately caps the visible list at three with `prefix(3)`, at `Aging/Views/Components/HubComponents.swift:169-173`.

Impact: the count tells the user there are unfinished jobs, but there is no indication that more rows exist. The two features most tied to family collaboration and proof-of-life are therefore easy to miss. `Hide` also removes the card from Today without a same-screen way to restore it. The person hub has a restore path, but it requires the user to find the full record first.

### AUD-07, P2: “Invite the family” becomes complete when no family was invited

Persona: signed-in owner who creates a circle but has not yet sent an invitation.

Status: static finding.

The six-step checklist defines `Invite the family` as complete whenever `isInGroup` is true, at `Shared/Services/CareOverview.swift:370-375`. Creating a group during onboarding makes this true immediately, even when the owner has zero pending or accepted invites.

Impact: a setup progress count can imply that family sharing is done when the owner is still the only member. This is especially misleading when the user sees `5 of 6 set up` and assumes siblings already have access.

### AUD-08, P1: refill tracking stops warning when the supply reaches zero

Persona: caregiver relying on the app to notice a medication is out.

Status: static logic finding. The relevant behavior is deterministic.

The model uses `quantityRemaining == 0` as the sentinel for “refills are not tracked”, at `Shared/Models/CareModels.swift:179-182`. `daysRemaining` returns `nil` whenever quantity is not greater than zero, at lines 280-288. Taking the final dose clamps the quantity to zero at lines 291-299. Today filters the Running low section to medications whose `daysRemaining` is non-nil, at `Aging/Views/TodayView.swift:513-537` and the `runningLowMedications` helper.

Reproduction:

1. Turn on Track refills.
2. Enter one unit on hand and one unit per dose.
3. Record the dose.
4. The quantity reaches zero.

The medication no longer has a numeric `daysRemaining`, and the editor will load Track refills as off because it derives the toggle from `quantityRemaining > 0`, at `Aging/Views/MedicationEditorSheet.swift:181-186`. Undoing the final dose also cannot restore stock because `restoreForDoseUntaken` refuses to operate at zero, at `Shared/Models/CareModels.swift:301-309`.

Impact: the app loses the exact state where “empty” should be most visible. A user can believe refill tracking is enabled while Today stops displaying the medication in Running low.

### AUD-09, P1: medication and health records can be deleted with no confirmation or undo

Personas: caregiver correcting a list, family member using swipe gestures, shared-record collaborators.

Status: static finding. The action code is direct and has no confirmation state.

Medication rows use `.onDelete` and immediately tombstone each row at `Aging/Views/PersonDetailView.swift:185-201,385-392`. The same pattern is used for visits, vitals, providers, notes, and tasks. There is no confirmation, undo action, or recovery affordance for these health records. In a shared group, the tombstone is designed to propagate to other family members.

Person deletion and emergency-contact deletion do ask for confirmation, which makes the absence of protection on medications and other medical rows more surprising. A horizontal swipe can therefore remove the medication history attached to a row that the user may have intended to edit.

### AUD-10, P2: emergency card and shared plain-text export disagree about missing blood type

Personas: ER user sharing the card instead of showing the live screen.

Status: static finding.

The live emergency card always renders `Blood type not recorded` when the field is empty, at `Aging/Views/EmergencyCardView.swift:195-206`. The plain-text exporter only emits a blood-type line when a value exists, at `Shared/Services/MedListExporter.swift:12-19`.

The recipient of the shared text therefore sees no blood-type field at all, while someone looking at the card sees an explicit unknown field. The project design correctly treats missing allergies and conditions as important, so this is an inconsistency in the high-stakes export path.

### AUD-11, P1: subject transparency can show no people after an offline relaunch

Persona: invited subject who has accepted a family invitation but reopens the app without a network connection before accepting, or while viewing, transparency.

Status: static finding, not completed against a live invite.

`GroupMember` is held in memory by `GroupService`, not in the SwiftData cache, at `Shared/Services/GroupService.swift:10-18,88-90`. `TransparencyView` loads members through a network task at `Aging/Views/Groups/TransparencyView.swift:101-104`, then simply loops over `groups.members` with no loading, stale-cache, or unavailable state at lines 109-130.

On a cold offline launch, the cached group role can still require transparency, but the member list can be empty. The subject is then asked to understand who can see them without being shown who that is. The exhaustive “what they can see” copy is good, but it does not replace the missing identities.

### AUD-12, P2: the iOS 26 floating tab bar collides with bottom content

Personas: every caregiver, especially a user scanning Today quickly or using a smaller phone.

Status: reproduced manually on iOS 26.3 with seeded data.

The floating tab bar visually sits over the lower part of the Today list. In the seeded run, the first view of the Doses section had lower dose rows partly obscured. On the fresh record it also overlapped the lower setup and medication content. Settings showed Support and the disclaimer only after scrolling past the overlay.

The content remains scrollable, so this is not data loss. It does make the primary medication checklist look clipped and makes lower-priority privacy/support content appear missing. The app uses a `List` inside the root `TabView`, at `Aging/RootView.swift:125-133`, without an app-level visual treatment that accounts for the floating tab bar.

### AUD-13, P2: Today hides the due date for tasks due today

Persona: caregiver using Today as a work queue.

Status: reproduced manually with seeded data.

The overdue task showed `Was due Aug 6, 2026 · Jack`. The task due today showed only `Sarah`, even though its full Tasks screen shows the date and recurrence. The Today row builds a subtitle only for dates before the start of today, at `Aging/Views/TodayView.swift:501-509`.

Impact: the user cannot distinguish a due-today task from a task with no date when the assignee is present. The section heading implies urgency, but the row does not show the date or “Today” explicitly.

### AUD-14, P2: Settings reports signed-out state but offers no sign-in path

Persona: local-only supporter who decides to back up or share after setup.

Status: reproduced manually and confirmed in source.

The Sharing tab contains a clear Sign in action at `Aging/Views/Groups/FamilyView.swift:154-166`. Settings, where a user is likely to look for account and backup controls, only displays `You are not signed in. Everything stays on this phone.` at `Aging/Views/SettingsView.swift:153-158`.

Impact: the account screen tells the user what is missing but does not let them resolve it. The user has to discover that sign-in lives under Sharing, even though the requested outcome may be backup rather than collaboration.

### AUD-15, P2: the search prompt understates what can be found

Persona: caregiver searching during a visit or ER intake.

Status: source review, with seeded search navigation manually exercised.

The Care search prompt says `Search meds, tasks, providers, visits, notes`, at `Aging/Views/PeopleView.swift:87-91`. The search implementation also covers people, health details, emergency contacts, vitals, symptoms or falls, and timeline entries. A user looking for “blood pressure”, “daughter”, “allergy”, or “fall” receives no hint that those searches are supported.

The search results did open the correct destination in the seeded run, so this is a discoverability problem rather than a navigation bug.

### AUD-16, P2: the Notes empty state recommends storing a gate code while the editor warns against secrets

Persona: family member using Notes for practical information.

Status: source review.

The empty Notes screen explicitly suggests `the gate code`, at `Aging/Views/CareNotesView.swift:32-40`. The editor footer then says the note is ordinary plaintext, visible to every helper, and not a secure vault, at lines 165-177.

A gate code may be useful family information, but it is also a credential-like secret. The two messages create the exact ambiguity the security warning is intended to prevent. The note is searchable and synced under ordinary group permissions.

### AUD-17, P2: check-in language is easy to overread as a safety signal

Personas: caregiver monitoring a subject and subject pressing the button.

Status: source review, with the large subject button manually reviewed.

The subject sees `I'm OK today`, and the supporting copy says `Press the button once a day so your family knows you're OK`, at `Aging/Views/CheckIn/CheckInHomeView.swift:85-120`. Today shows `Checked in today` with no qualifier at `Aging/Views/TodayView.swift:120-143`. The caregiver's Today view does not expose the local record's dirty or unsynced state, while the subject view does.

The settings page correctly says that nobody is called and no help is sent, at `Aging/Views/CheckIn/CheckInSettingsView.swift:40-75`. That disclaimer is not present at the point where a caregiver sees the daily status. A caregiver can therefore read “Checked in today” as “the person is safe” or assume other family members received it, when it only proves that a button record exists on the current device.

### AUD-18, P2: check-in windows cannot cross midnight

Persona: caregiver arranging a check-in for someone whose agreed window runs overnight.

Status: static finding.

The UI presents separate From and Until times, but saving forces the end to be at least one minute after the start on the same day, at `Aging/Views/CheckIn/CheckInSettingsView.swift:175-186`. There is no explanation that a window such as 8:00 PM to 8:00 AM is unsupported, nor a way to represent it. If overnight care is in scope, this silently produces an impossible schedule.

### AUD-19, P2: Plus plans are difficult to compare before purchase

Persona: caregiver reaching the second-person paywall.

Status: reproduced manually in the StoreKit test path and confirmed in source.

Monthly, yearly, and lifetime plans are rendered as identical prominent buttons with only a title and raw price, at `Aging/Views/PaywallView.swift:45-73`. There is no visible price per month, annual savings, selected state, or short explanation of the tradeoff. The trial and renewal terms are a long caption below the buttons.

The paywall is understandable enough to continue, but the user must do mental arithmetic and read small text to compare plans. A one-tap purchase choice should not require guessing which button is best value.

### AUD-20, P2: sync conflicts are surfaced but cannot be reviewed or resolved

Persona: family member editing a health record while offline.

Status: static finding.

The sync engine marks records as `needsReview` and retains the local copy when it detects a genuine conflict. Settings only displays a passive label such as `1 change needs a look`, at `Aging/Views/SettingsView.swift:142-150`. There is no navigation destination, record list, comparison view, or resolution action. The underlying conflict state is created at `Shared/Services/SyncEngine.swift:956-969`.

Impact: the user is told that a health record needs attention but cannot find the record or act on it. A manual support intervention or repeated sync attempt is the only apparent next step.

### AUD-21, P3: empty-state add actions are inconsistent

Personas: new caregiver exploring the feature catalog.

Status: manually observed in the fresh record and confirmed in source.

Medications and Notes provide an inline Add action in their empty state. Tasks, Visits, Providers, Vitals, Symptoms, and Emergency Contacts generally rely on the top-right plus button. A user can reach any of these features through the hub, see a “nothing yet” message, and have no equally prominent next action in the body.

The feature tiles are much clearer than the original grey-row design, but the empty-state interaction still changes from feature to feature.

### AUD-22, P2 if the page is live: invitation web copy says the app is not yet in the App Store

Persona: invited helper or subject opening an invitation on a phone or desktop.

Status: source review. Publication state was not independently checked.

The invitation link is correctly an HTTPS page with a visible eight-character code and a custom-scheme Open in Elderhub link, at `Shared/Services/InviteLink.swift:18-40` and `docs/site/join.html:63-86`. However, the page tells the invitee that Elderhub is `coming to the App Store shortly`, at `docs/site/join.html:79-80`.

If the page is already being used for current TestFlight or App Store invitations, this makes a valid invite look like a prelaunch placeholder and may send the user looking for an unavailable download. If the page is intentionally prelaunch, this should be treated as a release gate before invitations are sent.

## Persona walkthrough notes

### Local-only supporter

The no-account path is fast and the record opens offline as promised. The first-launch screen is visually clean. The main problems are identity switching between name and relationship, the lack of a later sign-in action in Settings, the incomplete setup list, and the possibility of entering a group-sharing path later without a clear distinction between local and shared data.

### Solo user

The app correctly allows a private record without an account and without a paywall. The field text still says `Their name`, and the relationship value `Me` can produce awkward and misleading `Me's record` copy. The app has no obvious reason for a solo user to visit Sharing, so backup discovery depends on finding a tab that is labelled for collaboration rather than backup.

### Signed-in owner

The family concept is understandable, and the invite form honestly says that Elderhub hands the email to Mail instead of sending it automatically. The owner can select caregiver or subject and can revoke pending invitations. The high-risk issues are group-creation failure presentation, the checklist falsely marking invitation setup complete, account switching after sign-out, and the lack of conflict resolution.

### Invited caregiver

The code-entry screen is concise and supports phone-dictated codes. The invitation message explains the caregiver's visibility. The end-to-end server acceptance path was not run. Static review identifies the local-record mixing risk if this is an existing install with ungrouped data.

### Invited subject

The reduced home screen is a strong mental model: one large button, their own medication list, and a Who can see me action. There is no paywall in the subject path. The subject should not be asked to accept transparency with an empty member list after an offline relaunch. The button and “family knows you're OK” copy also need careful expectation management because the feature is not an emergency detector or a safety guarantee.

### ER or offline user

The local-first architecture is visible in the app and the emergency card renders from local data. The live card correctly labels missing critical sections rather than implying that missing data is negative. The shared text export has the blood-type omission described above. The iOS 26 tab-bar overlay can also obscure the dose checklist at the moment a caregiver is most likely to use it.

### Family collaborator

Tasks, assignments, recurring work, notes, and shared authorship are understandable. The task editor explicitly says assignment is a note, not a notification, which prevents a false expectation. The Today task row should still show the due-today state, and sync conflicts need a usable review path.

### Accessibility and older users

The source includes deliberate Dynamic Type adaptations: Today changes the quick-action grid to two columns and the person hub changes feature tiles to one column for accessibility sizes. Feature tiles and the check-in button have explicit accessibility labels. I did not complete a full accessibility-size manual run because the UI test runner stalled, so this is a coverage note rather than a pass claim. The clipped lower content on iOS 26 is more concerning for larger text because it increases the amount of scrolling required to reach critical rows.

## What worked during the audit

- Fresh onboarding presents three understandable high-level paths without requiring sign-in for local tracking.
- Today exposes the main feature set with six quick actions, and the Medical menu contains the less frequent medical record features.
- Feature tiles explain their purpose instead of only naming a destination.
- The emergency card has an explicit empty state and an Add details action.
- Person deletion and emergency-contact deletion include confirmation language that explains the shared impact.
- Invitation creation distinguishes “write an email” from “send an email” and provides a code fallback.
- The subject surface has a separate restricted root and a visible transparency path.
- The Settings and emergency card disclaimers clearly say the app does not diagnose, detect illness, or call for help.

## Audit handoff

No app code was changed for this audit. The only intended artifact is this file. The live invite, real account switching, server-side group membership, notification delivery, and production purchase paths still need a device-level pass after the P1 items are triaged.
