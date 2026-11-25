# Fixes for the 2026-11-24 state machine audit

Fixes for the claims in `state-machines-2026-11-24.md` that survived its Phase 2 review, in ranked order.

**Summary: 7 claims. 6 fixed (1 proved by a failing test, 5 code path), 1 held for Jack, 0 skipped.**

The audit rules fix only claims with a failing test. M2 to M6 have none, because the app has no notification-center, `CustomerInfo` or view-state seam. Each was still fixed because it is plainly broken on a reachable route, and each fix is a few lines that copy a path the app already has (the save path's refresh, sign-out's re-plan, the paywall's own message slot). Each is marked "code path" below and none is claimed as proved.

## Claims

| ID | Outcome | Commit | Regression test | What changed |
|---|---|---|---|---|
| M1 | Fixed | `fix: a refill reminder planned after 9:00 fires at the next 9:00` (`c4042b0`) | `AgingTests/StateMachineRegressionTests.swift`: `m1ARefillReminderPlannedAfterNineFiresAtTheNextNine` (the repro's claim, fails on `2735f52`), `m1ASupplyAlreadyLowWhenEnteredAtLunchIsStillReminded`, `m1AnEveningReplanKeepsTheRequestAlreadyPending`; controls `m1ControlPlannedBeforeNineFiresAtNineToday`, `m1ControlAThresholdDaysAwayKeepsItsDay` | `RefillReminderPlanner.requests` moves a fire time that is not after now to the same 9:00 one day later, so iOS is never handed a one-shot trigger in the past. Nothing stored changes, so existing installs need no upgrade step: the next refresh rewrites any dead request through the existing body-and-moment diff. |
| M2 | Fixed (code path) | `fix: withdraw reminders when an appointment or a circle goes away` (`520cde0`) | none (no notification-center seam); `plan(in:)` already drops a tombstoned visit | The appointment delete in `VisitsView` re-plans reminders, as its save path already did. |
| M3 | Fixed (code path) | same commit as M2 | none, same reason | `GroupService.forgetGroupLocally` (leave, delete, removed by the organizer) and `applySelfAccess` (access narrowed) re-plan reminders after the local wipe, so no request names a person the phone no longer holds. Sign-out already did this. |
| M4 | Fixed (code path) | `feat: show a pending Ask to Buy as waiting for approval` (`59e16ee`) (Rollout A) | `PurchaseErrorTests` covers the mapping; the delegate itself has no `CustomerInfo` fixture | `StoreService` is the RevenueCat `PurchasesDelegate`. A customer-info update applies the entitlement at once, pulls the circle's billing when it turns Plus on, and an open paywall closes. |
| M5 | Fixed (code path) | `fix: a purchase error no longer hides the picked plan's disclosure` (`6353069`) | none (view `@State`) | `PaywallView` clears the message when a plan is picked or a purchase starts, so the selected plan's disclosure comes back. |
| M6 | Fixed (code path) | `feat: ask for a rating only while Today is on screen` (`420de26`) (Rollout S) | `ReviewMomentTests` covers the moment predicate; the on-screen flag is view state | Today tracks `onAppear`/`onDisappear` and the delayed ask re-checks it, so a tab switch or a push inside the 3 seconds skips the ask (it stays pending for the next tick-off). |
| M7 | Held for Jack | none | none | See below. |

## Held for Jack

- **M7. The check-in reminder fires after the person has checked in.** The reminder is one repeating daily trigger at the window midpoint (`CheckInService.swift:224-247`), and iOS cannot skip one day of a repeating trigger. Removing it would mean a set of dated one-shot requests, re-planned on every press and every open, with today's dropped once the button is pressed. The cost: if the person stops opening the app (exactly the day the check-in exists for), the one-shots run out after however many days were planned, where the repeating trigger never does. Decision: (1) keep the repeating trigger and accept the extra nudge on days already checked in (today's behaviour), or (2) switch to about 14 dated one-shots, taken out of the 64-request budget, with the first one skipped after a press. Recommendation: 1, because this is the one notification the app says has to be reliable, and a nudge on a day already done costs less than none on a day missed.

## Skipped

None.

## Tests

- **Full suite, this branch (`420de26` code):** `gh-sim test --scheme Aging`, run `elderhub@20261124-210016-9804-claude-mbpro9d36-1124-223946-14531`, GitHub run `45562269983` (Xcode 27.1, iPhone 17, iOS 27.2): **430 passed, 0 failed, 0 skipped**, including the 5 `StateMachineRegressionTests`.
- **Baseline, starting commit `2735f52`:** same command, GitHub run `45550819284`: 410 passed, 0 failed. No test already failed before this work, and none newly fails.
- **The claim on the starting commit:** the audit's repro (`state-machines-2026-11-24-repro.swift`) on `2735f52`, GitHub run `45558492028`: the M1 claim failed (fire date 09:00 that morning, planned at 20:05), the control passed. Its claim test is the same scenario as `m1ARefillReminderPlannedAfterNineFiresAtTheNextNine`, which passes on this branch.
