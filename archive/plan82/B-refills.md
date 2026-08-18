# B. Refill tracking

Depends on A (reuses `DoseReminderScheduler`). Migration **0009**.

## Goal

Track quantity on hand, warn before a prescription runs out. The highest-value gap
against the apps currently ranking for `medication list`, and it sits inside the
keyword we are buying.

## Read only these

- `Shared/Models/CareModels.swift:99-250`: `Medication` and `DoseLog`.
- `Shared/Services/SyncRemote.swift:55-92`: `MedicationDTO` and `DoseLogDTO`.
- `Shared/Services/SyncEngine.swift:181-260`: `applyMedication`, `write`, `applyDoseLog`.
- `Aging/Views/MedicationEditorSheet.swift`
- `Aging/Views/TodayView.swift`
- `Shared/Services/DoseReminderScheduler.swift`: whatever A shipped.
- `supabase/migrations/0002_care_data.sql`: the `medications` table, for column style.

## Build

New fields on `Medication`, all with defaults:

| field | type | note |
|---|---|---|
| `quantityRemaining` | `Double` = 0 | 0 means "not tracked", not "empty" |
| `unitsPerDose` | `Double` = 1 | a dose is not always one tablet |
| `refillThresholdDays` | `Int` = 7 | when to warn |
| `lastFilledAt` | `Date?` | |

Migration 0009 is an `ALTER TABLE medications ADD COLUMN ... DEFAULT`, plus the same
columns in `MedicationDTO` and both `write` sites in `SyncEngine`. No new entity, so
the recipe in `archive/plan82.md` does not apply beyond steps 4, 5 and 8.

**Decrement**: when a `DoseLog` is written with status `taken`, subtract
`unitsPerDose`. Do this where dose logs are created, not in `applyDoseLog`: a synced
dose from a sibling's phone must not double-decrement a value that also synced.
That double-count is the one real bug in this slice; write the test first.

**Days remaining** is a computed property on `Medication`: `quantityRemaining /
unitsPerDose / dosesPerDay`, where `dosesPerDay` comes from `scheduleMinutes.count`
adjusted for `weekdays`. Return `nil` when untracked or as-needed.

**Surface it** in two places and no more: a "running low" row in `TodayView`, and the
refill fields in `MedicationEditorSheet` behind a "Track refills" toggle so the
editor does not grow for people who do not want it. One local notification per
medication at the threshold, scheduled through A's scheduler and counted against its
64-request cap.

**Copy discipline**: "Refill soon" / "3 days left". Never "you will run out and get
sick". Organisational framing only (1.4.1).

## Tests

`AgingTests/RefillTests.swift`: locally logged dose decrements once; a dose arriving
via `SyncEngine.applyDoseLog` does not decrement; `daysRemaining` is `nil` when
untracked and when as-needed; weekday-limited schedules stretch days remaining.

DB: assertions in `supabase/tests/`, then `scripts/test-db.sh`.

## Commit

`feat(meds): track quantity on hand and warn before a refill runs out`

Flip row B to `done` in `archive/plan82.md` in the same commit.
