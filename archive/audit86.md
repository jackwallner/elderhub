# Elderhub super-audit

Audit date: 2026-08-06

App: Elderhub, bundle and scheme still named `Aging`

Audit target: the shipped user experience, not an implementation review. No app code was changed. The simulator store was reset and reseeded as needed during testing.

## Executive verdict

Elderhub has a coherent care-record model and a much clearer hub than a plain list app. The seeded experience makes the major capabilities discoverable, the offline-first message is unusually clear, and the app avoids emergency-detection claims. The strongest positive pattern is that most records are local-first, shareable in concept, and organized around a person rather than around isolated tools.

The app is not ready for a high-confidence caregiver or medical-record workflow. The largest risks are record correction, emergency-card completeness, check-in reliability and discoverability, stale Med List branding after the Elderhub rename, and sensitive information being invited into an unstructured shared Notes field. Several records can be created blank, and several important records can be deleted and recreated but not edited. Those are not cosmetic problems in a medication and health-history product.

Highest-priority findings:

1. Saved medications cannot be edited. The same is true for visits and vitals. The user must delete and recreate a record to correct it.
2. The Emergency Card hides missing sections instead of showing unknown or not recorded. A hurried reader can mistake absent data for negative data.
3. Daily check-in is buried in a person hub and omitted from the Today quick actions. Notification denial can leave the feature looking enabled without an effective reminder.
4. The paywall, StoreKit plan labels, and linked privacy page still say Med List even though the product is now Elderhub.
5. Notes visibly normalize storage of gate codes and insurance policy numbers even though Notes are plaintext, shared with the family group, and searchable. The product boundary says Notes are not a password vault, but the user experience points users toward exactly that behavior.
6. People search returns non-interactive hits. A user can find a medication, provider, visit, task, event, contact, or note but cannot open the result.
7. Blank visits and blank incident/symptom entries can be saved. These create meaningless rows in the record and Timeline.
8. Emergency contact phone numbers are plain text on the Emergency Card, while provider phone numbers are tappable. The more urgent contact path is less actionable.

There were no observed launch crashes, no observed data loss during normal local flows, and no evidence that the check-in path imports or gates on billing. The runtime audit used a seeded local store, so remote authentication, group membership, real sync, production purchase behavior, and subject-mode backend flows remain source-reviewed rather than runtime-proven.

## Audit method and evidence

The audit combined four forms of evidence:

- Direct interaction with the iOS app on a headless iPhone 17 Pro simulator running iOS 26.3.
- Clean onboarding runs and a seeded demo-data run containing multiple people and records.
- Source review of every view under `Aging/Views`, the shared models, the search, timeline, sync, check-in, billing, export, and group services.
- A second pass over the feature catalog, navigation routes, screen inventory, and issue register after this document was drafted.

Severity used below:

- P1: high user, safety, privacy, trust, or data-integrity impact. Resolve before relying on the feature in a real care workflow.
- P2: material friction, ambiguity, or recoverability problem. Resolve before broad polish or launch confidence.
- P3: small inconsistency, discoverability gap, or quality issue that does not usually block completion.
- Positive: behavior that is working well and should be preserved.

Evidence labels:

- Runtime: directly seen or exercised in the simulator.
- Source: confirmed by reading the relevant view/service/model.
- Inference: likely consequence of the observed UI or code path, requiring a backend or device-state confirmation.

## Test matrix and limits

| Area | Coverage | Evidence |
| --- | --- | --- |
| Clean onboarding | Supporter/local path, solo/local path, subject path to sign-in, name entry, back navigation | Runtime plus source |
| Seeded caregiver use | Today, People, person hub, medications, tasks, vitals, symptoms, visits, providers, contacts, notes, timeline, Emergency Card | Runtime plus source |
| Family tab | Signed-out/local state and sign-in presentation | Runtime plus source |
| Settings and paywall | Settings sections, legal links, Pro sheet, plan labels, restore affordance | Runtime plus source |
| Check-in | Settings off/on, notification prompt, caregiver recording, enabled state | Runtime plus source |
| Search | Search implementation and result-row interaction model | Source, with list UI inspected |
| Group and subject flows | Invite, join, roles, transparency, subject home, leave/delete | Source review; no usable Supabase account was available |
| Offline and sync | Local-first code paths and copy | Source review; no network transition or conflict session |
| Purchase | Simulator-safe configuration and paywall rendering | Runtime plus source; no purchase was made |
| Dark mode | Not completed | Open coverage gap |
| Dynamic Type and VoiceOver | Not completed as a full matrix | Open coverage gap |
| Landscape and iPad | Not completed | Open coverage gap |
| Non-US locale and metric units | No locale switch; source shows fixed units | Source finding |
| Real notification delivery | Permission prompt exercised; delivery and denial state not fully proven | Runtime plus source |

The first build produced the app successfully. A CoreSimulator IPC failure interrupted the first install, then the leased simulator was recovered headlessly and the existing build was installed and launched. The only compiler warning seen in that build was unreachable code after the simulator-only early return in `Shared/Services/StoreService.swift`. That warning is not a user-facing defect, but it makes simulator build output noisier and can mask future warnings.

The automation sometimes returned stale accessibility references after a navigation or simulator state transition. Those cases were not counted as product navigation bugs unless the source and a repeatable screen state supported them.

## Persona audit

### Persona A: adult child, first-time caregiver

Goal: add a parent, record medicines, understand what else the app can hold, and get useful information quickly during a stressful week.

What worked:

- The first question, “Who are you here for?”, is concrete and gives supporter, subject, and solo choices.
- The person hub has a useful mental model: header, setup progress, feature tiles, emergency card.
- The Today screen immediately exposes doses and tasks instead of requiring the user to understand the data model first.
- “The list lives on this phone too, so it opens with no signal” sets the right expectation for an ER or clinic setting.

Problems:

- The supporter account frame calls the action “Create your family” before the user has even created a person or decided to share. “Not now” is the actual local-only path, but the button hierarchy makes the account route feel like the expected route.
- The setup checklist says “0 of 6 set up” and shows only three next actions. Hiding it is easy, but there is no visible way to restore it once hidden.
- The most important data-correction path is missing. A first-time caregiver can save a medication quickly, but cannot later correct its schedule, strength, reason, refill amount, or instruction.
- The empty Today medication action opens the person hub, where the user has to find and tap Add medication a second time. The label promises a direct action.
- Search looks like a global escape hatch, but its result rows do not open anything.

Related findings: AUD-001, AUD-005, AUD-006, AUD-012, AUD-026, AUD-030.

### Persona B: sibling caregiver joining an existing family

Goal: join with a code, understand access, see who did what, and avoid creating duplicate or conflicting records.

What worked in source and local UI:

- Invite copy distinguishes another caregiver from the person being looked after.
- Subject invites are described as one-time, eight-character codes with an expiry window.
- Roles, organizer promotion, removal, and leaving a group have explicit surfaces.
- Task completion is treated as agreement, while text edits are conflict-sensitive in the task sync model. That is a good domain decision.

Problems and unverified behavior:

- The dose list writes a new local dose with `recordedBy: "You"`. In a shared family record, that loses the member's identity and is inconsistent with the richer author treatment used elsewhere.
- The Transparency screen lists medications, dose status, allergies and conditions, contacts, visits and readings, and check-ins, but does not clearly mention Notes, Tasks, or Providers. A sibling cannot make an informed privacy decision if the visible disclosure is not exhaustive.
- Family mutations and sync behavior were not runtime-tested because no backend account was available. The source deserves a dedicated two-device and offline conflict pass before relying on the role language.
- A group owner can reach a destructive delete-group confirmation without the typed phrase required by the separate leave-group sheet. The warning is not symmetrical for two destructive paths.

Related findings: AUD-017, AUD-022, AUD-023, AUD-031, AUD-032.

### Persona C: the person being looked after

Goal: join without learning the whole caregiver product, understand who can see data, check in once a day, and optionally mark doses.

What worked in source:

- The subject onboarding explicitly says a family code is needed and routes to a dedicated Join with a code path.
- Subject transparency is a separate, consent-oriented screen rather than hidden in settings.
- The subject home has one large “I’m OK today” action, a visible last check-in, an offline save message, and medication status.
- The check-in path contains no billing service dependency and does not claim to detect emergencies or summon help.

Problems:

- The subject sign-in route has no local skip. If the person cannot or does not want to use Sign in with Apple, the only route back is Back to the initial path, which discards the current step rather than offering a clearly explained alternative.
- The subject view is source-reviewed only. Code should be exercised with a real linked subject, including invitation acceptance, transparency acknowledgment, offline check-in, a second-day check-in, dose marking, and leaving the group.
- The one-check-in-per-day behavior has no correction or undo path. A mistaken tap by an older user or a caregiver recording on their behalf cannot be reversed from the visible screen.
- The copy says everyone looking after the subject is told if the window is missed, but the local permission and remote delivery states are not transparent enough to establish that promise.

Related findings: AUD-014, AUD-015, AUD-016, AUD-027, AUD-032.

### Persona D: ER clinician or a stranger holding the phone

Goal: identify the person, see current medications and critical facts, and call the right person or provider without interpreting silence as a negative answer.

What worked:

- Emergency Card is a dedicated, visually simple surface with name, age, medications, contacts, providers, and a disclaimer.
- The disclaimer correctly says the list is maintained by a family member and is not a medical record.
- The share action produces a plain-text one-pager suitable for sending through the system share sheet.

Problems:

- Empty sections disappear. If allergies, blood type, emergency contacts, or providers have not been entered, the card does not say “not recorded” or “unknown.” The absence can be misread as “none.”
- Emergency contact phones are not tappable. Provider phone numbers are tappable, which creates an inconsistent and backwards priority for the emergency use case.
- The card and exported text are not equivalent. Providers shown on the card are not included in the plain-text exporter, and the export has no explicit completeness status or preview before sharing.
- Optional medication fields allow a card entry with a name but no strength, schedule, purpose, or form. That can make the card materially less useful at the exact moment it is relied on.

Related findings: AUD-006, AUD-007, AUD-008, AUD-009.

### Persona E: older adult or low-vision user

Goal: read the current state, complete one simple action, and avoid accidental destructive actions.

What worked:

- The subject check-in button is large and uses a plain sentence.
- The app uses familiar tab labels and mostly standard navigation controls.
- The check-in explanation avoids alarmist language and clearly states that nobody is called.

Risks and open verification:

- The audit did not complete a full Dynamic Type, VoiceOver, or reduced-motion pass. This is a release-blocking coverage gap for the target audience, not evidence that every accessibility property is broken.
- Several important actions are hidden in swipe gestures, including dose correction via Skip and destructive deletion. Those actions are easy to miss and hard to discover without motor or vision assumptions.
- A check-in recording becomes disabled after the daily record and offers no correction. A simple action needs a clear confirmation or recovery path.
- Lower content is repeatedly covered or visually crowded by the persistent tab bar when pushed screens are scrolled to the bottom.

Related findings: AUD-016, AUD-018, AUD-019, AUD-033.

### Persona F: offline caregiver in a clinic, ambulance, or basement

Goal: open records and make changes with no signal, then trust that those changes will reconcile later.

What worked:

- The app consistently tells the user that records live on the phone and work without an account or signal.
- The source architecture uses SwiftData as the local mirror and keeps sync out of the rendering path.
- Synced records use local changes and tombstones rather than hard deletes in normal feature flows.
- Check-in also writes locally and has an offline status message.

Risks and open verification:

- No network transition was performed in this audit. The critical matrix is: create, edit, delete, and complete one of each record type offline, relaunch, reconnect, then verify the same record on a second account/device.
- A user cannot repair several incorrect records even while offline because edit surfaces are missing, not because sync is unavailable.
- The app's visible offline promise is stronger than its account disclosure. Local users are told that the list stays on the phone, but the account frame does not clearly distinguish backup from sharing and account recovery.

Related findings: AUD-001, AUD-002, AUD-003, AUD-017, AUD-028, AUD-031.

## Screen and frame inventory

The following inventory is the frame-by-frame review. “Runtime” means the frame was opened or exercised on the headless simulator. “Source” means the frame and behavior were reviewed in the relevant SwiftUI view and model/service. Variants such as empty, populated, enabled, and destructive states are listed separately because they carry different user risks.

### Onboarding frames

#### 1. Path picker, “Who are you here for?”

Runtime. Three large cards are presented:

- “I’m looking after someone,” with parent or partner language.
- “Someone is looking after me,” with family-code language.
- “Just me, for now,” for a personal list.

The footer says the choice can be changed later. This is a strong first frame because it explains the product in terms of roles rather than feature names.

Audit notes:

- The three choices are understandable without prior app knowledge.
- “Just me, for now” is friendly but slightly undersells that the app can still become a shared care record later.
- The role choice is not merely cosmetic. It changes whether account creation is optional or required, so the consequences should be made explicit before commitment.

#### 2. Sign-in, supporter/local variants

Runtime. “Create your family” contains Sign in with Apple, Not now, and copy about brothers and sisters seeing the same list. The list also works on the phone with no signal.

Audit notes:

- Sign in with Apple is visually primary. That is appropriate for sharing, but the frame does not say plainly that signing in enables backup and sharing while Not now keeps the list local.
- “Create your family” implies an immediate group and may make a solo/local user wonder whether they are in the wrong place.
- “Not now” is the only local route, and it does not say “Continue without an account.”
- There is no visible explanation of what happens to local data if the user later signs in, signs out, or changes devices.

#### 3. Sign-in, subject variant

Runtime/source. “Join your family” says the code comes on the next screen and has a Back action. There is no Not now.

Audit notes:

- The requirement is honest, but a subject who cannot authenticate is given no alternative explanation or support route.
- Back returns to the path choice. It is not a meaningful “previous step” once a subject has started joining.

#### 4. Person name frame, supporter variant

Runtime. “Who are you keeping track of?” offers a name field and relationship chips such as Mom, Dad, Me, and Spouse. It says to start with one person.

Audit notes:

- The relationship chips reduce typing and establish the person hub's vocabulary.
- The primary save requirement is a name. The relationship can remain weak or defaulted, which can lead to “Mom” being used as a label without enough identity context in a multi-person household.
- A user who taps Back from sign-in or a previous step risks losing partially entered context.

#### 5. Person name frame, solo variant

Runtime. “What should we call you?” says “Your own list” and presents the name field. The placeholder still says “Their name,” which is inconsistent with the question.

Finding: the pronoun mismatch is small, but it creates uncertainty about whether “Me” or another person is being created. P3.

#### 6. Join-code frame

Source. The code is normalized to uppercase, spaces are stripped, and an eight-character requirement is enforced before joining. Error text is available.

Positive: the code treatment is tolerant of common handoff mistakes.

Open runtime work: expired, already-used, wrong-group, offline, and network-retry responses should be tested with real RPC responses.

#### 7. Subject transparency onboarding

Source. The subject can review what the group can see, acknowledge it, and continue. The transparency language is one screen and includes leaving the group.

Finding: the disclosure names medications, dose status, allergies and conditions, contacts, visits/readings, and check-in, but does not explicitly enumerate Notes, Tasks, or Providers. P1 privacy clarity, AUD-022.

### Global navigation and shell frames

#### 8. Caregiver tab shell

Runtime. Today, People, Family, and Settings are persistent tabs.

Positive:

- The four top-level destinations are stable and easy to return to.
- The tab shell makes the product feel like a complete care workspace rather than a single-purpose medication list.

Finding: the persistent tab bar remains visible while pushed screens such as the person hub, Emergency Card, and detail lists scroll. Lower rows and footer content can sit behind or immediately under the tab bar. P2, AUD-019.

#### 9. Person picker menu

Runtime. The Today top-right person chip opens a Mom/Dad menu with a checkmark.

Audit notes:

- Switching context is compact and works.
- The chip is small and can be missed by users who assume Today is a global dashboard.
- The screen subtitle does not repeat whose Today view is active after scrolling.

### Today frames

#### 10. Today empty state

Runtime. The screen says “No medications yet” and offers “Add a medication.” The action opens the person hub, not the medication editor.

Finding: this is a two-step action disguised as a direct action. P2, AUD-026.

#### 11. Today populated state

Runtime. The screen shows a title and “Log or look up,” then quick actions for Meds, Tasks, Visits, Medical, Notes, and Contacts. Dose and task sections are visible.

Positive:

- The quick-action row substantially improves discoverability.
- The Medical menu groups vitals, symptoms, providers, health details, and history without overflowing the screen.
- Tasks show due date and assignee. Doses show time and strength.

Audit notes:

- Check-in is not in the row or Medical menu. It is central enough to deserve a visible Today route.
- The footer copy mentions meds, tasks, vitals, visits, providers, and history but omits Notes, Contacts, and Check-in, so the feature map is incomplete.
- Tapping a task completion circle removes the row immediately. The user does not get an inline undo.
- Tapping Taken changes the row to Taken by “You.” The visible route for correction is a hidden swipe action labeled Skip, not a direct undo or “Not taken.”
- A dose saved by one family member is recorded with `You` rather than a stable member identity. P1 shared-record attribution, AUD-017.

#### 12. Today task and dose states

Runtime/source. Overdue tasks and today's tasks are mixed into the Today workflow. Completed tasks leave the active list and can be reopened from Done in the full Tasks screen. Taken doses have a completed state.

Finding: recovery exists for tasks but is not symmetrical for doses. A caregiver can accidentally confirm a dose and have no obvious way to restore it. P2, AUD-018.

#### 13. Medical quick-action menu

Runtime. Log vitals, Log a symptom, Doctors, Allergies, and History are available.

Positive: the menu prevents the original seven-chip overflow problem and reaches the core medical features.

Finding: it adds a layer to all medical routes, and the labels are not consistent with the feature catalog, which uses Providers, Symptoms, Health Details, and Timeline. P3 discoverability and terminology, AUD-034.

#### 14. Today emergency-card footer

Runtime/source. Emergency Card and full records are reachable below Today content.

Finding: the emergency action is not visually close to the top of the daily screen and can be crowded by the persistent tab bar. An ER-oriented action should be reachable without scrolling through today's work. P2, AUD-019 and AUD-035.

### People and person hub frames

#### 15. People list, populated

Runtime. Search field says “Search meds, providers, visits, notes.” Person rows show full name, relationship, medication count, and setup progress.

Positive:

- The row gives a useful snapshot without opening each person.
- Setup progress makes incomplete records visible.

Audit notes:

- The placeholder names only four searchable types while the source search includes tasks, events, contacts, and persons too.
- A swipe delete on a person immediately tombstones the person and cascades recipient data. There is no confirmation or undo in the visible list. P1, AUD-013.
- The plus button correctly triggers the paywall when the free one-recipient limit is reached. The free-tier rule is one recipient, not one family member, and the paywall copy should keep stating that distinction.

#### 16. People search results

Source. Search covers persons, medications, providers, visits, care events, tasks, contacts, and notes, with a short debounce. `SearchHitRow` is a plain row rather than a Button or NavigationLink.

Finding: search can identify a result but cannot take the user to it. This is a dead end in a feature that appears to promise global lookup. P1/P2, AUD-012.

#### 17. Person hub, top frame

Runtime. The header shows the person's full name, relationship and age. Stat tiles show Doses today, Tasks due, and Running low.

Positive:

- The hub communicates the breadth of the app quickly.
- The stats provide orientation without pretending to assess health.
- Feature tiles are buttons and use a single navigation destination, avoiding the fragile nested link pattern.

Audit notes:

- “Running low” is a count/status that depends on refill data, but the setup path allows medication records without refill tracking. The visual needs an obvious empty-state explanation when no refill data exists.
- The age and relationship are useful identifiers, but the hub does not show a last-updated or sync state at the top for a shared record.

#### 18. Person hub, setup-card states

Runtime. The setup card starts at 0 of 6 and shows up to three remaining actions. Observed actions included adding a medication, turning on dose reminders, adding allergies and conditions, adding an emergency contact, inviting family, and setting up a daily check-in.

Positive: setup is progressive and maps to real value, not generic onboarding.

Findings:

- Hide has no visible restore or “show setup” action. P2, AUD-030.
- Check-in is represented in setup but not in Today quick actions. This gives a new user a one-time prompt but not a durable daily entry point. P1, AUD-014.
- A checklist row can route into a screen with another layer of action. The medication row from an empty Today state is the clearest example.

#### 19. Person hub, feature-tile frame

Runtime/source. Everyday tiles include Tasks, Vitals, Symptoms, and Check-in. Record tiles include Visits, Providers, Health Details, Contacts, Notes, and Timeline. Emergency Card is a separate banner.

Positive: the shared `CareFeature` catalog reduces the chance that a feature appears in one navigation surface but not another.

Finding: the catalog's coverage does not solve the check-in route being omitted from Today, and its wording varies across surfaces. P2/P3, AUD-014 and AUD-034.

### Medication frames

#### 20. Medication list and empty state

Runtime. Medications appear inline in the hub with name, strength, schedule, and refill-related summary. The empty state routes to an Add Medication action.

Finding: the medication row has no edit affordance. Tapping the name or summary does nothing. Only delete is available through swipe. P1, AUD-001.

#### 21. Add Medication, scheduled variant

Runtime/source. The sheet contains name, strength, form, schedule, time, additional times, refill tracking, reason, prescriber, instructions, linked provider, and pharmacy.

Positive:

- The sheet covers the information caregivers actually need.
- As-needed medication hides scheduled time controls, which prevents one obvious contradiction.
- The doctor-facing fields are optional and separated from the basic medication identity.

Findings:

- Save requires only the medication name. A medication can have no strength, form, schedule, purpose, or instructions, then appear on Today or Emergency Card with insufficient context. P1, AUD-006.
- Duplicate schedule times are accepted. A manually saved medication with 8:00 AM twice produced 0/2 doses on Today. There is no warning or clear reason to intentionally create two identical slots. P1/P2, AUD-005.
- “Track refills” reveals defaults such as 30 on hand and a 7-day warning. Defaults can look like entered facts if the caregiver does not review them.
- The editor title is always “Add Medication” and there is no edit mode. P1, AUD-001.
- The model has a label-photo field but no visible way to use it. This is not a defect by itself, but it is an unexposed expectation if the model or future copy suggests label support.

#### 22. Add Medication, as-needed and refill variants

Source/runtime. As-needed removes time scheduling. Refill tracking adds on-hand quantity, units per dose, and warning threshold.

Audit notes:

- “As needed” does not explain how a caregiver should record an as-needed administration or what appears on the Emergency Card.
- The form picker includes liquid, injection, inhaler, patch, cream, drops, and other, but the visible dose unit remains dependent on free text. This can produce ambiguous entries such as “10” with no unit.

### Emergency Card and health detail frames

#### 23. Emergency Card, populated

Runtime. The card showed identity, age, scheduled medication, emergency contacts, providers, a Share action, an Edit action, and the disclaimer that it is not a medical record.

Positive: the surface is focused, printable/shareable in concept, and does not use clinical claims.

Findings:

- Sections with no data disappear rather than showing unknown or not recorded. P1, AUD-007.
- Contact numbers are plain text and cannot be tapped to call. P1/P2, AUD-008.
- Provider phone numbers are tappable, while emergency-contact numbers are not. This inconsistency is especially confusing because contacts are framed as the primary people to call.
- The disclaimer is visible on the card and in Settings, which should be preserved.

#### 24. Emergency Card, empty state

Runtime/source. The prompt says “Nothing on the card yet” and asks the user to add allergies, conditions, blood type, and who to call. It calls the page the one handed to a paramedic.

Finding: the empty prompt is useful, but the populated partial state needs the same completeness discipline. A card with medications but no allergies should not look complete by omission. P1, AUD-007.

#### 25. Person details editor

Runtime. The editor includes name, relationship, date of birth, blood type, allergies, conditions, emergency contacts, and notes.

Finding: existing allergy and condition entries use example text such as “Penicillin” and “Type 2 diabetes” as input placeholders. On a populated form, that can look like a duplicate value or an instruction to re-enter the existing value. P2, AUD-024.

Positive: duplicate allergy and condition additions are prevented, and draft values are committed on Save rather than on every keystroke.

#### 26. Emergency contacts list and editor

Runtime/source. Contacts can be edited by tapping a row, deleted by swipe, and assigned as the primary person to call. Saving a new primary demotes the prior primary.

Positive: primary-contact exclusivity is clear in the model behavior.

Findings:

- Save requires a name but not a phone number. A “call first” contact can therefore be listed first without a usable call route. P1/P2, AUD-008.
- Delete has no confirmation. Because this is emergency-card data, accidental swipe deletion deserves stronger recovery than an ordinary list item. P2, AUD-036.

### Tasks frames

#### 27. Tasks list

Runtime. Tasks are grouped into Today, Later, No date, and Done. Rows show title, assignee, recurrence, notes, and completion controls.

Positive:

- Done can be reopened.
- The recurrence model creates the next task after completion, which is easy to understand from the visible grouping.
- The footer makes a valuable promise explicit: assignment is a family note, not a notification.

Findings:

- A task can have no date and can disappear from the daily workflow indefinitely. The editor does not explain the practical consequence of choosing no date. P2, AUD-037.
- Swipe deletion is immediate and has no visible confirmation or undo. P2.
- “Assigned to” may be read as an actual alert by users who skim, despite the good footer. The non-notification behavior should remain prominent wherever assignment is shown.

#### 28. Add/Edit Task sheet

Runtime/source. The sheet has title, notes, optional due date, repeat, priority, assignee, and an explicit assignment footer. Save requires a title.

Positive: the optional date and recurrence states are separated, and the recurrence explanation is good.

Finding: editing exists here, unlike for medications, visits, and vitals. The product should have a consistent expectation that tapping a record opens its editor.

### Vitals frames

#### 29. Vitals list

Runtime. The list supports a reading-type picker and displays readings newest first. It contains a long blood-pressure history but no chart or trend summary.

Findings:

- Existing readings are plain rows with delete only. Tapping a reading does nothing, so an incorrect reading cannot be corrected. P1/P2, AUD-003.
- The screen is a list even though the Pro copy says “Vitals history over time.” That copy is technically compatible with a list, but a user may expect trend visualization. P2 expectation gap, AUD-025.
- Lower rows can be visually crowded by the persistent tab bar. P2, AUD-019.

#### 30. Add Reading sheet, blood pressure

Runtime. The form has a type picker, systolic and diastolic fields, date/time, and note. Save waits for valid numeric values.

Positive: paired blood-pressure validation is materially safer than allowing arbitrary text.

Findings:

- Units are fixed to mmHg, lb, mg/dL, bpm, degrees F, and percent in the model and UI. There is no metric choice or locale adaptation. P2, AUD-020.
- Severity or clinical interpretation is not claimed, which is correct for this product.

#### 31. Add Reading sheet, non-BP variants

Runtime/source. Weight, glucose, heart rate, temperature, and oxygen have type-specific unit labels.

Finding: the fixed-unit issue affects every non-BP type. A non-US user must convert values or may enter a number under the wrong unit. P2, AUD-020.

### Symptoms and incidents frames

#### 32. Incidents & Symptoms list

Runtime. The title is “Incidents & Symptoms,” while the feature tile says Symptoms. Entries are grouped by month and show type, severity when set, date, note, and logged-by.

Positive: the list preserves the distinction between a record and an alert.

Findings:

- The terminology changes between Symptoms, Incidents & Symptoms, and “Log a symptom.” P3, AUD-034.
- Severity is a 0 to 10 stepper with no anchors or explanation. Different family members can use the scale differently. P2, AUD-038.

#### 33. Add Entry sheet

Runtime/source. Type options include Fall, ER Visit, Hospital Stay, Symptom, Mood, Appetite, Sleep, Pain, and Other. The form includes date/time, severity, what happened, and a footer saying it is a record, not an alert.

Finding: Save is active with no type, note, or severity. A blank form can create a blank event, which appeared as a meaningless Symptom row and Timeline entry during the audit. P1/P2, AUD-004.

Positive: the no-alert footer is important and should remain near the save action.

### Visits and provider frames

#### 34. Visits list

Runtime. Rows show provider, date, reason, notes, and follow-up. The list is compact and readable.

Finding: existing rows are not interactive. There is no edit sheet when tapping a visit, only swipe deletion. A blank visit created in the audit persisted into the list and Timeline. P1, AUD-002 and AUD-004.

#### 35. Add Visit sheet

Runtime/source. Date, provider, specialty, linked provider, reason, notes, and next step are available. Save is active with every field blank.

Findings:

- A blank Visit can be saved and later appears as a date-only row. P1/P2, AUD-004.
- The model contains a next-appointment field with no visible input path. If future copy implies appointment tracking, this is incomplete.
- Provider selection can add a provider inline, which is convenient, but it increases the chance of duplicate provider records if names are entered inconsistently.

#### 36. Providers list

Runtime. Providers are sorted by name. Pharmacy rows are labeled, phone presence is visible, and a footer says providers with a phone number appear on the Emergency Card.

Positive: provider editing is available, unlike visits and vitals. The pharmacy distinction is useful.

Findings:

- A provider can be saved with no phone number, then silently does not appear on the Emergency Card. The list explains the rule but the editor does not enforce or preview the consequence. P2, AUD-023.
- Deleting a provider detaches it from medications and visits. That consequence is material and should be obvious before a destructive swipe completes. P2.

#### 37. Provider editor and picker

Runtime/source. Name, pharmacy toggle, specialty, phone, address, portal link, notes, and linked selection are available. The footer says a portal URL is a bookmark and no username or password is stored.

Positive: this is excellent security-oriented copy. It draws a clear boundary around credentials.

Finding: the same explicit boundary is missing from freeform Notes, where sample and visible copy point users toward storing secrets. P1, AUD-011.

### Notes frames

#### 38. Notes list

Runtime. Notes show title, body preview, date, author, and pin state. Pinned notes have a pin action; rows can be edited and deleted.

Positive:

- The list makes the body preview useful for quick household context.
- Pinning supports recurring logistics.
- The note footer explicitly says the family group can see the note and that it syncs with the person's record.

Finding: body text is plaintext, shared under the same record permissions, and included in search. The seeded note contains a gate code, and the architecture notes explicitly caution that CareNote is not a password vault. The actual product experience currently normalizes secret storage without warning. P1 privacy and security, AUD-011.

#### 39. Add/Edit Note sheet

Runtime. Title and Note are freeform, with a Pin toggle. Save is disabled only when both fields are blank.

Audit notes:

- Allowing title-only notes is reasonable.
- A note can be body-only and will still be visible and searchable.
- No sensitivity classification, warning, masking, lock, expiry, or “do not store passwords/codes” language is present.
- Notes are not clearly included in the subject transparency inventory even though they can be family-shared. P1, AUD-011 and AUD-022.

### Timeline frames

#### 40. Timeline, populated

Runtime/source. Entries are grouped by month and include visits, completed tasks, medication starts, vitals, incidents, dose history, and check-ins. A filter picker shows All, and older history can be loaded.

Positive: a single chronological view is valuable when preparing for an appointment or explaining a sequence of events.

Findings:

- Blank visits and blank incidents become durable noise in the Timeline. P1/P2, AUD-004.
- Timeline rows are read-only. That is acceptable as a history surface only if source records are consistently editable or navigable, which is not true for visits and vitals.
- The filter and entry iconography need a usability pass under Dynamic Type and VoiceOver; this audit did not complete that matrix.

### Family frames

#### 41. Family, local-only state

Runtime. The screen says everything entered is on this phone, then offers Sign in to back it up and share it with family. The footer repeats that the list works with no account and no signal.

Positive: this is one of the clearest offline/account explanations in the app.

Finding: it still leaves the relationship between local data, later sign-in, account recovery, and sign-out under-explained. P2, AUD-028.

#### 42. Family, sign-in state

Runtime. “Create your family” repeats the sharing explanation and shows Sign in with Apple. The app tab shell remains visible.

Finding: stale product naming appears in the linked legal and purchase surfaces reached from the same account journey. P1, AUD-010.

#### 43. Family, signed-in group state

Source. Members, roles, invites, subject transparency, rename, leave, delete, and sign-out are represented.

Findings:

- Runtime coverage is missing for invitation acceptance, role changes from two accounts, removal, group deletion, and offline cache behavior.
- The group owner deletion path uses a confirmation dialog, while the leave-group path uses a typed phrase. The difference may be intentional, but both actions remove shared state and should communicate the scope consistently. P2, AUD-031.

#### 44. Invite and join sheets

Source. The invite flow distinguishes caregiver and subject, produces an eight-character subject code with a stated expiry/one-use rule, and provides share text. Join normalizes code input and reports errors.

Positive: the invite copy addresses the important privacy distinction between a caregiver and a subject.

Open work: exercise copied code, expired code, re-use, wrong group, offline send, and a subject account that is already linked.

### Settings, legal, and billing frames

#### 45. Settings, top frame

Runtime. The top offers Upgrade to Pro, with copy about tracking everyone, visit history, and export. The footer says one person in the family pays and the group is covered.

Positive: the one-payer group rule is stated, which avoids charging each sibling.

Finding: the Pro card and all plan labels use Med List branding, not Elderhub. P1, AUD-010.

#### 46. Settings, account/privacy frame

Runtime/source. Signed-out users see that everything stays on the phone. Privacy copy says no location, ads, or tracking. Privacy policy, Terms, Support, Restore purchases, and disclaimer content are available.

Findings:

- The privacy policy link opened a live page titled “Med List Privacy Policy” with Med List branding and icon, despite the current app being Elderhub. P1 trust and review risk, AUD-010.
- Restore-purchase errors are swallowed with `try?`, so a failed restore can look like a no-op. P2, AUD-021.
- Support and lower settings content can be partially obscured by the persistent tab bar until the user scrolls. P2, AUD-019.

#### 47. Settings, medical disclaimer

Runtime. The disclaimer says the app is not a medical device, gives no medical advice, cannot tell whether anyone is unwell, and does not call for help.

Positive: this is clear, consistent with the product boundary, and should remain in both Settings and emergency contexts.

#### 48. Paywall

Runtime. The sheet offers unlimited people, full visit history and doctor notes, export/share, and vitals history over time. It offers monthly, yearly, and lifetime plans, plus restore and legal text.

Findings:

- Visible product labels say “Med List Pro Monthly,” “Med List Pro Yearly,” and “Med List Pro Lifetime.” This is a direct rename leak. P1, AUD-010.
- The benefit “doctor notes” can be read as clinical documentation even though the product stores unstructured Notes. It also does not explain the privacy implications of family-visible notes. P2, AUD-011.
- No actual purchase was made in the simulator. Store configuration is correctly guarded for simulator use, and no production RevenueCat customer was created.

#### 49. External privacy page

Runtime. The link opened Safari to a Med List-branded privacy page at the old `/medlist/` path.

Finding: this is not merely a cosmetic old word. A user checking privacy before sharing medical and household data sees a different product identity. It can undermine consent and trigger app-review or support confusion. P1, AUD-010.

### Check-in frames

#### 50. Check-in settings, disabled

Runtime. The screen shows Daily check-in off and explains the agreed window, reminder behavior, and that nobody is called or sent to help.

Positive: the text sets a safe, non-emergency expectation.

#### 51. Notification permission prompt

Runtime. Enabling the toggle raised the standard iOS notification permission prompt. Allow was exercised.

Finding: denial was not fully exercised. Source review shows that the feature can remain enabled without a visible local-permission status after authorization fails or is denied. P1/P2, AUD-015.

#### 52. Check-in settings, enabled

Runtime. The enabled state shows From 8:00 AM, Until 8:00 PM, Wait a bit longer 1 hour, last-check-in state, and a caregiver button to record a check-in for the person.

Findings:

- There is no Save button. Settings are persisted on disappearance, while notification work is triggered through changes. A user has no explicit confirmation that the new window or toggle is saved. P2, AUD-016.
- The caregiver record button becomes disabled after the daily record. There is no correction path. P2, AUD-016.
- The screen does not show whether the local reminder is scheduled, denied, or awaiting remote registration. P1/P2, AUD-015.

#### 53. Subject check-in home

Source. The subject gets a large “I’m OK today” button, last check-in, who-can-see-me control, own dose list, and offline status.

Positive: this is an appropriately narrow subject experience and avoids emergency claims.

Open work: runtime exercise with a real linked subject and remote group is required.

## Cross-cutting findings register

### AUD-001: medication records cannot be edited

Severity: P1

Evidence: Runtime and source. Medication rows have delete behavior but no tap/edit route. `MedicationEditorSheet` is always in Add Medication mode.

Impact: Medication name, strength, form, times, refill data, purpose, prescriber, and instructions cannot be corrected in place. The only apparent path is delete and recreate, which is dangerous for a medication list, breaks history continuity, and is especially poor offline.

Expected outcome: every saved medication should have an obvious, reliable correction path that preserves identity and history when appropriate.

### AUD-002: visit records cannot be edited

Severity: P1

Evidence: Runtime and source. Visit rows are rendered as `VisitRow` without a Button or sheet item action. Swipe delete is available.

Impact: a wrong provider, date, reason, note, or follow-up cannot be corrected. Visit history is often entered after an appointment when memory is imperfect.

Expected outcome: a saved visit should reopen its existing fields for correction.

### AUD-003: vital readings cannot be edited

Severity: P1/P2

Evidence: Runtime and source. Existing readings are list rows with delete only. Tapping a reading produced no edit state.

Impact: a transposed blood-pressure or weight value must be deleted and recreated, weakening confidence in a longitudinal record and creating avoidable tombstones.

Expected outcome: readings should support correction with clear original-time semantics.

### AUD-004: blank visits and blank events are accepted

Severity: P1/P2

Evidence: Runtime and source. Save remained available on an empty Visit sheet and empty incident/event sheet. A blank Visit and blank Symptom were saved during the audit and appeared in lists and Timeline.

Impact: meaningless records pollute history and can be mistaken for real events. A Timeline entry titled only “Visit” is especially hard to interpret later.

Expected outcome: minimum meaningful content must be required, or an explicit draft state must be visible and recoverable.

### AUD-005: duplicate medication schedule times create duplicate dose slots

Severity: P1/P2

Evidence: Runtime. Saving the same medication with 8:00 AM twice produced two doses for the day.

Impact: caregivers can accidentally double-count a dose, see an alarming 0/2 state, or misinterpret the list as two administrations.

Expected outcome: duplicate slots should be rejected, merged, or explained before saving.

### AUD-006: medication identity fields are too optional for emergency use

Severity: P1

Evidence: Runtime/source. Save requires only a name; strength, form, purpose, schedule, and instructions can be blank.

Impact: an emergency card or Today row can contain an ambiguous medication such as a name without strength or administration context.

Expected outcome: the app must distinguish a minimal reminder-only medication from a clinically useful record and make incompleteness obvious.

### AUD-007: Emergency Card omission looks like a negative fact

Severity: P1

Evidence: Runtime/source. Empty sections are not rendered unless the whole card is empty.

Impact: “no allergy section” can be interpreted as no allergies, and “no contact section” can be interpreted as no one to call. This is unsafe ambiguity for a card explicitly described as something handed to a paramedic.

Expected outcome: absent critical fields need visible Unknown, Not recorded, or equivalent status, with a clear completeness signal.

### AUD-008: emergency contacts are not callable

Severity: P1/P2

Evidence: Runtime/source. Provider phones use links; emergency-contact phone text is not a telephone link. Contact phone is not required.

Impact: the user most likely to be called first is the least actionable. A primary contact can also have no usable number.

Expected outcome: primary contacts must have a visible, tested call action and a clear missing-number state.

### AUD-009: Emergency Card and export diverge

Severity: P2

Evidence: Source review. `MedListExporter` includes identity, blood type, allergies, conditions, medications, contacts, and disclaimer, but not the provider section displayed on the card. There is no export preview.

Impact: a user may share what they believe is the same card and omit provider information visible in the app. The recipient cannot tell whether missing information was not recorded or not exported.

Expected outcome: the share artifact should have a declared scope and match the visible emergency surface or clearly say what it excludes.

### AUD-010: Med List branding remains after the Elderhub rename

Severity: P1

Evidence: Runtime/source. Settings and paywall show Med List plan labels. The privacy link opened a Med List-branded page at the old path.

Impact: users may believe they installed the wrong app, question whether their privacy policy applies, or encounter app-review and support confusion. This is particularly damaging when asking for medical and family data or payment.

Expected outcome: every user-visible billing, legal, support, icon, URL, and plan string must use the current product identity or explicitly explain the legal entity.

### AUD-011: Notes normalize secret storage in a shared plaintext field

Severity: P1

Evidence: Runtime/source. The seeded note contains a gate code. Project architecture says CareNote is not a password vault. The Notes experience is plaintext, family-visible, searchable, and has no sensitive-data warning. Provider copy explicitly warns against storing credentials, but Notes do not.

Impact: users are taught to store access codes and may reasonably store passwords, insurance numbers, or other secrets. The information can be exposed to every group member and in search results.

Expected outcome: the product boundary must be visible at the point of entry and sample content must not encourage secrets.

### AUD-012: global search results are dead ends

Severity: P1/P2

Evidence: Source. Search covers many record types, but `SearchHitRow` is not interactive.

Impact: a user can find a note or medication but cannot open the record, which turns a promising global search into an index with no action.

Expected outcome: each result should open the correct person and record, or the UI should not present the row as a navigable lookup result.

### AUD-013: deleting a person has too little friction and recovery

Severity: P1

Evidence: Source. People rows use swipe deletion and cascade recipient data/tombstones without a visible confirmation or undo in the list.

Impact: a single accidental swipe can remove the identity around a large set of medications, visits, notes, and history. In a shared group, the scope of local and remote effect is difficult to infer.

Expected outcome: destructive recipient removal must show scope, require deliberate confirmation, and provide a safe recovery model.

### AUD-014: daily check-in is buried and absent from Today actions

Severity: P1

Evidence: Runtime/source. Check-in is a hub tile and setup row, but `QuickAction.todayRow` excludes it. The Medical menu also excludes it.

Impact: the feature is easy to discover once, then hard to find every day. A missed check-in workflow is time-sensitive, so burying the action conflicts with the promise.

Expected outcome: the daily check-in status and action should be reachable from the primary daily context for the relevant person.

### AUD-015: notification denial is not surfaced as a broken check-in setup

Severity: P1/P2

Evidence: Runtime/source. Enabling triggers notification permission. Source handles a remote registration warning but does not clearly expose local notification denial as an enabled-but-unreliable state.

Impact: a caregiver can believe reminders are active while iOS will not deliver them. The product promise is not merely a setting; it depends on a permission and delivery chain.

Expected outcome: the enabled state must distinguish scheduled, permission denied, and delivery unavailable, with a clear route to recover.

### AUD-016: check-in settings and manual records lack confirmation/recovery

Severity: P2

Evidence: Runtime/source. There is no Save button; settings save on disappearance. A manual daily record disables after use and has no undo.

Impact: users lack confirmation that changes persisted and cannot correct a mistaken caregiver or subject action.

Expected outcome: the state transition should be explicit and reversible within the reasonable correction window.

### AUD-017: family dose attribution says “You”

Severity: P1

Evidence: Source. `TodayView.record` creates dose logs with `recordedBy: "You"`.

Impact: shared records cannot reliably answer who marked a dose. This reduces accountability and can create family disagreements about whether a medicine was actually administered.

Expected outcome: the stored and displayed author should be the current family member identity, with a stable fallback for local-only users.

### AUD-018: dose correction is hidden and semantically confusing

Severity: P2

Evidence: Runtime/source. Taken is a direct button; the available swipe action is Skip. There is no visible undo or “not taken” state.

Impact: users may avoid correcting a mistake or interpret Skip as a future schedule action rather than correcting a past log.

Expected outcome: the correction path should be discoverable and use language that matches the state being corrected.

### AUD-019: tab bar covers lower content on pushed screens

Severity: P2

Evidence: Runtime. Person hub, Emergency Card, Settings, and detail lists showed lower content crowded or partly behind the persistent tabs.

Impact: users can miss Add actions, disclaimer text, Support, or final list rows. This is a repeated frame-level issue rather than a single screen defect.

Expected outcome: scroll content and bottom actions should remain fully visible above the tab bar in every pushed destination and accessibility size.

### AUD-020: vital units are fixed to US customary values

Severity: P2

Evidence: Source. Weight is lb, glucose mg/dL, temperature degrees F, and other labels are fixed.

Impact: non-US users have to convert readings and can enter values under an unexpected unit.

Expected outcome: unit presentation and input should follow locale or an explicit user preference.

### AUD-021: restore-purchase failures provide no feedback

Severity: P2

Evidence: Source. Settings and paywall use `try?` for restore.

Impact: a user who has paid but cannot restore sees no success, failure, or next step. This creates support cases and erodes billing trust.

Expected outcome: restore should visibly report success, no entitlement found, network failure, and retry state.

### AUD-022: family transparency may omit shared feature categories

Severity: P1

Evidence: Source. Transparency names several health categories but not Notes, Tasks, or Providers. Notes visibly say they sync with the family record.

Impact: consent is incomplete if the person being looked after cannot see the full set of information accessible to group members.

Expected outcome: the transparency list should be generated from the actual group-visible feature set and stay synchronized as features are added.

### AUD-023: provider phone rule is not enforced at entry

Severity: P2

Evidence: Runtime/source. Provider editor requires only a name. Providers without phone numbers are excluded from Emergency Card by design.

Impact: users can believe they added a provider for emergency use, then find it missing from the card.

Expected outcome: the editor should show the consequence immediately and distinguish a records-only provider from an emergency-card provider.

### AUD-024: allergy and condition placeholders resemble existing values

Severity: P2

Evidence: Runtime/source. Populated details editor showed “Penicillin” and “Type 2 diabetes” as input placeholders alongside existing entries.

Impact: a caregiver can think the field is prefilled, re-add a value, or fail to understand whether the existing row or the input is authoritative.

Expected outcome: examples should not look like current data, and current data should have a distinct edit/delete treatment.

### AUD-025: Pro copy implies a richer vitals history than the visible screen

Severity: P2

Evidence: Runtime/source. Paywall says “Vitals history over time”; Vitals is a chronological list without trend visualization.

Impact: users may purchase expecting trend analysis and find only list history. Even if the wording is technically defensible, the expectation is underspecified.

Expected outcome: benefit copy should match the actual level of analysis shown.

### AUD-026: empty Today medication CTA requires a second navigation step

Severity: P2

Evidence: Runtime. “Add a medication” from Today opens the full person hub, then requires another Add Medication tap.

Impact: the most obvious first-run action does not complete the promised task and makes the app feel indirect.

Expected outcome: the CTA should land at the medication entry point or clearly say it opens the person's record.

### AUD-027: subject sign-in has a one-way, all-or-nothing feel

Severity: P2

Evidence: Runtime/source. Subject flow offers Sign in with Apple and no Not now. Back resets to the role path.

Impact: a subject without an Apple account, device access, or willingness to sign in can feel trapped or may abandon without understanding what the family needs to do.

Expected outcome: the state should explain the prerequisite and provide a graceful recovery or support route.

### AUD-028: account, backup, sharing, and recovery boundaries are not fully explicit

Severity: P2

Evidence: Runtime/source. Local-only copy says sign-in backs up and shares, but the sign-in frame mainly says family members can see the list. Sign-out and data migration were not runtime-tested.

Impact: users may not know whether local data is merged, uploaded, preserved, or recoverable when they later authenticate.

Expected outcome: account screens should state local persistence, backup scope, sharing scope, sign-out behavior, and device-change behavior in plain language.

### AUD-029: stale terminology across feature surfaces

Severity: P3

Evidence: Runtime/source. “Meds,” “medications,” “Doctors,” “Providers,” “Symptoms,” “Incidents & Symptoms,” “History,” and “Timeline” refer to overlapping areas.

Impact: repeated terminology changes increase learning cost and make search/quick-action coverage harder to predict.

Expected outcome: each concept should have one primary user-facing name, with a deliberate exception only where audience language warrants it.

### AUD-030: setup card can be hidden without an obvious restore

Severity: P2

Evidence: Runtime/source. The setup card has Hide and no visible show-again action in the hub review.

Impact: a user who hides setup before completing the record loses the most useful guided path.

Expected outcome: hidden setup should be recoverable from the hub or settings.

### AUD-031: destructive group paths communicate scope inconsistently

Severity: P2

Evidence: Source. Leave uses a typed phrase in `LeaveGroupSheet`; owner delete uses a normal confirmation dialog.

Impact: users cannot easily infer whether a path removes only membership, shared group state, or local records. The difference in friction can make the more destructive path look routine.

Expected outcome: leave and delete should use consistent scope language and deliberate confirmation proportional to impact.

### AUD-032: remote group and subject paths need a real two-account pass

Severity: P1 before relying on family sharing

Evidence: Source only for RPC, roles, invites, transparency, sync conflict behavior, and subject routing.

Impact: the product's central sharing promise is not proven by local UI alone. A stale role cache, invite edge case, or sync conflict can affect privacy or medication status.

Expected outcome: two-device acceptance testing should cover every mutation and an offline/reconnect sequence for each synced entity.

### AUD-033: accessibility and alternate-layout coverage is incomplete

Severity: P1/P2 release coverage gap

Evidence: audit run was normal text size, light mode, portrait on iPhone 17 Pro. Dynamic Type, VoiceOver, landscape, iPad, and dark mode were not completed.

Impact: the product targets older adults and caregivers under stress. A clean normal-size run does not establish readability, focus order, hit targets, or bottom-bar safety for those users.

Expected outcome: the same frame inventory should be repeated at accessibility sizes, with VoiceOver, dark mode, landscape, and the supported device matrix.

### AUD-034: feature naming is inconsistent across navigation surfaces

Severity: P3

Evidence: Runtime/source. The catalog calls the feature Symptoms, the screen calls it Incidents & Symptoms, the action says Log a symptom, and the Medical menu calls the provider area Doctors while the hub calls it Providers.

Impact: a new user may not know that these are the same destinations, and a support agent cannot refer to one stable label.

Expected outcome: use one label per destination and reserve alternate wording for explanatory copy.

### AUD-035: emergency access is not prominent in the daily context

Severity: P2

Evidence: Runtime/source. Emergency Card is a lower Today link and a person-hub banner, while Today is dominated by quick actions, doses, and tasks.

Impact: in a real urgent moment, the user may need to scroll or navigate through the person context before reaching the card.

Expected outcome: the emergency route should remain immediately visible without confusing it with an emergency detection or alert feature.

### AUD-036: emergency contact deletion lacks recovery

Severity: P2

Evidence: Runtime/source. Emergency contacts can be deleted by swipe without a visible confirmation.

Impact: an accidental deletion can remove the only visible route to a family member in the emergency surface.

Expected outcome: deletion should state what disappears from the card and offer a safe recovery or deliberate confirmation.

### AUD-037: no-date tasks can become invisible to the daily user

Severity: P2

Evidence: Runtime/source. Tasks without due dates are grouped under No date and do not appear as Today work.

Impact: a task entered as “no date” can effectively be forgotten. The editor does not state this consequence near the no-date choice.

Expected outcome: no-date tasks should have a clear persistent affordance or stronger wording about their visibility.

### AUD-038: symptom severity scale has no shared meaning

Severity: P2

Evidence: Runtime/source. Severity uses a 0 to 10 stepper and “Severity not set,” with no anchors.

Impact: the same number can mean different things to different caregivers, reducing the value of a longitudinal symptom record.

Expected outcome: the scale should state what its endpoints mean and remain framed as a record, not a diagnosis.

## Positive patterns to preserve

These are important strengths that a fixing pass should not accidentally remove:

- Offline-first rendering from SwiftData is reflected in the visible copy and is structurally present in the services.
- The app does not claim to diagnose, treat, detect emergencies, or summon help. The disclaimer and check-in copy consistently maintain that boundary.
- Check-in has no billing dependency, which protects the reliability of the safety-adjacent path.
- The `CareFeature` catalog and shared hub components give the app a consistent discoverability architecture.
- The Today row was reduced to a usable number of actions, with Medical as a deliberate grouping rather than a horizontal overflow.
- Task recurrence and task completion conflict rules are thoughtfully modeled. Completion by siblings is treated as agreement, while genuine text edits can conflict.
- Provider editor copy explicitly says no username or password is stored. This is the right security boundary and is a useful pattern for Notes.
- The family invite flow distinguishes caregiver access from subject access and explains the difference before generating a code.
- The Emergency Card disclaimer appears in the places users need to see it.
- Medication scheduling uses minutes from midnight and weekday numbering rather than storing a fragile Date value, which is a good data-model decision for time-zone changes.
- The local-only path does not force an account, and the free-tier rule does not charge every sibling separately.

## Second-pass re-analysis

This section is the required independent re-check after the initial issue collection.

### Coverage reconciliation

The source inventory was compared against the feature catalog and navigation routes. The following user-facing capabilities are represented in the audit:

| Capability | Hub/catalog | Today route | Dedicated frame | Runtime | Source | Main risk |
| --- | --- | --- | --- | --- | --- | --- |
| Medications and dose logging | Yes | Meds | Medication editor, Today doses | Yes | Yes | No edit, weak required fields, duplicate times, attribution |
| Tasks | Yes | Tasks | Tasks list/editor | Yes | Yes | No-date visibility, hidden correction/deletion |
| Visits | Yes | Visits | Visits list/editor | Yes | Yes | No edit, blank save |
| Vitals | Yes | Medical | Vitals list/editor | Yes | Yes | No edit, fixed units, list-only expectation |
| Symptoms/incidents | Yes | Medical | Events list/editor | Yes | Yes | Blank save, ambiguous severity |
| Providers/doctors | Yes | Medical | Provider list/editor/picker | Yes | Yes | Phone/card consequence, terminology |
| Health details | Yes | Medical | Details editor | Yes | Yes | Placeholder confusion, incomplete card semantics |
| Emergency contacts | Yes | Contacts | Contact list/editor | Yes | Yes | Non-callable numbers, no phone requirement |
| Notes | Yes | Notes | Notes list/editor | Yes | Yes | Secret normalization and disclosure gap |
| Timeline/history | Yes | Medical | Timeline/filter | Yes | Yes | Blank noise, read-only dependency |
| Daily check-in | Yes | None | Settings and subject home | Partial | Yes | Buried, notification state, no correction |
| Emergency Card | Banner | Footer | Card/edit/share | Yes | Yes | Omission and export mismatch |
| People and global search | Person rows | None | People/search | Yes/list, search source | Yes | Search dead ends, destructive delete |
| Family sharing | Family | None | Family/invite/join/transparency | Local/sign-in only | Yes | Two-account behavior unproven, disclosure gaps |
| Settings/legal | Settings | None | Settings/paywall/external legal | Yes | Yes | Stale branding, silent restore |

This reconciliation found no major catalog feature that was entirely absent from the audit. It also confirmed the structural product issue: a feature can appear in the hub and still be practically undiscoverable in the daily workflow. Check-in is the clearest example.

### Severity re-check

I re-read the issue register looking for duplicate findings and for claims that were only inferred from automation. The following were retained because they are supported by both UI/source evidence or by direct runtime behavior:

- Record correction failures for medication, visit, and vital records.
- Blank record creation for visits and events.
- Missing emergency-card sections and non-callable contacts.
- Stale Med List branding in plan labels and the live privacy page.
- Notes sample and copy encouraging sensitive plaintext storage.
- Non-interactive search result rows.
- Check-in omission from Today and unclear local notification denial state.
- Duplicate schedule slots and dose author “You.”
- Bottom content crowding by the persistent tab bar.

The following were downgraded or marked as open coverage rather than asserted defects:

- Subject Home runtime behavior, group membership, sync, RPC errors, and real remote notifications are not called broken. They are unverified.
- The Vitals paywall wording is recorded as an expectation gap, not a claim that a chart is contractually promised.
- Automation-only navigation oddities were not turned into findings because stale simulator accessibility references were observed.
- The unused medication label-photo field is recorded as an unexposed capability, not a defect.

### Final priority order for a fixing agent

If the next agent needs a short order of operations, the audit evidence supports this sequence:

1. Establish reliable correction and validation for medication, visit, vital, and event records.
2. Make Emergency Card completeness and contact actions safe and explicit, then align export scope.
3. Make check-in durable, visible, permission-aware, and recoverable.
4. Remove all old Med List branding and verify every external legal/support surface.
5. Resolve the Notes privacy boundary and regenerate sample content that does not teach secret storage.
6. Make search results actionable and make person deletion deliberate and recoverable.
7. Fix cross-screen layout, units, terminology, settings feedback, and accessibility coverage.
8. Run the two-account and offline/reconnect matrix before treating family sharing as proven.

## Final verification

- `audit86.md` is the only file created for this audit.
- No Swift, project, configuration, asset, database migration, or test file was changed.
- The app was built and launched on the leased headless simulator. No Simulator.app window was opened.
- The Xcode test runner was started against the same headless simulator but did not complete after more than three minutes. It was stopped after the runner remained active without result output. This is recorded as a test-run timeout, not as a passing test result.
- Simulator data changes were confined to the disposable simulator store and were not treated as product fixes.
- The audit was re-analyzed against the view/service inventory and feature catalog before completion.
- The remaining gaps are explicitly labeled as unverified rather than silently assumed to work.
