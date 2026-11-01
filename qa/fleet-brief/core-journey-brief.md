# Core-feature journey brief (fleet run)

You are adding regression coverage for this app's core feature to its release gate.
The gate runs `ReleaseJourneysUITests` once per persona
before every App Store submission: newcomer, AX3 large text, Reduce Motion, German when
localized, and now an iPhone Duo unfolded (two-pane layouts). It also runs the app's unit
tests and blocks on any failure.

Today the journeys mostly prove screens load. They rarely prove the feature works, so a
regression in the core loop (a log that does not save, a timer that does not finish, a
streak that does not count, data gone after relaunch) ships. Fix that for this app.

## Do

1. Read AGENTS.md and the app's main views to find its core loop: the one or two things a
   customer opens the app to do (log an entry, run a routine, track a count, read a
   briefing). Read the existing `ReleaseJourneysUITests.swift` and its helpers.
2. Add one journey, `testCoreLoop...`, that does that loop as a user would on a fresh
   install (or the seeded data the other journeys use) and asserts the outcome, not just
   that a screen appeared: the new entry is listed with the value entered, the count went
   up, the summary shows the finished run, and it is all still there after
   `QA.relaunch(app)`. Call `QA.checkpoint(app, "<name>")` after each visible step, like
   the other journeys. If a helper calls `QA.checkpoint`, give the helper a
   `journey: String = #function` parameter and pass it through so findings carry the test
   name, not the helper's.
3. The same journeys run on an iPhone Duo unfolded, where some apps show two panes or a
   sidebar instead of a tab bar. Write queries that work in both (find by accessibility
   identifier or label, not by position or tab index). Swipe with `QA.swipe(element, .left)`
   (`.right`, `.up`, `.down`), never `swipeLeft()` or `swipeUp()`: on the unfolded Duo the inner
   display is rotated against the device and XCTest's swipes land as vertical drags. Where
   the app has no Duo layout, nothing changes.
4. Make the app's unit tests pass (`<App>` scheme). If one fails because the app is wrong,
   fix the app; if the test is stale against an intended change, update the test.
5. When `gh-sim` is installed, prove it on a GitHub Mac (public repos only), one run at a time:
   `gh-sim test --scheme <App>UITests --only <App>UITests/ReleaseJourneysUITests`, then
   `gh-sim test --scheme <App>` for the unit tests, then the journeys again with
   `--device "iPhone Duo"`. Fix until all three pass. Never pass secrets to gh-sim.
6. Rerun `xcodegen generate` if you add or remove a Swift file.
7. Commit as `test(qa): core <feature> journey asserts <outcome>` (and `fix:` commits for
   app fixes). Commit only files you changed. Do not push.

## Do not

- Change the app's design or copy to make a test pass.
- Add sleeps longer than the existing helpers use, or retry loops that hide a failure.
- Touch qa/gate.json, qa/ledger.jsonl, qa/backlog.jsonl, FleetQA.swift, signing, the
  version or build number, or anything under fastlane/ and docs/.
- Configure the production RevenueCat `appl_` key on a simulator.

End with three lines: the core loop you covered, what the journey asserts, and the
gh-sim run ids that passed.
