# E. Timeline

No migration. No new entity. Read-only over what C and D added.

## Goal

One chronological history per person: doses, visits, vitals, medication changes,
incidents, check-ins. `aso-plan.md` Appendix B calls this the one thing on the list
nobody else has, and it feeds `health journal` (pop 22).

It is near-free because every entity already carries `createdAt`, `updatedAt` and
`recordedBy`, and already syncs. **If you find yourself adding a table, stop:** you
have misread the slice.

## Read only these

- `Shared/Models/CareModels.swift`: every `@Model`, for their date fields.
- `Shared/Models/SyncModels.swift:60-135`: `CheckInRecord` and `CheckInSource`.
- `Aging/Views/PersonDetailView.swift`
- `Aging/Views/VitalsView.swift`: list styling to match.

## Build

`Shared/Services/TimelineBuilder.swift`: a **pure** function taking the fetched
arrays and returning `[TimelineEntry]` sorted descending, where `TimelineEntry` is a
value type with `date`, `kind`, `title`, `detail`, `personID`, `recordedBy`. No
SwiftData imports in the builder, no fetching inside it. All logic testable without a
store, same as `ScheduleEngine`.

Include: `Visit`, `VitalReading`, `CareEvent`, `CheckInRecord`, medication started /
stopped (derive from `startDate`, `endDate`, `isActive`), and dose logs whose status
is **not** `taken`. Taken doses are the overwhelming majority of rows and would bury
everything else; missed and skipped are the signal.

`TimelineView` renders it, grouped by month, with a kind filter. Paginate or cap the
fetch: two years of a busy person is thousands of rows and this must not stall
`PersonDetailView`. Load the most recent window first and extend on scroll.

Reachable from `PersonDetailView`. Do not add a tab.

**I1**: renders entirely from SwiftData. No sync call on appear, no spinner, no empty
state that blames the network.

## Tests

`AgingTests/TimelineTests.swift`: entries sort strictly descending across mixed
types; taken doses are excluded and missed doses included; a medication with an
`endDate` produces both a started and a stopped entry; an empty person yields an
empty array, not a crash.

## Commit

`feat(timeline): merged chronological history per person`

Flip row E to `done` in `archive/plan82.md` in the same commit.
