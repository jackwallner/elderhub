---
paths:
  - "Shared/Services/DoseReminderScheduler.swift"
  - "Shared/Services/NotificationService.swift"
  - "Shared/Services/NotificationRoute.swift"
  - "Aging/Views/Components/NotificationPermission.swift"
  - "AgingTests/DoseReminderTests.swift"
  - "AgingUITests/DoseReminderToggleUITests.swift"
---

# Elderhub: reminders, routing and notification permission

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

- **A dose reminder is one notification per person per dose time, not per
  medication.** Per medication the request count grows with the drug list, and
  three people on six medications each overflowed the device's 64 pending
  requests, silently dropping the evening. Grouped, it grows with people x
  distinct dose times. The identifier no longer names a medication, so
  `DoseReminderScheduler.apply` diffs on the **body** too: adding a tablet to
  the 8am slot has to rewrite the request already there. What still does not fit
  is counted (`DevicePlan.droppedCount`) and printed under the reminders toggle,
  because a caregiver who thinks a reminder is set when it is not is worse off
  than one who knows.

- **Reminders route to the person they name.** Every dose, refill and
  appointment request carries `personID` in `userInfo`;
  `NotificationService.didReceive` puts it on `NotificationRoute.shared` and
  Today consumes it. Before this there was no `didReceive` handler at all, so
  tapping "Dad: Warfarin" opened wherever the app was left, which with two
  people is the wrong record about half the time.

- `Views/Components/NotificationPermission.swift` is the **one** place that
  decides what a reminder toggle does when iOS refuses. All three dose-reminder
  toggles (Today's checklist, the person hub, onboarding) route through it.
  `requestAuthorization` returns false *without showing a prompt* once the app
  has been denied, which is the common case, so all three used to flip the
  switch back and say nothing: no prompt to answer, no hint that the answer is
  in iOS Settings, and a caregiver concluding the app is broken.
  `Outcome.blocked` is the case that gets the alert and the Settings link. The
  preference is still put back, because the reminder genuinely will not fire.
