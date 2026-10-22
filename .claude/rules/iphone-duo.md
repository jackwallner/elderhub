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
  Search results are still local to `PeopleView`.
- Each pane gets `horizontalSizeClass = .compact` and
  `horizontalToolbarInPane(true)` (iOS 27.1 `toolbarVerticalBehavior(.disabled)`),
  so it lays out as on a phone with its back button leading.
- Still across the fold: onboarding (the root before any person exists) and the
  form sheets (editors, paywall), which present as centred sheets.
- Unattended captures: `-uitest-family YES -seedDemo YES -DuoTour` plus
  `-DuoTourFirst`, `-DuoTourStep`, `-DuoRoutes`, `-DuoRoutesRegular` (see
  `DuoScreenshotTour`). `DUOTOUR` and `DUOGEOM` lines in app.log map shots to
  routes and record the measured fold. `simctl openurl` raises an alert on
  iOS 27, so the tour runs on a timer and gh-sim's `--url noop://N` only paces
  the screenshots.
