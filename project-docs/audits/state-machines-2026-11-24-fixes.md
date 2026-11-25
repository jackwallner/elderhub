# Fixes for the 2026-11-24 state machine audit

Fixes for the claims that survived the skeptical review in `state-machines-2026-11-24.md`, in its ranked order.

**Summary: 6 claims. 1 proved and fixed (B1), 1 proved and held for Jack (B2), 4 code path fixed without a headless proof (C1 to C4), 0 skipped.**

## Claims

| ID | Outcome | Commit | Regression test | What changed |
|---|---|---|---|---|
| B1 | Fixed | `fix: a late month-end bill or task keeps its due day` | `StateMachineRegressionTests.lateBillDueOnThe31stKeepsItsDay`, `lateTaskDueOnThe31stKeepsItsDay`, `lateQuarterlyBillKeepsItsDay` (the repro, which fails without the fix); controls `onTimeBillDueOnThe31stStillGoesToTheEndOfFebruary`, `lateMidMonthBillStillKeepsItsDay`, `weeklyAndDailyStepsAreUnchanged`; upgrade `aStoredFollowUpKeepsItsDate` | `BillPlanner.nextDueDate` and `TaskPlanner.nextDueDate` take each candidate as a whole number of steps from the row's own due date (`DateComponents.scaled(by:)`), not one step from the previous, clamped candidate. Stored rows are not touched. |
| B2 | Held for Jack | none | the repro's `monthEndSeriesReturnsToThe31stAfterFebruary` stays in the audit suite | See below. |
| C1 | Fixed (code path) | `fix: rebuild reminders when an appointment is deleted or a sync pulls changes` | none headless: iOS's pending requests cannot be populated in a unit test | Deleting appointments from Appointments rebuilds the reminder plan, as deleting a medication already did. |
| C2 | Fixed (code path) | same commit as C1 | none headless, same reason | `SyncCoordinator.syncNow` rebuilds the reminder plan after a cycle that pulled rows, so a sibling's stop or move reaches this phone's reminders without waiting for the next foreground. The diff makes an unchanged plan a no-op. |
| C3 | Fixed (code path) in Rollout A | `fix: Ask to Buy shows waiting for approval and unlocks when approved` | `PurchaseNoticeTests` covers the pending mapping; the stream itself needs a configured RevenueCat | `StoreService` follows `Purchases.shared.customerInfoStream` from configuration on, so an approval, renewal or lapse updates `isPro` while the app is open, and an open paywall closes once Plus arrives. |
| C4 | Fixed (code path) in Rollout A | same commit as C3 | `PurchaseNoticeTests` for the copy; the clearing is view state | The paywall's purchase notice is cleared by a new attempt and by choosing another plan, so the disclosure for the selected plan comes back. |

## Held for Jack

- **B2, a month-end series stays on the 28th after February.** The only record of a series is the previous row's due date, so after 28 February nothing on the device knows the family meant the 31st. Fixing it needs the series' day of month stored on every bill and task row: a new synced column, a migration applied with `./scripts/db-apply.sh` before the client ships, and the Android port to match. Decision: add a `due_day` (1 to 31) column to `bills` and `care_tasks`, written when a repeating row is created or its date is edited, and step follow-ups from it? Recommended, because rent and care-home invoices are the bills most often due on the 31st and they drift every year.

## Skipped

None.

## Tests

FULL_SUITE_PLACEHOLDER
