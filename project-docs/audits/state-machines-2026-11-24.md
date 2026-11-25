# State machine audit, 2026-11-24

Scope: the Elderhub iOS app (target `Aging`; no widget, watch or App Intents target). Android, the Supabase functions and the database are out of scope except where a client state machine reads them. Audited from committed code at `74bec1f`, with no app code changed for the audit. Method follows the fleet's 2026-11-06 audit (`jackwallner/baseball`, `project-docs/audits/state-machines-2026-11-06*.md`).

**Summary: 2 bugs proved by a failing headless test (B1, B2), 4 code path only (C1 to C4, not proved).** Plus 6 product calls (not counted).

Evidence run: `gh-sim test --scheme Aging --only AgingTests/StateMachineAuditRepro` on a clean checkout of `74bec1f` with only the repro suite added, GitHub run `45550920479` (result below in "Evidence results"). The suite is `state-machines-2026-11-24-repro.swift` beside this file (copy it into `AgingTests/` to run it). No build setting needs a placeholder value: the build reads Supabase settings at run time and the tests never reach the network.

Seams used: `BillPlanner.nextDueDate` and `TaskPlanner.nextDueDate` take a calendar; `Bill.markPaid` runs against `CareModelStore.makeInMemoryContainer()`. Seams that do not exist: a way to read what `UNUserNotificationCenter` is holding from a unit test (the simulator never grants notification permission, so `DoseReminderScheduler.apply` removes everything and returns), a `CustomerInfo` fixture or an injected RevenueCat client for `StoreService`, and any way to drive `PaywallView`'s `@State` without a UI test. That is why C1 to C4 stay code path.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Impact | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | A month-end bill or task paid or ticked late comes back on the 28th | Rent due on the 31st, paid on 5 March: the next rent shows due 28 March, three days early, and turns overdue three days before it is. | `BillPlanner.swift:54-55` and `TaskPlanner.swift:47-48`: "The next occurrence at or after `notBefore`, stepping by whole calendar units from `date`". Two months from 31 January is 31 March; the loop steps from each clamped intermediate (31 Jan, 28 Feb, 28 Mar). User data misstated: the due day the family entered. | Care, a person, Bills, add a bill due on the 29th, 30th or 31st, Repeats Monthly (or Quarterly, Half-yearly). Let it pass a shorter month unpaid. Mark it paid (Today, or the Bills list). Same for a recurring task ticked late. | Any repeating bill or task due on the 29th to 31st that is paid after a shorter month has gone by. Month-end is a normal due day for rent, care-home invoices and pension-day errands. Each time: one wrong due date, and an early overdue on Today and the hub. | `lateBillDueOnThe31stKeepsItsDay`, `lateTaskDueOnThe31stKeepsItsDay`, `lateQuarterlyBillKeepsItsDay` fail on the audited commit. Preconditions asserted first (February 2027 has 28 days; two months after 31 Jan is 31 Mar). Controls `controlOnTimeBillDueOnThe31stGoesToTheEndOfFebruary` (28 Feb) and `controlLateMidMonthBillKeepsItsDay` pass. | `BillPlanner.swift:69-77`, `TaskPlanner.swift:62-70` |
| B2 | Once a month-end series passes February it stays on the 28th for good | Rent due on the 31st, paid on time every month: from March on every rent is due on the 28th. | Same doc comments as B1; user data misstated. `CareModels.swift:1232,1564`: each follow-up steps from the paid row's own `dueAt`, and the February row says the 28th. | Same as B1, paying on time. | Every repeating bill or task due on the 29th to 31st, once a year at February (and the 31st also becomes the 30th after any 30-day month). | `monthEndSeriesReturnsToThe31stAfterFebruary` fails on the audited commit; its first assertion (February's row is the 28th) passes. | `CareModels.swift:1225-1236`, `:1557-1567` |
| C1 | (Code path, not proved) Deleting an appointment leaves its evening-before reminder pending | "Mom: cardiology tomorrow at 9:30 AM" at 6pm for an appointment the family deleted because it was cancelled. | `.claude/rules/reminders.md`: an appointment reminder "is rewritten when what it says or when it fires changes". Deleting a medication refreshes the plan (`PersonDetailView.swift:493`); deleting a visit does not. | Care, a person, Appointments, swipe an upcoming appointment, Delete, confirm. Background the app. Nothing rebuilds the plan until the next foreground or launch (`RootView.swift:94,110`), so a deletion the afternoon before still fires at 6pm. | Caregivers with "Doses and appointments" on who delete an upcoming appointment and do not reopen the app before 6pm the day before it. | Not run: the only witness is iOS's pending-request list, which a unit test cannot populate (no permission on the simulator). | `VisitsView.swift:128-130` |
| C2 | (Code path, not proved) A sibling's change pulled mid-session does not reach this phone's reminders | A medication a sibling stopped keeps its 8am "Mom: Warfarin" reminder on this phone until the app is next foregrounded. | Same rule file. The plan is rebuilt after launch and foreground syncs only (`RootView.swift:93-94,107-110`), but `syncNow` runs after every local write (18 call sites), and any of those pulls can carry the stop. | Two caregivers with reminders on. B stops a medication; A, already in the app, ticks a dose (a sync that pulls B's stop) and leaves. | Multi-member circles where two people use the app the same hour. Narrow, and cleared at the next foreground. | Not run: same notification-center seam as C1. | `SyncCoordinator.swift:63-66` |
| C3 | (Code path, not proved) An Ask to Buy approved later stays locked until relaunch | A child account taps the trial, the parent approves; the second person still cannot be added until the app is killed and reopened. | `AGENTS.md` (Tech Stack): Plus is "resolved as `store.isPro || groups.hasPlus`" (`PeopleView.swift:88`); nothing updates `isPro` after launch except a purchase or restore result: no `PurchasesDelegate`, no `customerInfoStream`, no foreground refresh. | Paywall, Start trial, Ask to Buy, parent approves on their device. | Family-sharing child accounts (rare in this audience). Also renewals and lapses while the app stays resident. | Not run: needs a `CustomerInfo` fixture. | `StoreService.swift:211-217,375-391` |
| C4 | (Code path, not proved) A failed purchase hides Apple's price disclosure until the sheet closes | After one failed attempt (no signal), choosing another plan shows the old error where that plan's billed amount and renewal terms should be. | `PaywallView.swift:98-99`: "Apple's required disclosure, rebuilt for the selected plan so the billed amount, the period and the trial always match the row above." `errorMessage` is set at `:464` and never cleared, and it takes the disclosure's slot (`:266`). | Paywall, Continue with no connection, error. Tap the Monthly plan. | Anyone whose purchase fails once (an offline-first app's normal case). | Not run: view `@State` with no headless seam. | `PaywallView.swift:19,266-275,464` |

## Evidence results

Repro run `45550920479`: pending at the time of the audit commit; recorded in the fixes doc. Local cross-check (Command Line Tools Swift 6.0.3, the planner's loop and the fixed loop copied into a script, Gregorian, America/New_York): 31 Jan monthly with `notBefore` 5 Mar 2027 gives 28 Mar under the shipped loop and 31 Mar under whole steps from the start; 30 Nov quarterly with `notBefore` 1 Mar gives 28 May and 30 May. On-time month end (28 Feb), mid-month (15 Apr), weekly and daily across the DST change are identical under both.

## Phase 2, skeptical review

- B1 survives. The route is the shipping Bills and Tasks screens; the test calls the same planner `markPaid` and `markComplete` call, with a real Gregorian calendar, and the control shows the harness gets mid-month dates right.
- B2 survives as a bug, but its root is data, not arithmetic: the only record of the series is the previous row's date, so the fix needs the series' day stored per row (a new synced column and a migration). Held for Jack.
- C1 survives as a route: the delete closure is the only place a visit is tombstoned, and no refresh follows it. Not proved; listed for the fix pass because the inconsistency with medication delete is direct.
- C2 survives, narrower than C1.
- C3 survives as a route; Rollout A (Ask to Buy) wires the customer-info stream anyway.
- C4 survives; Rollout A replaces that error slot anyway.
- Dropped: a bill follow-up does not copy `groupID` while a task follow-up does (`CareModels.swift:1248`). The push stamps every row with the cycle's group (`SyncEngine.swift:1202`), so nothing is lost.
- Dropped: a check-in record lookup that ignores `deletedAt`. Check-in records are never tombstoned.

## Product calls (not counted: documented, or no cited promise)

1. Dose reminders and the check-in reminder are repeating calendar triggers, so they fire even after the dose is logged or the check-in pressed. D26 (`docs/architecture.md:97`) chose a repeating trigger as the one iOS guarantees.
2. Buying Plus from the "Add person" paywall closes the sheet but does not open the add-person editor; the reader taps Add again.
3. A handed-over phone keeps the caregiver's own dose reminders for everyone.
4. `ReviewPrompt.markShown()` starts the 30-day cooldown even when iOS shows nothing. Fleet policy (pacing, not answers).
5. A check-in pressed late in the evening and read after flying west can fall on a different calendar day (`CheckInService.hasCheckedInToday` uses the phone's calendar). The server judges in the settings zone.
6. An Ask to Buy approved later never writes the `converted_*` attributes (`ConversionDiagnostics.recordConversion` runs only on a direct purchase result). Attribution only.

## State machines

### SM1. Entitlement and purchase (`StoreService`, `PaywallView`)

State: `isConfigured`, `isPro`, `localOverride`, `offerings`, `plans`, `isLoading`, `hasAttemptedLoad`, `loadFailure`, `introEligibility`, `introEligibilityResolved`; the paywall's `isPurchasing`, `errorMessage`, `selectedPlanID`.

Invariants: E1 `isPro` follows RevenueCat's latest customer info. E2 every trial line reads `eligibleTrialDays`, nil until eligibility resolves. E3 the disclosure under the button describes the selected plan. E4 the paywall is in exactly one of loading, no plans, loaded.

| From | Event | To | Invariant touched |
|---|---|---|---|
| Unconfigured | `start()` on device | Configured, `refresh()` | none |
| Configured | `refresh()` ok | plans loaded, eligibility resolved | E2, E4 |
| Configured | `refresh()` fails | no plans, `loadFailure` set | E4 |
| Free | purchase ok | Pro, sheet dismisses, conversion recorded | E1 |
| Free | purchase cancelled | Free, no message | none |
| Free | purchase throws (any, including Ask to Buy) | Free, red `errorMessage`, kept until the sheet closes | E3 broken (C4) |
| Free | Ask to Buy approved later | stays Free until relaunch | E1 broken (C3) |
| Pro | lapse while resident | stays Pro until relaunch | E1 (C3) |
| any | restore ok | Pro or "No previous purchase" alert | E1 |

### SM2. Reminder plan versus what iOS holds (`DoseReminderScheduler`)

State: per-person `DoseReminderPreferences` (UserDefaults), the SwiftData records, iOS's pending requests (`dose-`, `refill-`, `appointment-` prefixes), notification authorization.

Invariants: R1 iOS holds exactly the plan for the current records. R2 a revoked permission clears ours. R3 at most 63 of ours.

| From | Event | To | Invariant |
|---|---|---|---|
| any | launch or foreground: sync then `refresh` | plan applied | R1 |
| any | medication save or delete, visit save, person delete, toggle | `refresh` | R1 |
| any | visit delete | no refresh until next foreground | R1 broken (C1) |
| any | mid-session sync pulls a change | no refresh until next foreground | R1 broken (C2) |
| authorized | permission revoked, next refresh | ours removed | R2 |
| denied | permission granted in Settings, next foreground | plan re-added (toggle kept on) | R1 |

### SM3. Recurring bills and tasks (`Bill.markPaid`, `CareTask.markComplete`)

State: the row's `dueAt`, `recurrence`, `paidAt` or `completedAt`; the follow-up row.

Invariants: T1 the follow-up is due on the series' day, clamped only by its own month. T2 it is never created already overdue. T3 Undo on Today removes the follow-up it created.

| From | Event | To | Invariant |
|---|---|---|---|
| open | paid on time | paid, follow-up one step on | T1 broken after a clamped month (B2) |
| open | paid late | paid, follow-up first step after now | T1 broken (B1), T2 |
| paid | Undo on Today within 7 s | open, follow-up tombstoned | T3 |
| paid | reopened from Bills or Tasks | open, follow-up kept (documented) | none |

### SM4. The rating ask (`ReviewPrompt`, `TodayView`)

State: `launchCount`, `lastShownDate`, `outcome`, `hasPendingPositiveMoment`, Today's `reviewTask`.

| From | Event | To |
|---|---|---|
| idle | dose taken, task done or bill paid on Today | pending, ask in 3 s |
| pending | 3 s later, nothing presented, everyone clear, launch 2+, cooldown over, review page never opened | asked, cooldown stamped |
| pending | any check fails | stays pending |
| any | Settings, Rate Elderhub | asks end for good |
| any | Settings, Send Feedback | unchanged |

### SM5. Handover and check-in (`DeviceModeService`, `CheckInService`)

States: caregiver, recipient (named person or nil), PIN set or not; check-in settings enabled or not, the daily reminder pending or not.

| From | Event | To |
|---|---|---|
| caregiver | hand over to a person | recipient, reminder armed if this phone reminds |
| recipient | correct PIN, or no PIN | caregiver, handover id cleared |
| recipient | clear PIN | caregiver |
| caregiver tabs | appear without an own record | check-in reminder removed |
| recipient | named person removed elsewhere | "waiting for" screen, reminder left as armed |
