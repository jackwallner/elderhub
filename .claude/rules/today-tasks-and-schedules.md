---
paths:
  - "Shared/Models/CareModels.swift"
  - "Shared/Services/TaskPlanner.swift"
  - "Shared/Services/TodayDigest.swift"
  - "Shared/Services/CareOverview.swift"
  - "Shared/Services/ScheduleEngine.swift"
  - "Shared/Services/TimelineBuilder.swift"
  - "Aging/Views/TodayView.swift"
  - "Aging/Views/CareTasksView.swift"
  - "Aging/Views/VisitsView.swift"
  - "Aging/Views/TimelineView.swift"
  - "Aging/Views/MedicationEditorSheet.swift"
  - "Aging/Views/PeopleView.swift"
  - "Aging/Views/PersonDetailView.swift"
  - "Aging/Views/MedicalRecordView.swift"
  - "Aging/Views/Components/HubComponents.swift"
  - "AgingTests/CareTaskTests.swift"
  - "AgingTests/AppointmentTests.swift"
  - "AgingTests/StoppedMedicationTests.swift"
  - "AgingTests/WeekdayScheduleTests.swift"
  - "AgingTests/TodayDigestTests.swift"
  - "AgingTests/CareOverviewTests.swift"
  - "AgingUITests/CareTaskAssigneeFilterUITests.swift"
  - "AgingUITests/HubRenderUITests.swift"
---

# Elderhub: Today, tasks, appointments and medication schedules

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

- `Services/TaskPlanner.swift` — pure bucketing (overdue / today / …), recurrence
  arithmetic and `CareTaskMerge`, the task-specific sync rule. Two siblings
  ticking off the same errand is agreement, not a conflict; two people editing
  the same task's text is a conflict. Genuine LWW, unlike `applyVisit`.
  `isAssigned` is the one matching rule for "whose errand is this": the id wins
  whenever both sides have one (two siblings called Chris), and the name is the
  fallback, because `assigneeUserID` is only set when the assignee was picked
  from a loaded member list and typing a name offline has to keep working. A
  task that has an id, read on a device whose member list has not loaded yet,
  falls back too, so **Mine** is never silently empty on launch.
  `CareTaskRecurrence` carries quarterly and half-yearly for the same reason
  `BillRecurrence` always did: most of what a family repeats (reorder hearing
  aids, book the audiologist, review the repeat prescription) sits between a
  month and a year, and offering only those two means dismissing a reminder five
  times or missing it once. Cases are free to add: `recurrenceRaw` is a string
  in a column that already exists, and an unknown value falls back to `never`.

- **The tasks screen filters by assignee, and only in a shared circle.** Alone,
  the device has neither a user id nor a name to match on, so the Everyone/Mine
  control would only ever be empty and is not shown. The filter is not
  persisted: one that survives relaunch is one people forget is on, and what it
  produces here is a sibling concluding the family has nothing left to do.
  Today is deliberately *not* filtered (it answers "what is left for her", not
  "what is left for me"); it marks the reader's own rows with "You" instead.
  Assignment still notifies nobody, and the editor footer still says so.

- **An appointment is a `Visit` dated later than now.** There is no
  `isAppointment` flag and there should not be one: a second field could
  disagree with the date, and nothing is running at the moment an appointment
  becomes a past visit to flip it. `Visit.isUpcoming`, `Person.upcomingVisits`
  and `Person.pastVisits` are the only readings of that rule; Today shows the
  next seven days (`appointmentsDue`), the Timeline shows history only, and a
  time of day is stored only when one was actually chosen, because a visit
  written up from memory a fortnight later must not print "3:47 PM"
  (`Visit.hasTimeOfDay`). The older `Visit.nextAppointment` column is vestigial:
  it was never written by any screen, and a second place to put a date would be
  a second answer to "when is she next seen". Reminders fire at 6pm the evening
  before, out of the same 64-request budget as doses and refills, behind the
  same per-person toggle.

- **A medication is stopped, not deleted.** `Medication.stop()` clears it off
  the dose list, off the emergency card and out of the reminder budget while
  keeping the row and every `DoseLog` on it; `restart()` puts it back and
  clears `endDate`, which is what the Timeline reads to say when it stopped.
  Deleting stays for a row entered by mistake, and its confirmation still says
  what goes with it. Before this the only way to clear a drug was to delete it,
  so "she came off warfarin in June" could not be recorded at all.

- **`Medication.weekdays` has a UI, and every schedule is rendered by
  `Medication.scheduleLabel`.** The column, the sync payload and the reminder
  planner carried weekdays from the start while no editor could set one and no
  screen printed one, so a weekly tablet was entered, displayed and handed to a
  nurse as a daily one. The medication row, the emergency card and the exported
  one-pager all read the one label; empty `weekdays` means every day and prints
  nothing.

- `Services/TodayDigest.swift` — what is outstanding for each person right now,
  as pure functions over the models. **The Today tab and the Care tab rows both
  render this one type**, so "2 due" cannot mean two things on two screens. It
  also owns the single refill rule (`runningLow`), which `TodayView` used to
  keep its own copy of. `statusLine` deliberately distinguishes "Nothing
  recorded yet" (a record with no medications) from "Nothing due today" (a day
  already dealt with): collapsing those tells a caregiver their setup is
  finished and their morning is clear when neither is true. Every line is a
  statement about a list, never an assessment of anyone (I6).

- **Today has an Everyone mode, and it only exists at two people or more.** A
  solo caregiver sees exactly the screen they always have: no header, no picker,
  no aggregate. With more than one person the default scope is `.everyone`,
  because opening on one of them is how Dad's overdue 8am dose stayed invisible
  to somebody looking at Mom. Everyone mode is not the per-person screen
  repeated N times: the setup checklist and quick-action row are per-person jobs
  and stay there, doses and tasks are actionable in place (having to switch
  person to tick off Dad's tablet is the problem being fixed), and refills and
  bills are counts because they are errands for later in the week. People with
  nothing outstanding are listed under "Nothing due today" rather than dropped —
  a person who vanishes off the daily screen reads as a record that has gone
  missing.

- `Services/CareOverview.swift` — the feature catalog (`CareFeature`: title, blurb,
  symbol, colour), the per-tile count lines, and `SetupChecklist`. One list, read by
  the person hub, the Today quick actions and the People rows, so a feature cannot
  be added in one place and go missing in the other two. Copy here is always a
  statement of what is recorded, never an assessment (I6). `QuickAction.todayRow`
  is the Today tab's six chips: meds, tasks, bills, Medical, notes, contacts. Six,
  not seven, because the seven-chip row ran off the right edge, so its last entries
  were effectively not in the app. Anything new goes behind Medical, not into the
  open row; a unit test asserts the row plus `QuickAction.medical.members` still
  reaches every feature except check-in. **Medical pushes `MedicalRecordView`, it
  does not drop a menu**: every other chip pushes, and one tap gesture producing
  two kinds of thing reads as a mis-tap. That screen renders `.medical.members` as
  tiles, so the chip and the screen cannot drift. Check-in stays out of the row,
  but Today does carry a check-in *status* section once one is enabled for the
  person: setting it up is a hub job, "has she pressed it today" is a daily one,
  and it was two taps away on another tab.

- **The setup checklist leads the Today tab, and dismisses per row.**
  `SetupStepPreferences` (per person, per `SetupStep.Kind`) is the row-level
  dismissal; `SetupCardPreferences` is the whole-card Hide. Putting it first is
  only fair because both exist, so anything that makes it harder to dismiss has to
  move it back down. `PersonDetailView` and Settings → "Set up … again" restore
  every dismissal; `PeopleView`'s "3 of 6" line counts the *visible* steps so the
  two screens agree.

- **Card rows use `listRowInsets(leading: 0, trailing: 0)`.** The section is
  already inset by the inset-grouped list; a further 16 made every card in the app
  visibly narrower than the plain list sections beside it.

- **Today offers an undo for anything ticked off there.** A dose stays on screen
  and is corrected through the status menu; a task or a bill leaves the section
  the instant it is marked, so `UndoBanner` holds it for seven seconds. Doses
  were forgiving of a mistap and the other two were not, with nothing on screen
  saying so.
