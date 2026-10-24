---
paths:
  - "Aging/RootView.swift"
  - "Aging/Support/AppNavigator.swift"
  - "Aging/Support/DuoScreenshotTour.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "Aging/Views/PeopleView.swift"
  - "AgingTests/UnfoldedSplitTests.swift"
---

# Elderhub: iPhone Duo (2026-10-21)

- Unfolded (regular width, room for two panes of at least 360 pt), `RootView`
  puts the native `TabView` (Today, Sharing, Settings, tab bar inside it) on the
  leading side of the fold and Care (people, the person hub and everything it
  pushes) on the trailing side; the Care tab drops out of the tab bar there.
  Fold edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split. Same shape as Vitals.
  Folded, the four-tab phone layout is unchanged.
- The `TabView` is never rebuilt on fold or unfold, so Today, Sharing and
  Settings keep their scroll and pushed screens. Care has to move between the
  tab bar and its own pane, which builds a new `PeopleView`, so its stack lives
  in `AppNavigator` (`carePath`, `careHub`) and reopens where it was. Anything
  pushed from the Care stack must go through those, or it is lost on unfold.
  A hub built with `careHub` already set does not push it
  (`navigationDestination` follows changes only), so
  `PersonDetailView.reopenRestoredRoute` clears and rewrites it on appear.
  Search results are still local to `PeopleView`.
- Each pane gets `horizontalSizeClass = .compact` and
  `horizontalToolbarInPane(true)` (iOS 27.1 `toolbarVerticalBehavior(.disabled)`),
  so it lays out as on a phone with its back button leading.
- Still across the fold: onboarding (the root before any person exists) and the
  form sheets (editors, paywall), which present as centred sheets.
- The floating tab bar sits inside the leading pane, which is only 669 pt
  tall, so some rows are always under it. Both ways of hiding that were
  rejected by the visual review: rows crisp through and around the glass, and
  (2026-10-23) a list masked to end in a fade above the bar, which sliced the
  row sitting on it. `blursUnderTabBar(_:)` lets the rows run under the bar to
  the display edge under an ultra-thin material washed 60% toward grouped
  background. It starts only 6 pt above the bar (`TabBarEdgeBlur.leadIn`) and
  is full 10 pt into it (`settle`): a 28 pt lead-in still faded the last line
  of the row on the bar. No fade toward the fold: the wash matches the band
  there, and a fade let a blue Taken button show through beside the bar. The
  same 6 pt bottom content margin keeps the last row clear of it. Folded it is
  invisible and stays in the tree, so folding rebuilds nothing.
- iOS 27.1 draws the inner display's status bar (time, wifi, battery) in the
  trailing pane's navigation-bar row; the bar moves its trailing items clear of
  it. System behaviour, nothing is under it, but it leaves a pushed screen with
  two trailing buttons about 100 pt for its title. `EmergencyCardView`
  truncated to "Emergency..." there, so in a pane (`\.isUnfoldedPane`) it
  drops the bar title (`barTitleInContent`) and its header carries it. Check
  any new screen with a long title and two trailing items the same way.
- Unattended captures: `-uitest-family YES -seedDemo YES -DuoTour`, plus one
  gh-sim `--screen "-DuoScreen <route>"` per surface (`DuoScreenshotTour`):
  gh-sim relaunches the app per `--screen` and shoots it folded and unfolded.
  Folded, a route naming a person opens it on the Care tab. The hub is pushed
  first and its screen 1.5 s later: both in one update pushed the screen
  mid-push and the pane drew it blank. `medications` and `healthDetails` are
  not pushed screens (the hub lists meds; details is a sheet), so never use
  them as a route. Give gh-sim `--wait 15`: a cold relaunch on the runner
  took longer than 6 s and left outer shots blank. Without
  `-DuoScreen`, `-DuoTour` walks `-DuoRoutes`/`-DuoRoutesRegular` on a timer
  (`-DuoTourFirst`, `-DuoTourStep`); pass a long step so the launch shot holds
  still. `DUOTOUR` and `DUOGEOM` lines in app.log map shots to routes and
  record the measured fold. With `-DuoTour` the seeded circle is Sarah and
  Jack, the names on the sample tasks. Seed timestamps are first-launch time
  and every sample dose reads overdue after 8 AM, so pick gh-sim
  `--env TZ=<zone>` so the launch lands between about 6 and 7:45 local. Dad's
  record is deliberately sparse, so captures use Mom. Never use `--url`
  (iOS 27.1 raises an "Open in" alert) or made-up URLs (`noop://N`).
  The capture command is in the evidence folder of fleet run
  `shift-duo-elderhub-1-1792799687` (`duo-run.sh`).
