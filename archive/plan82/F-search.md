# F. Search

No migration. Last slice: it is only worth building once B, C, D and E exist.

## Goal

Type "hearing" and get the audiologist, the hearing-aid medication note, the visit
where it came up, and the incident log entry. Local, offline, no server (I1).

This plus the timeline and `MedListExporter` is the deliberate answer to the "AI
assistant" ask in `aso-plan.md` Appendix B. Most of those example questions are a
search over a well-structured local store, answered deterministically, offline, at
zero marginal cost, without shipping anyone's medical record to a third party.

## Read only these

- `Shared/Models/CareModels.swift`: every `@Model`, for their text fields.
- `Shared/Services/TimelineBuilder.swift`: whatever E shipped. Reuse
  `TimelineEntry` if it fits; do not fork it.
- `Aging/Views/PeopleView.swift`: the root the search field attaches to.

## Build

`Shared/Services/CareSearch.swift`: a pure function over already-fetched arrays
returning ranked `SearchHit` values (`personID`, `kind`, `title`, `snippet`,
`matchedField`). Pure, so it tests without a store.

Fields to cover: medication `name` / `purpose` / `instructions`, `Provider` name /
specialty / notes, `Visit` provider / reason / notes / followUp, `CareEvent` note,
`Person` conditions / allergies / notes, `EmergencyContact` name.

Matching: case- and diacritic-insensitive substring, tokenised on whitespace, all
tokens must match somewhere in the record. No fuzzy matching, no stemming, no index.
Rank by field priority (name beats notes) then recency. Cap results per kind so one
noisy field cannot crowd out the rest.

Scope: across all people by default, with the person's name on each hit, because "was
that Mom or Dad?" is exactly the question a multi-person app has to answer.

Soft-deleted records (`deletedAt != nil`) never appear.

**Performance is the risk.** A naive scan refetching everything on each keystroke
will stutter once D has two years of rows. Debounce input, fetch once per query
rather than per keystroke, and keep the matching function allocation-light. Measure
against a seeded store, not an empty one.

Extend `Aging/Support/SampleData.swift` with a large seed so the sim run is honest
about the row counts this has to survive.

## Tests

`AgingTests/CareSearchTests.swift`: multi-token queries require all tokens; matching
is diacritic-insensitive; soft-deleted records never surface; field priority ordering
holds; an empty query returns nothing rather than everything.

## Commit

`feat(search): offline search across people, meds, providers, visits and events`

Flip row F to `done` in `archive/plan82.md` in the same commit.
