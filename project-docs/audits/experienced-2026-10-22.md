# Elderhub experienced persona audit

Date: 2026-10-22. Persona: someone who has used Elderhub for months and repeats the same jobs daily (tick off the morning doses, log a blood pressure, add a recurring errand, restock a bottle, pay a bill, find an old note) and goes looking for the faster or deeper way to do each.

Method: `AgingUITests/ExperiencedAuditUITests` (7 walks) on a GitHub Mac (iPhone 17, iOS 27.0, Xcode 27.1) against the public demo fixture (`-seedDemo -uitest-family -uitest-wipe-store`: Mom and Dad, two years of vitals and visits, tasks, bills, a two-person circle). Run 1: 6 passed, 2 failed (both failures were walk-script problems: an ambiguous element query and a sheet that never opened, not app defects; they were fixed in the committed test and rerun, see "Rerun" below). 37 screenshots and the control logs are in `~/fleet-evidence/shift-audit-elderhub-experienced-1-1792690106/` (`screenshots/`, `control-logs.txt`). Each finding is labelled RUNTIME (seen in a screenshot or measured in the control log) or SOURCE (read from code only, not exercised). Motion and frame rate were NOT measured (no video, by design). Fixture artifacts (all "started" timeline entries dated today, Mom and Dad both under "Only on this phone", every vital at the same clock time) are ignored.

Not repeated from earlier audits: onboarding and first dose (`newcomer-2026-10-22.md`), sign-out, revocation, emergency-card parity (`paudit91.md`). Not walked: paywall, restore, Sign in with Apple.

## Findings

### E-01 (P1, RUNTIME) With one person on the phone, the first screen of Today has no dose on it
`20-today-mom-first.png`: with Mom selected the screen is the setup card ("4 of 6 done", two rows) and the six 128 pt chips. The control log reads `Taken buttons on Mom's first screen: 0`. Scrolling (`21`, `22`) gives Tasks, then Appointments, then "Today's doses" last. Everyone mode (`01`) is the opposite and right: three Taken buttons on the first screen. So a family of two gets the fast screen and the solo caregiver, who is the common case, gets the slow one. An experienced user has long finished setup and is still asked to scroll past it every morning (it only goes away if each row is dismissed or Hide is found).
Fix: doses first in the per-person screen, same order as Everyone mode; fold the chip grid into one 64 pt icon row below the doses; collapse the setup card to one line once the person has a medication.

### E-02 (P1, SOURCE with RUNTIME absence) As-needed medications can be listed but never logged
The seed has Acetaminophen as "As needed". It appears on the hub (`32`) and the emergency card (`73`) but on Today it appears nowhere (`01`, `20` to `22`: only Lisinopril and two Metformin doses). In code `Medication.isScheduled` returns false for as-needed, `ScheduleEngine` makes no slot for it, and nothing writes a `DoseLog` for it, so there is no "gave a dose now" action. `daysRemaining` returns nil for as-needed too, so Track refills on a PRN bottle never warns. A repeat user's most common PRN questions are "did anyone already give her a Tylenol today and when?" and "how many are left?", and neither can be answered from the app; the sibling at the next phone cannot see it either.
Fix: a "Give a dose" row per as-needed medication on Today that writes a timestamped `DoseLog` (who, when), shows "last given 2:10 PM by Dana", and counts down on-hand stock.

### E-03 (P2, RUNTIME) Logging a blood pressure is six taps and two field taps, every time
Today, Medical chip (1), Vitals tile (2) (`40`), plus (3) (`41`), tap Systolic (4), type, tap Diastolic (5), type, Save (6) (`42` to `44`). `Keyboard up on open: false`: the sheet opens with no field focused and a large blank area. The decimal pad has no Next or Done key (`43`), so moving to Diastolic is a tap on a 129 pt field. The second reading straight after (`45`) is an empty sheet again; nothing is remembered. Save is a 62x36 pt capsule (control log, below 44).
Fix: focus Systolic on open, add a keyboard toolbar with Next and Done, jump to Diastolic after three digits, and put "Log BP" on the Today chip row or the Vitals tile so the common reading is two taps. Keep the kind picker on the last kind used.

### E-04 (P2, RUNTIME + SOURCE) 53 readings and no trend, summary or search
`41`: Vitals is a flat newest-first list of 53 values. No latest, 30-day average, range or sparkline; the project does not import Charts at all. The Timeline (`63`) has a single "Filter" menu and no search field (`timeline.search-field: MISSING`). In code `loadWindow` fetches only non-taken doses, so the Timeline cannot show that a dose was taken, and "Load earlier history" widens only the dose and check-in window, not visits or vitals. What this app is for, answering a doctor's "how has her pressure been", means scrolling and reading.
Fix: a header above the list (last, 30-day average, high/low) with a small Charts line for the selected kind; a search field on Timeline; include taken doses in a "Doses" filter.

### E-05 (P2, RUNTIME, rerun confirmed) The cross-record search is hidden until the list is pulled down
`65-care-tab.png`: no search field under the "Care" title and `searchFields` matched nothing (`care.search-field: MISSING`), although `PeopleView` declares `.searchable` (prompt "Meds, allergies, people, tasks, contacts, notes") and the code comments call it a feature (plan82 slice F). A power user cannot find the fastest route to "that note about the side door". Rerun: pulling the list down reveals it (`r2-65b`, field 370x44), and it works: 'hearing' returned 6 rows across tasks, a medication and a symptom note (`r2-66`). So the feature exists but nothing on the resting screen says so.
Fix: confirm the field renders on iOS 27 inside the tab bar's glass layout; if it only appears on pull-down, pin it (`.searchable(placement: .navigationBarDrawer(displayMode: .always))`) or add a visible search button.

### E-06 (P2, RUNTIME + SOURCE) The Tasks screen's tick-off circle is a bare glyph with no undo; Today's is not
`50-tasks-list.png`: the circle is roughly 20 pt (about 46 px of a 920 px wide image at 402 pt). `CareTasksView.TaskRow` has no frame, while `TodayTaskRow` (same app) was explicitly given `minWidth: 44, minHeight: 44` for exactly this reason. Completing from the Tasks list also calls `markComplete` with no undo bar, and the follow-up occurrence of a recurring task is created at once; the way back is the collapsed "Done N" header (the "N" reads as a count, not a button) and Reopen, which deliberately does not remove the follow-up. Bills (`60`) has the same shape: Paid is a leading swipe only, no visible control, no undo.
Fix: reuse the Today row (44 pt target and `offerUndo`) on the Tasks and Bills screens.

### E-07 (P2, RUNTIME) An overdue dose looks exactly like a due one
`01` at 6:12 PM: Lisinopril 8:00 AM, Metformin 8:00 AM and Metformin 7:00 PM are three identical rows. Overdue is told only by the headline count and a small orange dot on the person header. In `DoseRow` there is no per-row state. Someone deciding "is the 8 AM Metformin still safe to give now, or should I skip it" has to compare clock times by hand.
Fix: an orange "Overdue 10 hours" caption on overdue rows, and keep "Skip" visible (it is swipe-only today).

### E-08 (P3, SOURCE) A dose can only be recorded as taken "now"
`record(_:for:person:)` stamps `recordedAt = Date()` and `DoseRow` shows only the status word and the recorder's name. Logging at noon for an 8 AM dose a parent took cannot be given its real time, and the status line does not say when it was recorded. Fix: show "Taken 8:05 AM by Dana" and let the status menu set the time.

### E-09 (P2, SOURCE) Restocking a bottle means opening the editor and retyping the on-hand number
`RefillRow` on Today is not tappable, no "Refilled" action exists (`quantityRemaining` is written only by dose ticks and the editor), and the "Running low" row has no way to say "picked up 90". Not exercised at runtime (the demo fixture has nothing low: `mom.running-low-row: MISSING`). Fix: tap the row for "Picked up: + 30 / 60 / 90 / type".

### E-10 (P1, RUNTIME in rerun) A one-off bill defaults to repeating monthly, and typing 45 in Amount gives $450.00
`BillEditorSheet` initialises `recurrence = .monthly` and `hasDueDate = true`, so a dentist invoice entered by typing a payee and amount repeats next month once marked paid (footer: "Marking this paid adds the next one automatically"). The amount field is a currency-formatted `TextField(value:format:)`, a known awkward control with the decimal pad. Rerun, `r2-67`/`r2-68`: the New Bill sheet opens with Due date on (today) and Repeat 'Every month'. Control log: `Amount field value after typing 45: $450.00`; the field starts as '$0.00' and typed digits are inserted at the tap point, so the cursor sits inside the string (`r2-68`). A caregiver typing a $45 bill can save $450 with no warning (caveat: XCUITest taps the field centre; a real thumb may land at the end, but the pre-filled '0.00' makes the failure easy to hit). Fix: default Repeat to Never, start the Amount empty with a placeholder (or select-all on focus), and show the formatted value only after editing ends.

### E-11 (P3, RUNTIME) Repeat is hidden until a due date is switched on
`54-task-editor-scrolled.png`: only Due date, Priority and Who's doing it; Repeat appears after the toggle. A weekly errand takes two extra steps and the missing field reads as no recurrence support. Fix: show Repeat disabled with "Set a due date first" or switch the due date on when Repeat is chosen.

### E-12 (P3, RUNTIME) Today forgets who you were looking at
`80`/`81`: after picking Mom and relaunching, Today opens on Everyone (`everyone-headline` present, three Taken buttons). Deliberate (an overdue dose for Dad must not hide), but a caregiver who looks after one parent most days re-picks every launch. Fix: remember the last person and show a one-line "Dad has 1 dose due" strip when somebody else needs attention.

### E-13 (P3, RUNTIME) Small controls on repeat screens
Control log: emergency-card Share 38x36 pt, Vitals Save 62x36 pt, Today person picker 90x36 pt (Apple's floor is 44). In `73` the pharmacy phone link wraps centred while the other links are left aligned.

### E-14 (P3, RUNTIME) The Everyone headline reads as a sentence of counts
`01`: "2 doses overdue · 2 doses due · 2 tasks · 1 appointment · 2 to sort out" wraps to two lines at the largest text on the screen and "2 to sort out" does not say what. Fix: lead with the actionable item ("2 doses overdue for Mom") and drop the rest to a smaller line.

## What worked (RUNTIME)
- Everyone mode puts the three Taken buttons, with strength and time, on the first screen (`01`); a two-person family gets the morning round in three taps.
- The hub and Medical tiles say what they are for and carry live counts ("53 readings", "Next: Oct 26 at 10:15 AM") (`30`, `40`).
- Today's task circle is a 44 pt target and gives an undo bar (SOURCE: `TodayTaskRow`, `UndoBanner`).
- Medication editor supports weekdays, several times, duplicate-time warnings and stop-without-delete (SOURCE: `MedicationEditorSheet`).
- Vitals list round trip works: the new 128/82 appeared at the top of the list after save (`44`).
- The emergency card is complete and honest, with CALL FIRST and tap-to-call (`73`).

## Not measured / limits
- Frame rate and animation smoothness: not measured here. Keyboard and sheet screenshots (`42`, `43`, `45`) show no layout collision, but a settle-time judgement needs a device.
- Medication editor, task recurrence, restock and PRN paths were read from source, not walked, except where a finding says RUNTIME.

## Rerun
Run 2 (gh-sim run 39832550592, Morning round, Hub and editors, Bills/notes/timeline/search): 2 passed, 1 failed (`testExperiencedHubAndEditors`: `Failed to tap "Cancel" Button` after the new-medication steps; the same control log shows `med-editor.cancel` hittable at 76x36 earlier in the walk, so this is a script fault, probably a Cancel button hidden by an open confirmation or focus state, not an app defect; unresolved and not re-run for lack of time). Records: `test-summary-run2.json`, `test-run2-get.json`, control logs `control-logs-run2.txt`, PNGs `screenshots/r2-*`.

- E-05 and E-10: updated above.
- E-15 (P3, RUNTIME) Tapping Taken removes the row from the pending list with no confirmation (`r2-05`: Lisinopril vanished from Mom's group; control log `everyone.undo-banner-after-dose: MISSING`), whereas marking a task done shows an Undo bar (`r2-10`, Undo 60x44). SOURCE: undo for a dose lives in the recorded row's status menu or a swipe (`TodayView.swift:1281-1342`), neither visible after the tap. A mistap on the busiest button in the app has no obvious way back. Fix: reuse `offerUndo` for dose records.
- E-16 (P3, RUNTIME) Care search results repeat the title as the subtitle for tasks and medications (`r2-66`: 'Replace hearing aid batteries' twice, 'Hearing Aid Batteries size 312' then 'Hearing Aid Batteries'). Fix: show the notes or schedule line, or nothing.
- Confirmed OK: Today's task circle is 44x44 and gives an Undo bar (`r2-10`); the New Bill sheet's Save stays disabled until a payee is entered (`r2-67`); the new-medication sheet shows Track refills (`r2-37`) and the Time picker (87x36). `new-med.weekday-mon` was MISSING in the control log: not investigated (weekday chips may sit below the fold).

Time and queue: run 2 sat on GitHub from the previous attempt and finished in 27m38s. Nothing was left in flight. Frame rate not measured.

## Next action
Fix E-01, E-02, E-03 and E-10 first (they decide whether the daily loop is fast and whether PRN doses are safe), then E-05 (find out why search is missing), E-06 and E-07. The walks are rerunnable: `gh-sim test --scheme AgingUITests --only AgingUITests/ExperiencedAuditUITests`.
