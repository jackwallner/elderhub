---
paths:
  - "Shared/Services/StoreService.swift"
  - "Shared/Services/ReviewPrompt.swift"
  - "Aging/Views/PaywallView.swift"
  - "Aging/Views/Components/ReviewPromptSheet.swift"
  - "Aging/Services/Products.storekit"
  - "AgingTests/ReviewPromptTests.swift"
  - "AgingTests/PaywallFunnelTests.swift"
  - "AgingUITests/PaywallRenderUITests.swift"
---

# Elderhub: the paywall and the review prompt

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

- `Services/StoreService.swift` — RevenueCat. `identify()` ties the RC customer to
  the Supabase user id; without it the billing webhook has no group to credit.
  **The paywall has three states, not two.** `isLoadingPlans` / `hasNoPlans` /
  loaded, backed by `loadFailure` and `hasAttemptedLoad`. A failed offerings
  fetch used to be logged and nothing else, so the sheet rendered a bare
  `ProgressView` forever, and this app is opened with no signal by design, which
  makes that the ordinary case rather than the exotic one. Restore stays
  reachable in every state.

- `Services/ReviewPrompt.swift` and `Views/Components/ReviewPromptSheet.swift`
  are the rating funnel and the gate on it. **Never asked on a day with anything
  outstanding for anyone** (`PersonDigest.isClear` for every person, and at
  least one person with something recorded), never before several distinct days
  of real use, and never on the recipient's phone (that root is
  `CheckInHomeView` and never reaches Today). This is a Medical-category app
  opened by worried people: an "is Elderhub helping?" card in front of an
  overdue 8am dose is worse than never asking. Yes goes to Apple's prompt and is
  recorded as a *soft* defer, because that prompt frequently shows nothing; no
  goes to `SupportMail`, which prefills version, build, iOS, person count and
  sync state and deliberately carries nothing from the record (I5).
