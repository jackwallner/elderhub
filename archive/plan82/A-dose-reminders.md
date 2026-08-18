# A. Dose reminders

## Why this is first

`aso-plan.md` lists "reminders per person, with mark taken on their behalf" as v1
core. It is not built. `grep` for `UNNotificationRequest` across `Shared/` and
`Aging/` hits only `CheckInService`: the app stores schedules and never fires a
single local notification for them. Every slice after this one hangs off the
scheduler you are about to write.

## Goal

Local notifications for scheduled doses, per person, offline, no group required (I3).

## Read only these

- `Shared/Services/ScheduleEngine.swift`: whole file. Slots already come from here;
  do not duplicate its logic.
- `Shared/Services/CheckInService.swift:120-160`: the existing
  `UNCalendarNotificationTrigger` pattern. Copy its shape.
- `Shared/Services/NotificationService.swift`: authorization + delegate live here.
- `Shared/Models/CareModels.swift:99-200`: `Medication` only.
- `Aging/Views/TodayView.swift`

## Build

**`Shared/Services/DoseReminderScheduler.swift`** (new)

- A pure function `requests(for:on:) -> [ReminderSpec]` mapping medications to
  `(personName, medName, hour, minute, weekday?)`. Pure so it is testable without
  `UNUserNotificationCenter`. Everything hard goes here.
- A thin actor that diffs desired specs against pending requests and adds/removes.
  Reschedule on: app foreground, medication save/delete, person delete.
- `UNCalendarNotificationTrigger(dateMatching:repeats: true)`. Hour + minute when
  `weekdays` is empty, plus `weekday` when it is not. Identifier
  `dose-<medID>-<minutes>-<weekday>` so a diff is cheap and idempotent.
- `isAsNeeded` medications are never scheduled.
- Inactive (`isActive == false`), ended (`endDate` in the past), and soft-deleted
  (`deletedAt != nil`) medications are never scheduled.

**The 64-request limit is the actual engineering problem.** iOS keeps only 64 pending
local notifications per app. Three people × 6 meds × 3 times/day × specific weekdays
blows past it silently and the failure mode is "some reminders just never fire".
Cap deterministically: sort by next fire time, take the first 64, and reschedule on
every foreground so the window rolls forward. Assert the cap in a test.

**Body copy** names the person, because this app is multi-person and that is the
differentiator: `"Mom: Metformin 500mg"`. No em dashes in shipped copy; use a colon.
Never imply harm from a missed dose (1.4.1).

**Per-person toggle**, device-local in `UserDefaults` keyed by person id. Reminders
are a property of *this phone*, not of the shared record, so this is deliberately not
synced and deliberately not a migration. A caregiver and a sibling should not be
forced into the same notification settings.

Wire the toggle into the person's row in `PeopleView` or `PersonDetailView`, whichever
already has a settings affordance. Do not add a tab.

## Tests

`AgingTests/DoseReminderTests.swift`: empty `weekdays` means every day; specific
weekdays produce one spec per day; as-needed and inactive produce none; the 64 cap
holds and is stable across two calls with identical input.

## Verify

`agent-sim checkout aging`, build + all tests against the returned UDID, screenshot
the person detail toggle, `agent-sim checkin aging`.

## Commit

`feat(reminders): schedule local dose notifications per person`

Flip row A to `done` in `archive/plan82.md` in the same commit.
