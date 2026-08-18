# plan82: post-1.0 feature build

Six slices from `aso-plan.md` Appendix B. Each is built by **one agent in a fresh
context**. You were told which letter you are.

## How to run this

```
Read archive/plan82.md. You are agent A.
```

Then `/clear` and repeat for B, C, ... Slices are **strictly ordered**: each starts
from the previous one's committed `main`. Do not run two at once, they collide in
`SyncEngine.swift`.

## Status

Agent's last commit updates this table. If your row is not `todo`, stop and say so.

| # | slice | file | migration | status |
|---|---|---|---|---|
| A | Dose reminders | `archive/plan82/A-dose-reminders.md` | none | done |
| B | Refill tracking | `archive/plan82/B-refills.md` | 0009 | done |
| C | `Provider` entity | `archive/plan82/C-providers.md` | 0010 | done |
| D | Incident / symptom log | `archive/plan82/D-incidents.md` | 0011 | done |
| E | Timeline | `archive/plan82/E-timeline.md` | none | done |
| F | Search | `archive/plan82/F-search.md` | none | done |

**Read your slice file and nothing else from this table.** Migration numbers are
pre-assigned so a later slice never renumbers an earlier one.

## Contract (every agent)

1. Read this file, then your slice file. Read only the source files your slice lists.
2. Do not touch another slice's files. Do not "improve" anything you pass through.
3. Rerun `xcodegen generate` after adding or removing any `.swift` file.
4. Build + test green before committing. Sim lease: `agent-sim checkout aging`,
   target the returned UDID, `agent-sim checkin aging` when done. Never a named
   destination, never Simulator.app.
5. One conventional commit for the slice. Flip your row to `done` in the same commit.
6. If a step is blocked, finish everything else, then say exactly what you skipped.

## Invariants (breaking one means the change is wrong)

- **I1** ER with no signal. Every screen renders from SwiftData. No slice may put a
  network call in front of a read.
- **I2** No billing check anywhere in the check-in write path.
- **I3** A solo caregiver with no group gets the full app. Nothing gates on a group.
- **I6** Nothing detects an emergency or summons help. Logging an incident is fine.
- Never claim to treat, cure, or diagnose (App Review 1.4.1).
- Migrations are append-only once applied. Fix forward, never edit a shipped file.
- Enums persist as `*Raw` strings with a computed accessor.
- Schedules are minutes from midnight, not `Date`. `weekdays` is 1-indexed, Sunday
  first; empty means every day.

## Recipe: adding a synced entity (slices C and D only)

The expensive shared knowledge, written once so no agent has to rediscover it. Nine
touchpoints, in order:

1. `Shared/Models/CareModels.swift`: new `@Model`. Every stored property needs a
   default (SwiftData lightweight migration). Include the five sync fields:
   `groupID: UUID?`, `updatedAt: Date`, `deletedAt: Date?`, `isDirty: Bool = true`,
   `serverVersion`.
2. `Shared/Services/CareModelStore.swift:19`: add to `Schema([...])`.
3. `Shared/Models/SyncModels.swift:211`: new `SyncEntity` case. **The raw value is
   the Postgres table name.** Check the per-entity policy switch below it (~:234).
4. `Shared/Services/SyncRemote.swift`: a `SyncDTO` struct, snake_case coding keys.
5. `Shared/Services/SyncEngine.swift`: five edits: the `pull(entity:)` switch
   (~:64), `apply(_:)` (~:115), a new `applyX` + `write` pair beside the others, the
   `push(entry:)` switch (~:457), and `markSynced` (~:553).
6. `supabase/migrations/00NN_*.sql`: table, RLS on, group-scoped policies,
   `updated_at` trigger. Model it on `0002_care_data.sql`; do not invent a new shape.
7. `supabase/tests/`: assertions, then `scripts/test-db.sh` (no Docker).
8. `xcodegen generate`.
9. `AgingTests/SyncEngineTests.swift`: round-trip plus one conflict case.

Sources are globbed by directory in `project.yml`, so a new file under `Shared/` or
`Aging/` needs no `project.yml` edit.

## What is already built

Do not rebuild these. `TodayView`, `Medication` + `ScheduleEngine`, `Visit`,
`VitalReading`, `EmergencyContact`, `EmergencyCardView`, groups/roles/invites/sync
with `recordedBy` attribution, `MedListExporter` one-pager, `CheckInService`.

## Out of scope for all six slices

Password vault, interaction checker, insurance, financial, document vault, care-task
board, AI assistant, fall detection, location sharing, HealthKit. Each is priced and
refused in `aso-plan.md` Appendix B. If a slice seems to want one, it does not.
