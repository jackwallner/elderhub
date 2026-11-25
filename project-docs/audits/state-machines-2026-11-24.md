# State machine audit, 2026-11-24

Scope: the Elderhub iOS app (`Aging` target, `Shared/`). There is no widget, Watch, App Intents or notification-extension target, so the only scheduled state outside the process is local notifications. Android, the Supabase functions and the database are out of scope. Audited from committed code at `2735f52`. No app code was changed for this phase.

**Summary: 1 bug proved by a failing test, 6 code-path claims (not proved).** Plus 7 product calls (not counted).

Evidence run: `gh-sim test --scheme Aging --only AgingTests/StateMachineAuditRepro` on `2735f52` with the repro suite copied into `AgingTests/`. Run `eh-repro-mbpro9d36-1124-220907-3608`, GitHub run `45558492028` (Xcode 27.1, iPhone 17, iOS 27.2): 2 tests, 1 passed (the control), 1 failed (the claim). The repro suite is `state-machines-2026-11-24-repro.swift` beside this file; it is not in the test target. No build settings or secrets are needed for the unit tests.

Seams that exist: `RefillReminderPlanner.requests(for:on:calendar:)`, `AppointmentReminderPlanner`, `OneShotReminderDiff`, `TodayDigest.build`, `ReviewPrompt` statics, in-memory `CareModelStore.makeInMemoryContainer()`. Seams that do not: an injectable `UNUserNotificationCenter` (every `apply*` reads `.current()`), a constructible RevenueCat `CustomerInfo`, and any way to drive a view's `@State` headless. That is why the notification-call, entitlement and paywall claims stay code path.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Population and frequency | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| M1 | A refill reminder planned after 9:00 on the day the supply reaches its threshold is handed to iOS for 9:00 that morning | No "Refill soon" push at all for that medication, ever, unless the app happens to be opened before 9:00 on a day the supply is at or under its threshold | `MedicationEditorSheet.swift:138` "Warn at N days left"; `DoseReminderScheduler.swift:410-411` "One local, non-repeating notification per tracked medication, firing on the day it is expected to cross its refill threshold" | Reminders on for Mom. A tracked tablet, 1 a day, warn at 7 days, 8 on hand. At 8pm tick the evening dose taken on Today (on hand 7). The app refreshes reminders on the next foreground (`RootView.swift:110`) or any medication save (`MedicationEditorSheet.swift:318`); the plan is `dayOffset 0` at 09:00 today, already past. Same for a count typed in at lunch that is already low. | Every caregiver tracking refills whose refreshes on the crossing day happen after 9:00 (evening doses, twice-daily meds, anyone who opens the app after breakfast). Once per refill cycle per medication. Cost: the one push that is the point of refill tracking does not arrive. | Test `m1RefillReminderPlannedAfterNineIsStillInTheFuture` asserts preconditions (`daysRemaining == 7`, threshold 7, one spec) then that the fire date is after now. Control `m1ControlRefillReminderPlannedBeforeNineFiresAtNine` (7:00, expects 09:00 today). Run `45558492028`: the claim failed with `fire.map { $0 > now } → false: refill reminder handed to iOS for 2026-11-24 14:00 UTC (09:00 New York), before now 2026-11-25 01:05 UTC (20:05 New York)`; the control passed. | `DoseReminderScheduler.swift:578-583` (no "is it in the future" check; `AppointmentReminderPlanner` has one) |
| M2 | Deleting an appointment leaves its evening-before reminder pending | "Mom: Dr. Patel tomorrow at 9:30 AM" at 6pm for an appointment that was deleted | `.claude/rules/reminders.md`: "A refill or appointment reminder is rewritten when what it says or when it fires changes"; the save path refreshes (`VisitsView.swift:318`) | Mom's hub, Appointments, swipe tomorrow's appointment, Delete, lock the phone. Nothing refreshes until the next foreground. | Anyone who cancels an appointment and does not reopen the app before 6pm the evening before. Occasional. | Code path only. `plan(in:)` already drops a tombstoned visit, so the missing step is the call, which no headless test can observe without a notification-center seam. | `VisitsView.swift:128-130` |
| M3 | Leaving or deleting the circle, being removed from it, or having access narrowed leaves that person's repeating dose reminders pending | "Dad: Warfarin" keeps arriving on this lock screen after the phone has given up Dad's record, until the app next comes to the foreground | `SettingsView.swift:54-66` (sign-out drops pending requests "so no request keeps naming a person this phone can no longer show"); `GroupService.applySelfAccess` doc: losing access purges what the phone holds | Sharing, Leave (or Family, Delete group); or the organizer narrows this member's access and `loadMembers` runs on the Sharing screen. `forgetGroupLocally` / `applySelfAccess` hard-delete the people but never touch notifications. | Rare (leaving a circle, narrowed access), but it shows medication names after consent was withdrawn. | Code path only, same missing seam as M2. | `GroupService.swift:735,741,791-814` (`forgetGroupLocally`, also called on removal at `:331`), `:765-789` (`applySelfAccess`) |
| M4 | An Ask to Buy approved later, or a purchase made on another device, does not unlock this phone until relaunch or the next paywall open | A parent approves; the app keeps showing the paywall and "Upgrade" in Settings | The pending copy this run adds ("Your purchase unlocks once it is approved"); `StoreService` doc "Plus unlocks additional people" | Paywall, Start trial, Ask to Buy, approved later while the app stays in memory. `StoreService` sets no `PurchasesDelegate` and the foreground path (`RootView.swift:102-111`) never calls `store.refresh()`. | Family-shared Apple IDs. Partly masked for signed-in circles: the webhook credits the circle and `groups.refresh()` on foreground pulls `hasPlus`. Not masked for a purchase without an account. | Code path only (no `CustomerInfo` fixture). Fixed under Rollout A. | `StoreService.swift` `configureIfNeeded` (no delegate) |
| M5 | After any purchase error the message replaces Apple's required disclosure for the rest of the sheet's life | Pick a different plan after an error: the button and price change, the disclosure for that plan never appears | `PaywallView.swift:98-99` "Apple's required disclosure, rebuilt for the selected plan so the billed amount, the period and the trial always match the row above" | Paywall offline, Continue (network error), then tap Monthly. `errorMessage` is never cleared, and it takes the disclosure's slot (`PaywallView.swift:266-276`). | Anyone who hits a purchase error and keeps the sheet open. Ask to Buy hit it every time (its pending error was shown here). | Code path only (view `@State`). | `PaywallView.swift:266-276, 456-467` |
| M6 | The rating ask can land after the reader left Today | Mark the last dose taken, switch to the Care tab within 3 seconds: Apple's prompt appears over Care | `.claude/rules/paywall-and-review.md`: the ask comes "only if nothing is presented" on Today; `ReviewPrompt.swift:7-8` | Today, tick the last item, tap Care. `isTodayClear` only checks modal presentation and app state, not that Today is on screen. | Low; the 3-second window. | Code path only. Fixed under Rollout S. | `TodayView.swift:986-992` |
| M7 | The check-in reminder fires after the person has already checked in | Mom presses I'm OK at 9am; at the window midpoint "Tap to check in for today" still arrives | `CheckInService.swift:179` "the notification is a nudge to press the button"; its body `:241` "Tap to check in for today." | Recipient phone, press I'm OK before the window midpoint. `scheduleReminder` uses one repeating daily trigger that a press never touches. | Every recipient who checks in before the midpoint, every day. Trust cost on the screen that matters most, not a missed alert. | Code path only (no notification-center seam). Held for Jack: the fix trades the reliability of a repeating trigger for per-day one-shots. | `CheckInService.swift:224-247` (`repeats: true`, never touched by `press`) |

## Product calls (not counted)

1. **Permission revoked later.** Turning Notifications off for Elderhub in iOS Settings leaves `DoseReminderPreferences` on; the foreground refresh clears the requests (`DoseReminderScheduler.apply` returns early unauthorized), Today's setup checklist still counts reminders as done, and only opening that person's hub reconciles the toggle (`PersonDetailView.swift:205-212`). The rules forbid clearing a stored setting on an inferred state, so the right shape (a "Reminders are off in iOS Settings" line where the toggle state is shown) is a product call.
2. **Today across midnight.** `TodayView` builds its digest from `Date()` in `body` with no day-change observer; whether a foreground re-renders it depends on whether sync mutates something Today observes. Not proved either way.
3. **A handed-over phone still gets dose reminders.** In recipient mode every enabled person's dose and appointment reminders still fire, and a tapped one leaves `NotificationRoute.pendingPersonID` set until the caregiver comes back, when Today jumps to that person.
4. **Check-in reminder time zone.** The reminder uses the device zone; the server judges the window in `check_in_settings.timezone`, the zone of whoever saved it last (already listed as a known gap in the sync rules).
5. **A refill reminder repeats while the supply stays under its threshold** if the app is opened before 9:00 that day (`dayOffset` is floored at 0). Pre-existing, and arguably what "Refill soon" should do until a new count is entered.
6. **`isPro` is not persisted.** A payer launching offline depends on RevenueCat's cached customer info; the circle's `hasPlus` is cached in `CareGroup`, so family members are covered.
7. **`errorMessage` text is RevenueCat's English description** for errors other than network and pending. English-only app today, so no translation gap yet.

## State machines

### SM1. Entitlement and purchase (`StoreService`)

State: `isConfigured`, `isPro`, `offerings`, `plans`, `isLoading`, `hasAttemptedLoad`, `loadFailure`, `introEligibility`, `introEligibilityResolved`, `localOverride`.

Invariants: E1 `isPro` equals the active `Aging+` (or fallback) entitlement after every `apply`; E2 no trial wording before eligibility resolves; E3 RevenueCat is never configured with the production key on a simulator; E4 the RevenueCat identity follows the Supabase user (`identify`, `forgetCustomer`).

| From | Event | To | Note |
|---|---|---|---|
| unconfigured | `start()` on device | configured, `identify`, `refresh` | E3: simulator stays unconfigured |
| free | purchase ok | pro, conversion recorded, billing pulled | |
| free | purchase cancelled | free | not an error |
| free | `paymentPendingError` | free, red error | M4/M5; Rollout A makes it a pending notice |
| free (pending) | approval while running | free until relaunch or paywall open | M4 |
| any | sign-out / delete account | `logOut`, anonymous | E4 |

### SM2. Paywall sheet (`PaywallView`)

State: `isPurchasing`, `isRestoring`, `errorMessage`, `restoreResult`, `selectedPlanID`; store's three load states. Invariants: P1 the disclosure matches the selected plan; P2 the button is never left spinning; P3 Restore is reachable in every state. P1 broken by M5. No pending unlock action exists (both presenters, `PeopleView` and `SettingsView`, just set `showPaywall`), so the C1 stale-flag pattern from the baseball audit cannot occur here.

### SM3. Dose reminders (per person, per device)

Preference (`DoseReminderPreferences`, off/on) x iOS authorization x pending `dose-<person>-<minute>-<weekday>` requests. Invariant: pending equals `plan(in:)` when authorized and enabled, nothing when not; the 63-request budget is shared with refills and appointments. Reconciled on launch, foreground, medication save/delete, visit save, person remove and toggle change. Missing: visit delete (M2), circle leave/delete/narrowed access (M3).

### SM4. Refill and appointment reminders (one-shot)

Identifier is the medication's or visit's id; `OneShotReminderDiff` compares body and year-to-minute. Appointment fires 18:00 the evening before and must be in the future (guarded). Refill fires 09:00 on `max(0, floor(daysUntilThreshold))` days out with no future guard (M1).

### SM5. Reminder permission toggle (`NotificationPermission`)

`request()` returns granted / blocked (denied, no prompt) / denied. Non-granted puts the preference back. Pref-versus-status reconciled only in `PersonDetailView.onAppear` (product call 1).

### SM6. Check-in (`CheckInService`, `CheckInHomeView`)

One repeating request `aging.checkin.reminder` at the window midpoint, armed from `CheckInHomeView` via `.task(id: reminderKey)` (person, enabled, window, scenePhase), removed when settings are off or the caregiver phone does not hold its own record. A press never touches it (M7). No billing check at any depth (I2), verified: `CheckInService` does not import `StoreService`.

### SM7. Notification route (`NotificationRoute`)

Tap sets `pendingPersonID`; `RootView` switches to Today; Today consumes it on change or appear and drops an unknown id. Never consumed in recipient mode (product call 3).

### SM8. Review ask (`ReviewPrompt`, `TodayView`)

`appLaunchCount`, `lastShownDate`, `outcome`, `hasPendingPositiveMoment`. Invariants: R1 not before the 2nd launch; R2 30 days between calls, stamped when called; R3 opening the review page ends the asks, feedback never does; R4 a blocked ask stays pending; R5 only on Today, only with nothing outstanding for anyone. R5 weakened by M6. Covered by `ReviewPromptTests`.

### SM9. Handset mode (`DeviceModeService`)

caregiver / recipient, PIN hash and salt, `handedOverPersonID`. Invariants: handing over never needs the PIN, coming back does when one is set, coming back clears the handed-over person, clearing the PIN returns to caregiver. No invalid transition found.

### SM10. Circle membership and local wipe (`GroupService`)

`activeGroupID`, cached `CareGroup` (role, `hasPlus`), `selfVisibleRecipientIDs`. `forgetGroupLocally` and `applySelfAccess` hard-delete with `context.delete` by design (I5); neither re-plans notifications (M3).

## Phase 2, skeptical review

Re-read each claim as an outside reviewer:

- **M1 survives.** The route is the ordinary evening dose on Today followed by any refresh. A `UNCalendarNotificationTrigger` built from full year-to-minute components in the past has no next trigger date and never delivers. The test drives the real planner with a fixed clock and calendar; the preconditions rule out a broken fixture, and the control shows the same fixture yields 09:00 when planned at 7:00.
- **M2 and M3 survive as code path.** Both routes are reachable from shipping UI; the save path and sign-out do refresh, so the omission is not a design choice. Not counted as proved.
- **M4 survives as code path**, with the caveat that circle billing masks it for signed-in families.
- **M5 survives as code path.** The slot logic is unambiguous; Ask to Buy reached it on every pending purchase.
- **M6 survives as code path.** Low impact.
- **M7 survives as code path** and is held: no reviewer disputes the behaviour, but the fix is a reliability trade-off.
- Dropped: dose reminders firing after a dose is taken (repeating by design), DST for dose reminders (wall-clock components), a stopped medication (excluded and refreshed), the 64-request cap (handled and shown).
