# Elderhub release to TestFlight audit

Audit date: 2026-09-03

Scope: compare the currently released App Store build with the newest valid
TestFlight build, then scan the source delta, release configuration, unit tests,
and high-risk caregiver, recipient, sharing, reminder, and emergency-card
paths. This is a read-only audit. No app or project source was changed. The
uncommitted working-tree fixes present during this audit were not treated as
part of the shipped TestFlight binary.

## Comparison anchors

| Channel | Version | Build | ASC state | Uploaded |
| --- | --- | --- | --- | --- |
| App Store | 1.0.1 | 30 | `READY_FOR_SALE`, valid | 2026-08-27 08:45 PDT |
| TestFlight | 1.0.2 | 34 | valid, internal beta testing | 2026-09-03 16:30 PDT |

The live build is ASC version `1.0.1`, build 30. The latest TestFlight record is
build 34, version 1.0.2, and is not attached to an App Store version yet. The
clean source snapshots used for comparison were commit `92b5607` for build 30
and commit `943ab14` for build 34. A local archive also reported version 1.0.2,
build 34.

## Executive verdict

Build 34 is a valid, compiling build. The build delta improves recovery,
accessibility, reminder permission messaging, conflict visibility, and
emergency-contact labeling. One confirmed user-facing regression was introduced
in build 34: the new onboarding `Finish later` action discards the answer being
edited on the current step.

The more serious result is that build 34 still carries high-confidence issues
already present in build 30. The release-blocking risks are the account boundary
after sign-out, offline access after a recipient restriction, and incomplete or
hard-to-reach emergency information. The selected UI run could not complete
because the Xcode test worker stalled while materializing, so runtime UI claims
below are based on source and existing tests unless explicitly marked otherwise.

## Findings

### REG-01, P2, new in build 34: `Finish later` loses the current answer

On any onboarding details step, type or change an answer and tap the new
`Finish later` button before tapping `Continue`. The button calls `onFinished()`
directly. The current step's state is only written by `advance(saving: true)`.
When the flow is opened again from Settings, the unfinished answer is gone.

This is a data-loss and trust issue for an in-progress form. It is especially
easy to hit when somebody is interrupted while entering allergies, conditions,
or date of birth. The source comment says nothing is lost, but the current
state has not been saved.

Evidence: `Aging/Views/Onboarding/OnboardingDetailsFlow.swift:113-123,418-425`
at the build-34 source snapshot. The button is new in `92b5607..943ab14`.

### REG-02, P0, carried from build 30: sign-out does not close the account boundary

The Settings sign-out action calls `AuthService.signOut()`. That method signs
out of the auth SDK and clears session display state, but does not clear the
SwiftData mirror, cached group, pending reminders, or RevenueCat customer
identity. `RootView` continues to expose the caregiver tabs after the auth state
changes.

A different person using the handset can therefore see the previous family's
medical records and may receive reminders naming the previous person. This is a
privacy failure, not stale UI.

Evidence: `Aging/Views/SettingsView.swift:84-87`,
`Shared/Services/AuthService.swift:245-266`,
`Aging/RootView.swift:34-87`, and
`Shared/Services/StoreService.swift:211-230`. The corresponding behavior is
present in both exact source snapshots.

### REG-03, P1, carried from build 30: access revocation is not applied offline

The server supports per-recipient access scopes, and `loadMembers()` correctly
purges inaccessible local rows through `applySelfAccess()`. The normal launch
path loads the cached member representation, refreshes the group, and syncs,
but does not call `loadMembers()`. The cached member representation also drops
the access scope and listed recipient IDs.

After an owner restricts a caregiver, that caregiver's phone can continue to
show the already-downloaded record while offline. The server may deny new
requests, but the local mirror still answers the UI until a sharing path reloads
membership. A two-device revocation run was not completed because the UI test
worker stalled, but the source path is direct and high confidence.

Evidence: `Aging/RootView.swift:60-72`,
`Shared/Models/SyncModels.swift:79-111`,
`Shared/Services/GroupService.swift:221-234,365-447,721-763`.

### REG-04, P1, carried from build 30: Everyone Today omits check-in state

When there are multiple people, Today defaults to Everyone. Its digest and
aggregate view include doses, tasks, appointments, refills, and bills, but no
check-in state. A person with check-in enabled and no check-in can consequently
appear under `Nothing due today`.

The default weekly sibling view cannot answer the recorded question "is Mom OK?"
and its clear wording can be read as reassurance. This does not require an
emergency inference, only the check-in status already stored by the app.

Evidence: `Shared/Services/TodayDigest.swift:15-46` and
`Aging/Views/TodayView.swift:289-382`. Both exact source snapshots omit this
state.

### REG-05, P1, carried from build 30: assignee name and assignee identity can diverge

The task editor allows selecting a family member and then editing the displayed
name. Saving preserves the selected `assigneeUserID` whenever the name is
nonempty. `TaskPlanner.isAssigned()` gives the ID precedence over the name.

Reproduction: select Chris, replace the visible name with Sarah, and save. The
row says Sarah but Mine still treats it as Chris's task. The picker-path UI test
does not cover this retype path.

Evidence: `Aging/Views/CareTasksView.swift:468-473` and
`Shared/Services/TaskPlanner.swift:75-94`.

### REG-06, P1, carried from build 30: an empty emergency card is ambiguous

When all critical fields are empty, the live card replaces its sections with a
single `Nothing on the card yet` setup prompt. The export instead prints named
critical headings with `Not recorded` values.

An ER clinician cannot tell whether a field is unknown, not applicable, or
omitted. The empty live and exported handoffs also communicate different
states.

Evidence: `Aging/Views/EmergencyCardView.swift:16-64,217-236` and
`Shared/Services/MedListExporter.swift:23-65`.

### REG-07, P1, carried from build 30: live card and export contain different medication detail

The live emergency card shows the medication name, schedule or as-needed state,
and purpose. The exported one-pager additionally includes form, instructions,
prescriber and phone, and pharmacy and phone.

The two routes look like alternate emergency handoffs without telling the user
that one is only a summary. A clinician can receive materially different
medication context depending on which route Sarah opens.

Evidence: `Aging/Views/EmergencyCardView.swift:261-300` and
`Shared/Services/MedListExporter.swift:101-135`.

### REG-08, P1, carried from build 30: date of birth is promised but omitted

Onboarding says date of birth prints on the emergency card. The live card
prints name, age, and blood type, while the export prints name, age, blood type,
and generated time. Neither prints date of birth.

Age is not an equivalent patient-matching value in an emergency. This creates a
false expectation about a high-value identity field.

Evidence: `Aging/Views/Onboarding/OnboardingDetailsFlow.swift:189-207`,
`Aging/Views/EmergencyCardView.swift:238-258`, and
`Shared/Services/MedListExporter.swift:12-20`.

### REG-09, P1, carried from build 30: emergency-card retrieval is too deep

In single-person Today, the emergency-card action follows setup, tasks,
appointments, refills, doses, and bills. In Everyone mode, the default for a
multi-person account, there is no direct emergency-card action in the aggregate
content. The user must first select the person, then find the card through the
person path.

This is a poor 30-second handoff for an unfamiliar ER clinician. The priority is
based on interaction depth and layout, not a timed runtime failure.

Evidence: `Aging/Views/TodayView.swift:289-381,525-635`,
`Aging/Views/PersonDetailView.swift:150-179,204-321`, and
`Aging/Views/EmergencyCardView.swift:31-66`.

### REG-10, P1, carried from build 30: recipient mode can silently show the wrong person

Recipient mode resolves the stored handover ID first, then falls back through
an auth-linked row, `isSelf`, and finally the first local person. If the stored
handover ID is stale, the fallback is silent. The screen title is only `Today`
and does not persistently show the person's entered name.

Eleanor can press check-in or read medication information for a different person
without a strong identity signal. A stale handover should be explicit and
recoverable, not guessed.

Evidence: `Aging/Views/CheckIn/CheckInHomeView.swift:41-99`,
`Shared/Services/DeviceModeService.swift:82-95,113-158`.

### REG-11, P1, carried from build 30: recipient cold start can look broken

If recipient mode renders before the local person arrives through sync, the
screen shows `Nothing here yet`. Recovery is the outer scroll view's pull to
refresh, with no visible retry button. Root sync runs asynchronously after the
initial view is rendered.

Eleanor can reach a blank screen with no check-in control or emergency context
and conclude that the handover failed. The exact cold-start timing was not
runtime-validated because the test worker stalled.

Evidence: `Aging/Views/CheckIn/CheckInHomeView.swift:88-94,126` and
`Aging/RootView.swift:60-72`.

### REG-12, P1, carried from build 30: zero refill units silently disable low-stock warnings

The medication editor accepts zero or another nonpositive units-per-dose value.
`Medication.daysRemaining` then returns nil, so a medication with refill
tracking enabled drops out of the running-low calculation.

A setup mistake can therefore make a tracked medication disappear from refill
work without an error or warning.

Evidence: `Aging/Views/MedicationEditorSheet.swift:118-140,281-290`,
`Shared/Models/CareModels.swift:382-402`, and
`Shared/Services/TodayDigest.swift:175-181`.

### REG-13, P1, carried from build 30: transparency can be acknowledged without a member list

When the member list cannot load, Transparency shows an error or loading state,
but still leaves `I understand` available. The user can complete the disclosure
without seeing who currently has access.

That weakens consent and sharing trust exactly when the access picture is
unknown.

Evidence: `Aging/Views/Groups/TransparencyView.swift:78-132` and
`Shared/Services/GroupService.swift:365-447`.

## Additional P2 findings and product gaps

| ID | Status | Finding | Evidence and impact |
| --- | --- | --- | --- |
| REG-14 | Carried | Group creation failure can advance onboarding after showing an error. The record can look ready while the circle is not created. | `Aging/Views/Onboarding/OnboardingFlow.swift:289-326` |
| REG-15 | Carried | Search flattens private, stranded, and shared people into unlabeled results, erasing the scope distinction present in the normal Care list. | `Aging/Views/PeopleView.swift:45-107,356-409`, `Shared/Services/CareSearch.swift:91-113` |
| REG-16 | Carried | Generic person notes are excluded from both emergency handoffs without telling the person entering them at that point. | `Aging/Views/PersonDetailsEditorSheet.swift:118-121,188-196`, `Aging/Views/EmergencyCardView.swift:79-87`, `Shared/Services/MedListExporter.swift:1-136` |
| REG-17 | Carried | Task and bill completion controls do not have the explicit minimum hit-area contract used by dose controls. This is a source risk, not a measured miss-tap. | `Aging/Views/TodayView.swift:1084-1090,1131-1139,1261-1267` |
| REG-18 | Carried | The live emergency card has no freshness timestamp while the export has a generated timestamp. | `Aging/Views/EmergencyCardView.swift:60-63,238-258`, `Shared/Services/MedListExporter.swift:12-20` |
| REG-19 | Carried | A weekly sibling has no since-last-visit or unread-change summary. Today shows current outstanding work, not what changed since the last visit. | `Shared/Services/SyncCoordinator.swift:18-77`, `Aging/Views/TimelineView.swift:16-95`, `Aging/Views/CareTasksView.swift:119-141` |
| REG-20 | New, static risk | `PhoneNumberField` rewrites the full field on every edit. Inserting into the middle of an existing number may move the caret and make correction frustrating. The stalled UI run prevented device confirmation, so this is not counted as a confirmed regression. | `Aging/Views/Components/PhoneNumberField.swift:17-24` |

## ASC and release-configuration notes

- The live 1.0.1 listing still contains the pre-rename `jackwallner.github.io/medlist` URLs. The current repository metadata uses `/elderhub` URLs. The redirect repository keeps the old paths resolving, so this is metadata drift rather than a confirmed broken link.
- Build 34 is TestFlight-only and not attached to a draft App Store version. It should not be treated as evidence that the next App Store listing metadata has been uploaded.
- The build record is valid, targets iOS 17 or later, and is not expired.

## Validation performed

- The exact build-30 source snapshot generated with XcodeGen and built successfully in Release configuration on a leased headless simulator.
- The exact build-34 source snapshot generated with XcodeGen and built successfully in Release configuration on the same leased headless simulator.
- The exact build-34 Debug `AgingTests` suite passed. Xcode emitted two existing compiler warnings in `GroupService.swift` about nested fallback `try await` expressions with no async operations.
- The exact build-30 Release unit-test attempt and the selected build-34 UI tests stalled in Xcode while waiting for test workers to materialize. They were stopped after the hang. These runs are inconclusive, not app test failures.
- A two-device access-revocation run, real APNs delivery, and a real RevenueCat purchase were not completed in this audit.

## Verified build-34 improvements

The following changes were present in the TestFlight source and did not show a
source-level regression during the scan: explicit `CALL FIRST` labeling and
extension-safe dialing, larger and labeled check-in and dose controls, visible
undo for recent Today actions, blocked-notification guidance, a non-spinning
paywall failure state with Restore still reachable, and readable local versus
remote conflict summaries.
