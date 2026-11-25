---
paths:
  - "Shared/Services/StoreService.swift"
  - "Shared/Services/ReviewPrompt.swift"
  - "Shared/Services/RemoteConfig.swift"
  - "Aging/Views/PaywallView.swift"
  - "Aging/Views/TodayView.swift"
  - "Aging/Services/Products.storekit"
  - "AgingTests/ReviewPromptTests.swift"
  - "AgingTests/PaywallFunnelTests.swift"
  - "AgingUITests/PaywallRenderUITests.swift"
---

# Elderhub: the paywall and the review prompt

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here.

- `Services/StoreService.swift`: RevenueCat. `identify()` ties the RC customer to
  the Supabase user id; without it the billing webhook has no group to credit.
  **The paywall has three states, not two.** `isLoadingPlans` / `hasNoPlans` /
  loaded, backed by `loadFailure` and `hasAttemptedLoad`. A failed offerings
  fetch used to be logged and nothing else, so the sheet rendered a bare
  `ProgressView` forever, and this app is opened with no signal by design, which
  makes that the ordinary case rather than the exotic one. Restore stays
  reachable in every state.

- Ratings: no in-app rating question (App Review 5.6.1). `ReviewPrompt` is the
  tracker; Today marks a dose taken, task done or bill paid as the positive
  moment and calls the system `requestReview()` about 3s later only if Today is
  still on screen, nothing is presented and **nothing is outstanding for anyone
  today** (`ReviewPrompt.isGoodMoment`, `PersonDigest.isClear` for every
  person), from the 2nd launch with a 30-day cooldown. That is the only
  automatic trigger; offering metadata `rating_prompt: off` pauses it. A
  blocked ask stays pending. Never on the recipient's phone (that
  root is `CheckInHomeView` and never reaches Today). This is a Medical-category
  app opened by worried people: an ask in front of an overdue 8am dose is worse
  than never asking. Settings > Feedback has separate "Rate Elderhub" (ends the
  asks) and "Send Feedback" rows; feedback goes to `SupportMail`
  (`Aging/Support/SupportMail.swift`), which prefills version, build, iOS,
  person count and sync state and deliberately carries nothing from the record
  (I5). Sending feedback never stops the asks.

- Purchases: a pending payment (Ask to Buy) is `PurchaseError.waitingForApproval`,
  shown in grey in the disclosure slot, never as an error; network and offline
  errors read "We couldn't reach the App Store just now." Approval arrives
  through the `PurchasesDelegate` customer-info update, which unlocks without a
  relaunch and closes an open paywall. Any message is cleared when a plan is
  picked or a purchase starts, so the disclosure for the selected plan is back.

- Trial button wording is `TrialCTA` over offering metadata `trial_cta`
  (`Shared/Services/RemoteConfig.swift`). Control `seven_day` is the shipped
  "Start My \(days)-Day Free Trial"; an ineligible account keeps "Subscribe" /
  "Unlock Lifetime" in every arm. The arm shown is set as the `trial_cta`
  subscriber attribute.
