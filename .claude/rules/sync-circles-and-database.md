---
paths:
  - "Shared/Services/SyncEngine.swift"
  - "Shared/Services/SyncRemote.swift"
  - "Shared/Services/SyncCoordinator.swift"
  - "Shared/Services/GroupService.swift"
  - "Shared/Services/AuthService.swift"
  - "Shared/Services/PostgrestCoding.swift"
  - "Shared/Services/DeterministicID.swift"
  - "Shared/Models/SyncModels.swift"
  - "supabase/**/*"
  - "SupabaseFunctions/**/*"
  - "scripts/db-apply.sh"
  - "scripts/check-schema-drift.py"
  - "Aging/Views/Groups/*.swift"
  - "Aging/Views/ConflictsView.swift"
  - "Aging/Views/CareEventsView.swift"
  - "Aging/Views/MedicationEditorSheet.swift"
  - "Shared/Models/CareModels.swift"
  - "AgingTests/SyncEngineTests.swift"
  - "AgingTests/SyncCoordinatorTests.swift"
  - "AgingTests/LocalWriteTests.swift"
  - "AgingTests/RefillTests.swift"
  - "AgingTests/CareEventTests.swift"
---

# Elderhub: sync, circles, access and the database

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

### Circles and access

- **One account, one circle, and `accept_invite` closes an untouched one for you
  (migrations 0019, 0020).** Onboarding creates a circle for anyone who signs in
  on the "Start a care record" path, so a joiner who did not happen to tap
  "I have an invitation" first was refused with `already_in_group` and had
  nowhere to go from that screen: the family could not get into the record. The
  server now closes the caller's own circle and takes the invitation, but only
  while they own it, nobody else is in it, and it holds nothing but the one
  recipient onboarding created (tasks excepted). A circle with a medication,
  visit, note or bill in it still gets the refusal and is closed deliberately
  from Sharing, where the app says what goes with it. Nothing of theirs is
  carried across: uploading the record they started into the circle they joined
  would be a disclosure, not a migration (I5). Fixed on the server rather than
  in the client because the build in the store prints the refusal with no way
  past it.

- **Access inside a circle is per-recipient (migration 0018).**
  `group_members.access_scope` is `all` (default) or `listed`, and
  `recipient_access` holds what `listed` means. Default is unrestricted, so
  applying 0018 hid nothing anyone could already read. `visible_recipient_ids()`
  is **parameterless on purpose**: a security-definer function taking row values
  cannot be wrapped in `(select ...)` and so runs once per row, while a
  parameterless one hoists to an initPlan and runs once per statement, which
  makes the scoped policies cheaper than the unscoped ones they replaced. Owners
  are never restrictable (the RPC raises *and* the function ignores the flag for
  them). `care_recipients` is the one table whose select policy asks
  `is_unrestricted_staff()` directly rather than naming its own id, because
  `visible_recipient_ids()` is `stable` and cannot see the row a `RETURNING`
  clause just inserted. Restricting someone also purges what their phone already
  downloaded (`GroupService.applySelfAccess`), with `context.delete` and **never**
  `tombstone()`: losing access to Dad's record must not delete Dad's record (I5).

### Conflicts and authorship

- **A flagged conflict carries both readings of the row**
  (`OutboxEntry.localSummary` / `remoteSummary`, captured in
  `SyncEngine.flagConflict`). They have to be captured then or not at all: the
  pull keeps the local row and discards the incoming one, so the family's
  version is gone by the time anybody opens `ConflictsView`. Without them the
  screen asked somebody to choose "Keep mine" or "Use theirs" about a drug
  dosage while showing neither dosage.

- **Every authored row resolves its name through `CareTaskAuthor.name(from:)`.**
  `recorded_by_name` is a *synced* column, so the literal string "You" that
  `CareEventsView` wrote went to the server and came back on everyone else's
  phone: a fall one sibling logged read "Logged by You" on the other's screen,
  on the one feature whose job is answering "what happened while I was away".

### Database and sync rules

- **No `date` column, ever. Every day-valued column is `timestamptz`
  (migration 0021).** supabase-swift decodes every date with one strategy, and
  that strategy only parses a full ISO8601 timestamp; PostgREST serialises a
  `date` as a bare "1939-07-13", which fails it, and the error takes down the
  whole page rather than the one field. One care recipient with a birthday meant
  a joining phone pulled no people at all, and `medications.start_date` is
  `not null`, so it pulled no medications either. It shipped because the only
  phone holding a record was the one that typed it in: the push path never
  decodes, so nothing exercised the pull until the first person accepted an
  invitation and got an empty app. Values converted at **noon** UTC, because
  midnight UTC read through a US calendar is the evening before and would move
  every birthday back a day. `check_in_settings.last_escalated_on` stays a
  `date`: `CheckInSettingsDTO` does not declare it, and Codable ignores a key no
  field asks for.

- **A pulled child is bound to its parent on every apply, not just on the
  insert.** `bindPerson` / `bindMedication` are called whether the row is new or
  already held, because a row attached to nobody is invisible forever: no
  `liveMedications`-style read can reach it, no screen lists it, and nothing
  later puts it right. `SyncEngine.parentState` stops a new one being made (the
  page stops rather than skipping, so the cursor never passes an unwritten row),
  and `repairParentlessRowsIfNeeded` rewinds every pull cursor **once per
  install** for a store that already holds one, so build 27's orphans are
  offered again. That repair deletes nothing: a parentless row may be the only
  copy of something somebody typed, and the re-pull goes through the same
  conflict rules as any other. The `.v1` in the key is load-bearing, a later
  repair is a different question.

- **`DoseLog.id` is derived from (medication, scheduled time), so re-recording a
  slot must reuse its row.** Undoing a dose tombstones the log, and the tombstone
  keeps the id any replacement would be given. Anything that logs a dose therefore
  searches `medication.doses`, not `liveDoses`, and clears `deletedAt` on the row
  it finds. Two rows with one server key is the failure this avoids.

- **`Medication.tracksRefills` is a real column, not a sentinel.**
  `quantityRemaining == 0` used to mean both "not tracked" and "empty", so the
  moment a bottle ran out the medication dropped off Running low, loaded with
  the toggle off, and could not have its last dose undone. Migration 0016 splits
  them; zero while tracking now means out of stock, and `daysRemaining` returns
  0 rather than nil.

- **The Care tab shows group records and local-only records in separate named
  sections, and joining a circle adopts nothing.** Every people query used to
  return every `Person`, so a private record sat in the family list looking
  shared. `SyncEngine.adoptPerson` moves one across, only from an explicit tap:
  uploading the rest of someone's phone because they accepted an invitation is a
  disclosure, not a migration.
