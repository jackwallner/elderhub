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
- Split, there is no bar at the bottom of either pane. The system tab bar is
  hidden on every tab (`systemTabBarHidden`) and the same three tabs run as a
  strip across the top of the leading pane (`PaneTabStrip`, `PaneTabChrome`),
  so both lists run off the display's bottom edge. iOS 27.1 lays a pane's bar
  row into the inner display's 82 pt status band, so the strip is an overlay
  centred on that row (48 pt), and the `TabView` gets 12 pt of top padding: a
  stack whose frame stops short of the top safe edge puts its bar below the
  band. `safeAreaPadding` did not (run 3: the strip hid Everyone and Rename).
  Don't stack the strip above the `TabView` in a `VStack` that ignores the top
  safe area: the `TabView` expands back to the top and draws over it (run
  shift-duo-elderhub-3, capture 2 had no tabs at all). A pane is
  only 669 pt tall, and every way of keeping a bottom bar was rejected by the
  visual review: rows crisp through the glass, a fade above the bar (sliced
  the row on it), a blur under it (the row on it still half covered). Same
  fix that passed Hockey and Baseball. Folded the strip has zero height and
  stays in the tree, so folding rebuilds nothing.
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
  `shift-duo-elderhub-2-1792805567` (`duo-run.sh`, `TZV=<zone>`). Run it in the
  foreground (a background Bash task); backgrounding it with `&` inside a
  shell that exits kills the gh-sim client after dispatch.
