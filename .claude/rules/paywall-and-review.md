---
paths:
  - "Shared/Services/StoreService.swift"
  - "Shared/Services/ReviewPrompt.swift"
  - "Shared/Services/RemoteConfig.swift"
  - "Aging/Views/PaywallView.swift"
  - "Aging/Views/TodayView.swift"
  - "Aging/Services/Products.storekit"
  - "AgingTests/ReviewPromptTests.swift"
  - "AgingTests/ReviewMomentTests.swift"
  - "AgingTests/RemoteConfigTests.swift"
  - "AgingTests/PurchaseNoticeTests.swift"
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

- **A purchase that did not go through is a `PurchaseNotice`, not RevenueCat's
  text.** Ask to Buy (`paymentPendingError`) reads "Waiting for approval. Your
  purchase unlocks once it is approved." in secondary colour; no connection
  reads the paywall's own App Store line; anything else keeps the store's
  words in red. The notice clears on a new attempt and on choosing another
  plan, because it takes the slot of the plan's required disclosure. An
  approval lands later through `customerInfoStream` (observed from
  configuration on, which also catches renewals and lapses while the app is
  open), and an open paywall closes once Plus arrives.

- **Wording tests go through RevenueCat offering metadata, not releases.**
  `RemoteConfig` reads `offerings.current.metadata`; `TrialCTA` (`trial_cta`:
  `seven_day` control, `my`, `your`) words the paywall's trial button and is
  only used while the account is trial-eligible. The control is the shipped
  "Start My N-Day Free Trial". Set any switch key the same on every offering.
  DEBUG captures pin a key with `-elderhub.rc.<key> <value>`.

- Ratings: no in-app rating question (App Review 5.6.1). `ReviewPrompt` is the
  tracker. The one good moment, and the only automatic ask: on Today, a dose
  taken, task done or bill paid that leaves **nothing outstanding for anyone
  today** (`ReviewPrompt.isGoodMoment`: every `PersonDigest.isClear`; a skipped
  or missed dose never counts). The system `requestReview()` follows about 3s
  later only if Today is still the screen showing (not another tab or a pushed
  screen) and nothing is presented over it, from the 2nd cold launch with a
  30-day cooldown stamped at the call. A blocked ask is skipped and the next
  moment asks. RevenueCat offering metadata `rating_prompt: off` pauses it
  (`RemoteSwitch.ratingPrompt`). Never on the recipient's phone (that
  root is `CheckInHomeView` and never reaches Today). This is a Medical-category
  app opened by worried people: an ask in front of an overdue 8am dose is worse
  than never asking. Settings > Feedback has separate "Rate Elderhub" (ends the
  asks) and "Send Feedback" rows; feedback goes to `SupportMail`
  (`Aging/Support/SupportMail.swift`), which prefills version, build, iOS,
  person count and sync state and deliberately carries nothing from the record
  (I5). Sending feedback never stops the asks.
