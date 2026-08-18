# C. `Provider` entity

Migration **0010**. Follow the nine-step recipe in `archive/plan82.md`.

## Goal

One row per doctor, specialist, dentist, pharmacy, therapist. Today `prescriber`,
`pharmacy`, `Visit.provider` and `Visit.specialty` are loose strings retyped on every
record. Dad's spreadsheet had one row per provider with phone, address, portal link
and notes, and that shape is correct.

## Read only these

- `archive/plan82.md`: the recipe. Do not rediscover the touchpoints.
- `Shared/Models/CareModels.swift`: `Person`, `Medication`, `Visit`, and
  `EmergencyContact` (the closest existing analogue; copy its shape).
- `Shared/Services/SyncRemote.swift:122-135`: `EmergencyContactDTO`, same reason.
- `Shared/Services/SyncEngine.swift:315-340`: `applyContact`, same reason.
- `supabase/migrations/0002_care_data.sql`: the `emergency_contacts` table and its
  policies. Your table is the same shape with more columns.
- `Aging/Views/VisitsView.swift`, `Aging/Views/MedicationEditorSheet.swift`,
  `Aging/Views/EmergencyCardView.swift`

## Build

`Provider`: `name`, `specialty`, `phone`, `address`, `portalURL`, `notes`,
`isPharmacy: Bool`, belongs to `Person`, plus the five sync fields. Every property
defaulted.

**Additive only.** `Medication.providerID: UUID?`, `Medication.pharmacyID: UUID?`,
`Visit.providerID: UUID?`. **Leave the existing free-text `prescriber`, `pharmacy`
and `provider` strings in place and keep displaying them when no id is set.** They
hold real user data on shipped devices and there is no safe backfill, so do not
migrate, clear, or "clean up" them. New records set the id; old records keep working.

UI: a provider picker in the medication and visit editors that offers existing
providers for that person and has an inline "Add new". A provider list reachable from
`PersonDetailView`. Providers with a phone number appear on `EmergencyCardView` under
the existing contacts, tappable to call. Do not add a tab.

`portalURL` is a plain stored string rendered as a link. **It is not credential
storage**: no username, no password, no "saved login" affordance. The password vault
is refused in `aso-plan.md` Appendix B and this field is the closest thing to it.

Extend `MedListExporter` so the one-pager prints the prescriber and pharmacy with
phone numbers. That one-pager is the feature that earns the app; a provider phone
number on it is the whole point of this slice.

## Tests

`AgingTests/ProviderTests.swift`: a medication with a `providerID` resolves the name;
with no id it falls back to the legacy string; deleting a provider nulls the
reference and does not delete the medication. Extend `MedListExporterTests`.

`AgingTests/SyncEngineTests.swift`: round-trip plus one conflict case.

DB: assertions in `supabase/tests/` proving anonymous access is blocked and a
non-member cannot read another group's providers. Then `scripts/test-db.sh`.

## Commit

`feat(providers): add providers as a first-class synced record`

Flip row C to `done` in `archive/plan82.md` in the same commit.
