---
paths:
  - "Shared/Models/CareModels.swift"
  - "Shared/Services/BillPlanner.swift"
  - "Shared/Services/DeviceModeService.swift"
  - "Shared/Services/MedListExporter.swift"
  - "Aging/Views/EmergencyCardView.swift"
  - "Aging/Views/CareNotesView.swift"
  - "Aging/Views/BillsView.swift"
  - "Aging/Views/BillEditorSheet.swift"
  - "Aging/Views/HandoverViews.swift"
  - "Aging/Views/PersonDetailsEditorSheet.swift"
  - "AgingTests/BillPlannerTests.swift"
  - "AgingTests/CareNoteTests.swift"
  - "AgingTests/DeviceModeTests.swift"
  - "AgingTests/MedListExporterTests.swift"
---

# Elderhub: records, the emergency card, notes and bills

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

### Person labels

  `Person.displayLabel` is the **entered name**, never the relationship: two
  labels for one row (Today saying "Mom" while the emergency card says
  "Eleanor") is unreadable in an ER, and the relationship-first version also
  produced "Me's care record". Relationship is the subtitle.

### Services

- `Services/BillPlanner.swift` — the same shape as `TaskPlanner`, for `Bill`:
  bucketing (overdue / due soon / later / no date / autopay), recurrence
  arithmetic and the outstanding total. Autopay is checked *before* the date, so
  a direct debit is never called overdue; without that the overdue section stops
  meaning anything. Marking a recurring bill paid creates a **new row** for the
  next period rather than moving this one's date, exactly as `CareTask` does,
  because "did anyone pay the March invoice" is what the history is for.

- `Services/DeviceModeService.swift` — who is holding *this handset*
  (`.caregiver` / `.recipient`) and the four-digit caregiver code that swaps back.
  A different axis from `GroupRole`, which is what an *account* may do in the
  circle and is enforced by RLS; keep the two named apart in code and in copy. The
  emergency card is never behind the code, the service never imports
  `StoreService` (I2), and clearing the code returns to the caregiver's app so a
  handed-over phone is never a door with no handle. See `docs/architecture.md` §19.

- `Models/CareModels.swift` also holds `CareNote`, the deliberately unstructured
  per-person note. It is **not** a password vault and must never become one by
  drift: no field is typed as a credential, no copy invites one, and the body is
  plaintext under the same RLS as everything else. The editor footer says so at
  the point of entry, which is the only place the boundary is any use. See
  `docs/architecture.md` §14 for what a real vault would require.

- **`Bill` is on that same line and is the likeliest place to cross it.** A
  screen headed "Bills" is where a family will put the online banking login if
  a box is left open for it, so there is no account-number, reference, card or
  login field, the editor footer says so at the point of entry, and `notes` is
  plaintext under the same RLS as everything else. The other half: nothing here
  pays anything. `paidAt` records that a human says they paid it, the way a
  `DoseLog` records that a human says a tablet was swallowed.

- `Services/MedListExporter.swift` — the plain-text one-pager. It prints every
  critical section even when empty ("ALLERGIES: not recorded"), because a
  section that simply vanishes reads as a negative answer to whoever is holding
  the page. `EmergencyCardView` follows the same rule, and the two must stay in
  step on what they include: the export used to omit the provider block the card
  showed.

- **A primary emergency contact is marked, not just sorted first.** The card
  prints a "CALL FIRST" badge and the export prefixes the line with
  `CALL FIRST:`. Order alone was the entire signal, and it is not one a
  stranger can read: somebody holding this page in an ER has no reason to think
  the list is ordered, and with three names on it they pick one. Both renderers
  and `EmergencyContactEditorSheet`'s footer say the same thing.

- `EmergencyCardView.telURL` stops at an extension marker (`x`, `#`, `,`, `;`).
  Keeping every digit turned "555-1234 x203" into a real, wrong number the card
  offered to dial.
