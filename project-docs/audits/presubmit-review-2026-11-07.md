# Elderhub pre-submit review, 1.0.6 (build 49), 2026-11-07

Scope: app sources (`Aging/`, `Shared/`, `project.yml`) from the live App Store build to HEAD.
App Store Connect shows 1.0.5 READY_FOR_SALE with build 45 attached, so the base is
`48c1e4a` (chore: bump build 44 to 45), not the last 1.0.5 commit `2282d45` (build 46,
never shipped). 42 files, about 730 lines added. Docs, fastlane, qa and tests excluded.

Checked: SwiftData models (no schema change in range), the new `Clearable` DTO wrapper
(encode and decode of missing, null and present keys), sync keep-local and conflict-hold
rules, check-in settings write and the moved check-in reminder, DST dose placement and
dedupe, one-shot reminder diffing, refill and vital `Int` traps, the membership removal
wipe, the Back Up circle creation, paywall (only colour changes; Restore, Terms and
Privacy still in the footer), DEBUG-only Duo tour, and copy for health claims, other
platforms and hard-coded prices.

| # | Severity | Location | What happens | Status |
|---|---|---|---|---|
| 1 | P0 | `Shared/Services/GroupService.swift:293` | New in this range: an empty `group_members` answer on a phone with a cached circle is treated as a removal and runs `forgetGroupLocally`, which deletes every person, the cursors and the whole outbox. supabase-swift falls back to the anon key when it cannot produce an access token (a refresh the auth server refused or rate limited while the REST call still goes through), and RLS answers an anonymous query with no rows. A still-valid member then loses the circle on that phone and every write made offline that had not been sent. | Fixed: the wipe only runs when the query was made with this account's own unexpired session. Test `anonymousEmptyAnswerKeepsTheCircle`. |
| 2 | P1 | `Shared/Services/CheckInService.swift:208`, `Aging/RootView.swift:61` | 1.0.5 scheduled the repeating "Let them know you're OK" reminder on whichever phone saved the check-in window, which was a caregiver's. 1.0.6 moved arming to `CheckInHomeView` (the person's own phone) and nothing on a caregiver's phone ever calls `scheduleReminder` again, so after the update caregivers keep getting a daily "Tap to check in" with no way to stop it, even by turning check-ins off. | Fixed: the caregiver root clears the reminder unless one of the records on the phone is this account's own. Test `caregiverPhoneHoldsNoOwnRecord`. |
| 3 | P2 | `Aging/Views/CheckIn/CheckInHomeView.swift:166` | The person's own phone now asks for notification permission from the Today screen on first appearance once a window is set, rather than from a settings action. Acceptable (it is the screen the reminder is for), noted for review screenshots. | Not fixed: intended behaviour. |
| 4 | P2 | `Aging/Views/PaywallView.swift:403` | The "included" check moved from `.green` to a fixed dark green, which is low contrast on the dark-mode paywall. Visual only. | Not fixed: design change, out of scope. |

No other crash, data-loss, purchase or App Review issue found in the range. Health copy
has no treat, cure or diagnose claim; no Android or Google Play reference; no prices in
copy (all come from StoreKit); the Duo screenshot tour is compiled only in DEBUG.
