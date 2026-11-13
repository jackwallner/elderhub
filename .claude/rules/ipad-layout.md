---
paths:
  - "Aging/RootView.swift"
  - "Shared/Utilities/ReadableColumn.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "AgingUITests/IPadTourUITests.swift"
  - "project.yml"
  - "Aging/Info.plist"
---

# Elderhub: iPad layout (1.0.7)

iPad support is free: `TARGETED_DEVICE_FAMILY "1,2"`, all four orientations
(`UISupportedInterfaceOrientations~ipad`), Split View and Slide Over allowed
(never `UIRequiresFullScreen`). Once a version ships with iPad the idiom can
never be removed, so every screen has to be checked there before a build.

- **The Duo split is phone only.** `UnfoldedSplit.make` fires on regular width
  and a wide container, which an iPad satisfies, so `RootView` also requires
  `userInterfaceIdiom == .phone`. An iPad keeps the one adaptive layout: the
  native `TabView` (top tab bar on iPadOS 18+), Care as a stack, never two
  phone-width panes. Do not lift that gate.
- **Full-screen roots that are not lists** (onboarding, Transparency, the
  recipient's check-in home) are wrapped in `.readableColumn(maxWidth: 600)` in
  `RootView`; pushed scroll screens (the emergency card) apply
  `.readableColumn()` to the content inside the `ScrollView`, so the scroll bar
  stays at the screen edge. Narrow widths (iPhone, Split View) are unchanged.
- Every tab and every screen pushed from it keeps one column on iPad:
  `RootView` sets `.contentMargins(.horizontal, padColumnMargin, for:
  .scrollContent)` once on the `TabView` (680 pt column, zero on iPhone and in
  narrow Split View). Lists are NOT readable-width on their own (inset grouped
  runs edge to edge on a 13-inch), so do not wrap or re-cap them per screen.
- The paywall is page-sized on iPadOS 18+ (`PadPageSheet`), its pinned purchase
  area capped at 600 pt; the default form sheet cut the Yearly card off.
  Other sheets stay centred form sheets.
- Sheets inherit the root `.contentMargins`, so a sheet that sizes its own
  content must reset it (`.contentMargins(.horizontal, 0, for: .scrollContent)`,
  as the paywall does).
- iPad frames come from `AgingUITests/IPadTourUITests.swift`, because gh-sim
  cannot rotate a simulator: `gh-sim test --scheme AgingUITests --only
  AgingUITests/IPadTourUITests --device "iPad Pro 13-inch (M5)"`, frames in
  the run's `attachments/`, portrait and landscape each. Frames use the window
  screenshot; in landscape the simulator returns it as a portrait buffer turned
  a quarter clockwise, so rotate `-land` frames upright (PIL `rotate(90)`). It reuses the DEBUG
  `-DuoScreen <route>` routes (an iPad is never split, so a route lands as it
  does folded on a phone). Split View widths are a manual check.
- The store set is 13-inch iPad (2064x2752), built from those captures with
  the same headlines as the iPhone set. `testStoreFrames` walks the hub for the
  medications (the hub's own list), tasks and appointments frames, because a
  `-DuoScreen` route does not reliably land there. Shipped in the 1.0.7 train.
