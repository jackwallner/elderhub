# D. Incident / symptom log

Migration **0011**. Follow the nine-step recipe in `archive/plan82.md`.

## Goal

`symptom tracker` is pop 33, the second-highest real-volume term in the entire
94-keyword pull. One typed note entity covers falls, ER visits, mood, appetite,
sleep and pain, which is the rest of the care-journal ask.

## The line you may not cross

**I6: nothing detects an emergency or summons help.** This slice records what a human
types after the fact. No accelerometer, no fall detection, no automatic escalation,
no "are you OK?" prompt triggered by an entry, no 911 affordance beyond what
`EmergencyCardView` already has. A logged fall notifies nobody automatically; it
appears in the group's shared record like every other row.

Never claim to treat, cure, diagnose, or predict (1.4.1). This is a notebook.

## Read only these

- `archive/plan82.md`: the recipe.
- `Shared/Models/CareModels.swift:300-400`: `VitalKind` and `VitalReading`. Your
  entity is the same shape with a free-text body; copy the `*Raw` enum pattern.
- `Shared/Services/SyncRemote.swift:108-122`: `VitalDTO`.
- `Shared/Services/SyncEngine.swift:289-315`: `applyVital`.
- `supabase/migrations/0002_care_data.sql`: the `vital_readings` table.
- `Aging/Views/VitalsView.swift`: the list + entry sheet pattern to mirror.

## Build

`CareEvent`: `kindRaw` (`fall`, `erVisit`, `hospitalStay`, `symptom`, `mood`,
`appetite`, `sleep`, `pain`, `other`), `occurredAt: Date`, `severity: Int` = 0
(0 means unset), `note: String`, `recordedBy: String`, belongs to `Person`, plus the
five sync fields. Everything defaulted.

`recordedBy` matters more here than anywhere else in the app: "Sarah logged a fall on
Tuesday" is the sentence the family needs. Populate it the same way `DoseLog` does.

UI: a list on `PersonDetailView` grouped by month, newest first, and an entry sheet.
Filter by kind. No charts. No trend language, no "3 falls this month suggests..."
Count and list, nothing inferential.

## Tests

`AgingTests/CareEventTests.swift`: unknown `kindRaw` falls back to `.other` rather
than crashing (the whole reason enums are stored as strings); month grouping respects
the device time zone; `recordedBy` survives a sync round-trip.

`AgingTests/SyncEngineTests.swift`: round-trip plus one conflict case.

DB: assertions in `supabase/tests/`, then `scripts/test-db.sh`.

## Commit

`feat(events): log falls, symptoms and incidents per person`

Flip row D to `done` in `archive/plan82.md` in the same commit.
