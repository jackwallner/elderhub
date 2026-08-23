# Elderhub audit823

Audit date: 2026-08-23

Scope: Elderhub only, `/Users/jackwallner/elderhub`.

This is a fresh max-reasoning rerun focused on downloads, trial starts, purchase conversion, user experience, operational visibility, release regression risk, legal and website consistency, and Cursor, Claude, and Codex agent hygiene. This file is the only requested output. No app code, configuration, metadata, script, commit, or push was changed.

## Executive verdict

Elderhub is in a prelaunch state. The available App Store Connect status is `Waiting for Review` for `Elderhub: Family Care Log`, app ID `6796916172`, version `1.0`. The public App Store URL returned HTTP 404 on 2026-08-23, which is consistent with an unpublished or not-yet-available listing. Downloads, ratings, trial starts, conversion, revenue, retention, and crash rates are therefore not measurable from the available evidence.

The product story is unusually coherent for a first release: one care record is free, the core experience is offline-first, helpers are free, and the app concentrates a family care circle around a Today screen, medication records, an emergency card, tasks, visits, vitals, and history. The seven screenshot concepts communicate that story well. The most important risks are below.

1. A local-only user can reach the additional-person paywall before having a Supabase identity or group. The purchase can succeed locally in RevenueCat, while the RevenueCat webhook intentionally ignores anonymous or no-group events. I did not find a later reconciliation path that attaches that purchase to a newly created group. This is a potential purchase-to-access integrity defect, not merely an analytics gap.
2. A production RevenueCat offerings or StoreKit failure can leave the paywall on an indefinite loading spinner. `StoreService` logs the failure but does not expose a retryable error state, and `PaywallView` renders only `ProgressView` when plans are empty.
3. The app has no native review request or feedback funnel, no MetricKit or crash service integration, and no product funnel telemetry found in the source. The first launch would have little ability to explain a conversion drop, a trial failure, or a release regression.
4. The current website is still explicitly prelaunch. Its download calls to action are non-clickable `Coming to the App Store` spans. That is correct while the listing is unavailable, but it must be changed before the first traffic or it will suppress downloads.
5. The submitted paywall screenshot appears stale relative to the current `PaywallView` implementation. The image says `Continue`, while the current source uses trial, lifetime, or subscribe-specific CTA text. Store screenshots should represent the reviewed build.
6. Store, local StoreKit, website, and setup scripts repeat price and product naming in several places. Prices are currently aligned in local evidence, but the live ASC and RevenueCat values were not independently verified in this rerun.
7. The canonical shared agent guide is healthy, because `AGENTS.md` symlinks to `CLAUDE.md`. There is no app-specific `.cursor` directory found at the repo root. Several root and research documents still use old Med List or Aging framing and can cause an implementation agent to follow superseded decisions.

The release recommendation is conditional: do not treat the app as conversion-ready until the identity and group billing edge case, paywall failure state, purchase and restore tests, review access path, and post-release observability are validated. The first-person value path can remain free and should remain free. The additional-person gate is the right monetization moment, but it must be technically safe and clearly explained.

## Evidence boundaries

### Observed

- Local Swift, SwiftUI, SwiftData, Supabase, RevenueCat, StoreKit configuration, XcodeGen, Fastlane, UI tests, website, legal pages, metadata, scripts, and documentation were inspected.
- The current local project identity is `Aging`, bundle ID `com.jackwallner.aging`, marketing version `1.0.0`, build `27`, with the customer-facing app name `Elderhub`.
- The ASC app record available in context is `Elderhub: Family Care Log`, ID `6796916172`, version `1.0`, status `Waiting for Review`.
- The public App Store URL `https://apps.apple.com/us/app/id6796916172` returned HTTP 404 on 2026-08-23.
- The GitHub Pages homepage and privacy, terms, and support URLs returned HTTP 200. The corresponding `jackwallner.com/ios/elderhub/` mirror URLs also returned HTTP 200.
- The submitted screenshot source set exists under `fastlane/screenshots/en-US` and contains seven 1320 x 2868 PNG files.
- No `requestReview`, `SKStoreReviewController`, MetricKit, Crashlytics, Sentry, Bugsnag, or comparable product analytics integration was found in the inspected source.

### Inferred from code

- The local-only purchase and group-billing edge case is inferred from the complete code path across onboarding, People, StoreService, and the RevenueCat webhook. It needs a device or StoreKit test that reproduces the exact sequence before being called a live incident.
- An empty paywall with no retry is directly visible in the code. Whether ASC, StoreKit, or RevenueCat will fail in production is not known.
- The screenshot and CTA mismatch is a direct comparison between the current source strings and the submitted image. It may be an intentionally old marketing capture, but it should not be submitted without confirming it represents the reviewed build.
- The effect of metadata changes on downloads is a hypothesis. No live impressions or conversion data was available.

### Unavailable

- No reliable Elderhub-specific downloads, product page views, trial starts, paid conversion, refunds, revenue, ratings, review text, retention, crash count, or RevenueCat dashboard metric snapshot was available in the local repo or accessible context.
- Fleet-level or other-app metrics must not be attributed to Elderhub.
- This audit does not treat a RevenueCat presence as a privacy disclosure inconsistency. The requested RevenueCat data-collection inconsistency review is explicitly out of scope here.

## Priority matrix

| ID | Priority | Finding | Evidence | Required next move |
| --- | --- | --- | --- | --- |
| ELD-01 | P0 if reproduced, otherwise P1 release blocker | A local-only user can purchase before identity and group creation, while the webhook ignores anonymous or no-group events. | `OnboardingFlow.swift`, `PeopleView.swift`, `StoreService.swift`, `revenuecat-webhook/index.ts` | Require identity before the monetized path, or implement and test purchase-to-group reconciliation. |
| ELD-02 | P1 release blocker | Empty RevenueCat offerings can become an indefinite paywall spinner with no retry or useful error. | `StoreService.refresh`, `PaywallView` plans-empty branch | Add explicit loading, unavailable, retry, and support states. Add failure injection tests. |
| ELD-03 | P1 release blocker | Review status and reviewer access are not fully proven by local files. Sharing requires account context, but review notes say no demo account is needed. | ASC context, `fastlane/Fastfile`, `review_information` | Confirm submitted build, regulated medical declaration, reviewer path, and whether sharing and purchase can be tested without an Apple ID. |
| ELD-04 | P1 | There is no crash, hang, launch, sync, purchase, trial, or webhook observability layer. | No MetricKit, crash SDK, or product analytics matches; only OSLog | Add privacy-preserving release telemetry and a configurable external watchdog before traffic. |
| ELD-05 | P1 | There is no native rating request, Store page rating action, or in-app feedback action. | No `requestReview` or `SKStoreReviewController` matches; no Settings rating action found | Add a value-gated review prompt, explicit Settings entry, and feedback route. |
| ELD-06 | P1 launch-day blocker | The landing page still has non-clickable `Coming to the App Store` spans and no live download URL. | `docs/index.html:532-556,830-836` | Replace both CTAs, nav, metadata, and structured data immediately after listing availability. |
| ELD-07 | P1 | Store screenshot 7 appears stale relative to current paywall CTA and trial wording. | `fastlane/screenshots/en-US/store-7-family.png` versus `Aging/Views/PaywallView.swift:90-110` | Regenerate screenshots from the final reviewed build and recheck prices, trial text, and CTA. |
| ELD-08 | P1 | Price and product names have multiple local sources of truth. | `Products.storekit`, ASC scripts, website JSON-LD, `StoreService`, setup scripts | Establish one canonical table and run a release drift check against ASC and RevenueCat. |
| ELD-09 | P1 or P2 | Legal contact uses the old `+medlist` alias throughout customer-facing pages after the Elderhub rename. | Privacy, consumer health, terms, support, and join pages | Confirm routing and replace with a neutral Elderhub support alias when ready. |
| ELD-10 | P1 | UI tests render the paywall but do not complete real purchase, restore, trial, or webhook propagation. | `AgingUITests/PaywallRenderUITests.swift`, StoreService simulator guard | Add StoreKit purchase and restore coverage, then device/TestFlight RevenueCat smoke tests. |
| ELD-11 | P1 | Medical App Store review and metadata declarations need live ASC confirmation. | `CLAUDE.md:238-251`, `Fastfile` review notes, Medical category | Confirm regulated medical device declaration and claims with the exact submitted build. |
| ELD-12 | P2 | Onboarding says `You can change this later`, but no equivalent path or persona switch was found. | `OnboardingFlow.swift:255-334` | Replace with precise copy or add a real path-switch route. |
| ELD-13 | P2 | A signed-out user sees no direct Sign in or backup action in Settings. | `SettingsView.swift:328-330` | Add a clear account and backup CTA without blocking local use. |
| ELD-14 | P2 | Group creation failure allows onboarding to continue without an obvious sharing recovery state. | `OnboardingFlow.createFirstPerson` | Surface incomplete sharing state, retry, and a clear recovery action. |
| ELD-15 | P2 | Only en-US store metadata was found. | `fastlane/metadata` has `en-US` plus review information only | Decide whether the launch is deliberately US English only and measure territory opportunity before localization. |
| ELD-16 | P2 | Root and research docs contain multiple old naming eras and dated audits. | `ios27Aging.md`, `aso-plan.md`, `docs/research`, SQL and function comments | Create a canonical agent reading order and move or label superseded material. |
| ELD-17 | P2 | Public screenshot assets contain plausible health records and a real-looking developer surname and phone number. | Screenshot 2 and other store assets | Confirm every value is synthetic, consented, and safe for permanent public distribution. |
| ELD-18 | P2 | Store page, canonical website, GitHub Pages URLs, and mirrored legal pages need a post-availability link audit. | `README.md`, `docs/index.html`, Fastlane URL files | Verify all links, canonical tags, app ID links, redirects, and deep links after approval. |

## 1. Release and App Store Connect baseline

### Current status

| Item | Current evidence | Assessment |
| --- | --- | --- |
| App Store Connect app | `Elderhub: Family Care Log`, ID `6796916172` | Correct customer-facing identity in available ASC context. |
| Current ASC status | Version `1.0`, `Waiting for Review` | Prelaunch. Do not interpret this as live availability or a healthy production funnel. |
| Public listing | `https://apps.apple.com/us/app/id6796916172` returned 404 on 2026-08-23 | Expected until availability, but must be retested after approval. |
| Local XcodeGen project | `project.yml`, name `Aging`, iOS 17, Swift 6, Xcode 16 | Internal names are stable identifiers, not necessarily customer-facing defects. |
| Local version | `project.yml:22-23`, `MARKETING_VERSION: 1.0.0`, `CURRENT_PROJECT_VERSION: 27` | Confirm ASC version `1.0` and build `27` are the submitted pair. |
| Bundle | `com.jackwallner.aging` | Keep stable. Do not rename the bundle to match the product name. |
| Category | Medical in local strategy and review notes | Confirm the live ASC category and regulated device declaration. |
| Store regions | Local docs say the app is not sold in EU or UK | Confirm ASC territory availability matches every customer-facing legal and marketing statement. |

### Release gates

Before approval:

1. Confirm ASC has build `27` attached to version `1.0`, the correct binary, correct screenshots, and the current metadata files.
2. Confirm the medical category and any regulated medical device declaration are complete. `CLAUDE.md:238-251` specifically calls out this declaration as required in ASC UI.
3. Confirm reviewer instructions are executable. `fastlane/Fastfile` says `No demo account required`, but sharing and group billing rely on sign-in and server state. A reviewer cannot create a new Apple ID during review.
4. Confirm the reviewer can reach the first-person experience, emergency card, Care, Sharing, and the additional-person paywall without needing an unavailable credential. If a server-backed path is required, provide a deterministic reviewer route or a review-safe test account.
5. Confirm all URLs in the review information and metadata return 200 from the production environment, not only from the local `docs` directory.
6. Confirm the submitted build uses the production APNs entitlement after archive export. `Aging/Aging.entitlements` contains `aps-environment: development`, with a comment that Xcode rewrites it during export. Inspect the exported archive rather than relying on the source entitlement.
7. Confirm no simulator or StoreKit testing configuration is present in the submitted archive. The `.storekit` configuration belongs to local run and test schemes only.

### Fastlane review-path risk

`fastlane/Fastfile` review notes describe a valid happy path: choose a path, optionally skip sign-in, finish setup, open Care, tap Add person, and inspect the Elderhub Plus paywall. The same notes say no demo account is required. The mismatch is not necessarily an App Review failure, but it is an unverified dependency:

- a user can remain local-only by skipping sign-in;
- Sharing and group state are server-backed;
- RevenueCat group propagation depends on a UUID user ID and a group membership;
- the reviewer cannot create an Apple ID or depend on a private invite.

Validation should explicitly demonstrate the complete claimed flow in a clean review environment. If the reviewer only needs to see the paywall, say so precisely. If the reviewer needs to test an actual purchase, restore, invite, or shared update, the current no-demo-account statement is not sufficient evidence.

## 2. ASC metadata and download conversion

### Metadata inventory

The only store metadata locale found is `fastlane/metadata/en-US`. The files are:

- `name.txt`: `Elderhub: Family Care Log`, 25 characters.
- `subtitle.txt`: `Meds, visits, vitals, check-in`, 30 characters.
- `keywords.txt`: `medication,dementia,alzheimers,memory care,pill,reminder,prescription,elder,parent,senior,medical id`, 100 characters by the local count.
- `description.txt`: 3,221 characters in 39 lines.
- `promotional_text.txt`: 145 characters.
- `marketing_url.txt`: `https://jackwallner.github.io/elderhub/`.
- `privacy_url.txt`: `https://jackwallner.github.io/elderhub/privacy-policy.html`.
- `support_url.txt`: `https://jackwallner.github.io/elderhub/support.html`.
- `release_notes.txt`, category files, copyright, and review information.

The field lengths are within the familiar ASC limits for name, subtitle, keywords, description, and promotional text. Recheck character counts using the exact ASC validation behavior before upload, especially punctuation, apostrophes, and whitespace.

### What is strong

- The title makes the family-care use case explicit and keeps the product name visible.
- The subtitle covers concrete record types rather than generic health language.
- The description leads with the non-obvious distinction: the user may be tracking somebody else's care, not their own pills. That is a clear positioning statement.
- The description explains the free boundary, family helper model, offline behavior, subscription renewal, and legal links.
- The promotional text has a direct emotional and functional message: one care circle, family invites, all features for the first person, and offline access.
- The Medical category and health-oriented terms are aligned with the actual feature set, subject to ASC review.

### Search and positioning hypotheses

`CLAUDE.md:238-251` records a deliberate strategy not to depend on broad App Store search terms such as `caregiver`, `senior care`, or `home care`, because local research found limited search demand and substantial competition. It instead identifies a `dementia` cluster and `medical id` as opportunities. The current keyword file reflects that strategy.

This is a hypothesis, not a measured outcome. Once the listing is live, track product page views and downloads by territory and source. Do not infer that a keyword is successful from rank alone. The primary question is whether the product page converts the right user into first-person activation and then into a second-person intent.

Specific checks:

- `alzheimers` is a sensitive term and should only remain if the app's content and review positioning can support the intent without implying diagnosis, treatment, monitoring, or clinical efficacy.
- `medical id` is a strong intent term for the emergency card, but the emergency card must be reliable, understandable, and clearly presented as user-maintained information rather than a clinical system.
- `elder`, `parent`, and `senior` may be broad. Test whether replacing one with a care-circle or medication-record term improves qualified conversion. Do not change several terms simultaneously without a measurement plan.
- The app title collision with ASC app `Elder Hub`, ID `1589043147`, is documented in `CLAUDE.md`. The name is defensible, but monitor search result confusion, support requests, and review references to the other app. A brand or subtitle distinction may be safer than relying on spelling alone.

### Description improvements

The description is complete but can be made more conversion-oriented without adding unsupported claims:

1. Keep the first three lines focused on the highest-value moment: a family member can see what was taken, what is due, and what matters in an emergency.
2. Put the one-person-free boundary immediately after the first value paragraph. Users should understand the paywall before investing in a long feature list.
3. Use consistent vocabulary for `care record`, `care circle`, `helper`, and `person`. The source alternates between person, subject, recipient, supporter, caregiver, and family helper because the product supports different roles. Customer copy should choose a small set of terms.
4. Make the offline promise precise. The app supports local use and later sync, but shared updates and invitations need identity and network access. Avoid wording that implies every collaborative feature works without connectivity.
5. Retain the medical disclaimer and avoid any claim that the app prevents missed doses, detects emergencies, diagnoses conditions, or replaces professional advice.
6. Add a direct App Store link after availability, then validate that the `marketing_url` page and the app page agree on product name, pricing treatment, availability regions, and screenshots.

### Screenshot review

The source set is under `fastlane/screenshots/en-US`, not under the metadata text directory. All seven files are 1320 x 2868 PNGs, suitable for the 6.9-inch class source size used by the project.

Observed sequence and message quality:

| Asset | Visible message | Conversion role | Review |
| --- | --- | --- | --- |
| `store-1-checkin.png` | `Mom checks in, family sees the update` | Distinctive family benefit | Strong opening. It shows an immediate, understandable outcome. |
| `store-2-emergency.png` | `Everything a doctor asks for, on one screen` | Emergency card and information density | Useful, but validate the wording against medical review expectations. It can sound more complete or clinical than the product can guarantee. |
| `store-3-today.png` | `Know what was taken, and who marked it` | Shared accountability and Today | Strong proof of the core record model. Check text size and scroll context on the actual store crop. |
| `store-4-medications.png` | `One medication list, kept properly` | Medication organization | Clear feature proof. The visible dose-reminder toggle is off, which may under-sell reminder value. |
| `store-5-tasks.png` | `Nobody calls the pharmacy twice` | Family task coordination | Memorable benefit, but confirm it does not imply an outcome the app cannot guarantee. |
| `store-6-timeline.png` | `Two years of history, without the shoebox` | Historical record and visits/vitals | Strong concept. Confirm the data is synthetic and that the app does not imply a guaranteed two-year retention duration. |
| `store-7-family.png` | `Every feature free for one person` | Paywall and pricing | Important conversion proof, but the CTA appears stale versus current source. |

### Screenshot-specific blockers

The last screenshot displays a paywall with `Continue`, monthly `$9.99`, yearly `$39.99`, lifetime `$89.99`, and a one-week trial disclosure. Current `Aging/Views/PaywallView.swift:90-110` builds CTA text from state:

- `Start My N-Day Free Trial` for an eligible subscription;
- `Unlock Lifetime` for lifetime;
- `Subscribe` when there is no trial.

The asset therefore does not match the current source unless the screenshot came from a different intentionally reviewed UI. Recreate it from the final build and confirm:

- the selected default plan is the same;
- the CTA includes the correct eligibility state;
- the price is localized by the StoreKit product rather than a stale hardcoded value;
- the trial disclosure, renewal language, Terms, Privacy, and EULA are visible or correctly represented;
- the screenshot does not expose an old app name, old price, old product, or unsupported trial promise.

The emergency screenshot contains names, medications, conditions, blood type, a phone number, and an emergency contact. Treat every value as public forever. Confirm that `Eleanor Wallner`, `Jack Wallner`, all health data, and the `(555) 010-4477` number are synthetic or explicitly cleared for public use. The fact that the data resembles a realistic record is good for comprehension but increases privacy and trust risk if any value is real.

### Download landing page

`docs/index.html` is a clean prelaunch page with:

- title `Elderhub: Family Care Log - Shared Medication & Medical Records for iPhone`;
- a MedicalApplication JSON-LD object;
- local price offers of `$9.99`, `$39.99`, and `$89.99`;
- a one-week trial claim for subscription offers;
- feature sections for check-ins, medications, emergency card, tasks, history, sharing, and offline use;
- an explicit one-person-free and family-helper model.

The page also contains a clear implementation comment at approximately `docs/index.html:532-535` saying that the download spans and JSON-LD should be replaced when the app is live. The current hero and bottom CTA use non-link spans such as `Coming to the App Store` at approximately `docs/index.html:546-556` and `830-836`.

This is appropriate before approval. It becomes a direct conversion blocker immediately after approval. The launch patch should:

1. Replace every download span and nav link with an App Store URL containing app ID `6796916172`.
2. Add an `apple-itunes-app` smart app banner where appropriate.
3. Add `downloadUrl` to JSON-LD and verify that the structured data still validates.
4. Preserve UTM parameters through the App Store link where possible and log source at the landing page if an analytics system is introduced.
5. Add a visible fallback for users outside supported territories, because the legal pages say EU and UK availability is excluded.
6. Make `join.html` use a direct app link once available. The current page tells users to search the App Store for Elderhub, which is a poor fallback after listing approval and an impossible one before approval.

The store metadata points to GitHub Pages, while `docs/index.html` uses `https://jackwallner.com/ios/elderhub/` for canonical and Open Graph URLs. `CLAUDE.md:277-290` says the two sites are mirrored. This is workable, but choose and document one canonical public marketing URL. Confirm that both hosts serve identical current HTML, preserve all legal paths, and do not generate conflicting canonical or social preview metadata.

## 3. First-run onboarding and activation

### Current state machine

`Aging/Views/Onboarding/OnboardingFlow.swift` defines distinct paths for:

- `supporter`, somebody keeping track of another person;
- `subject`, a person joining or being represented in a care record;
- `solo`, a person keeping track of themselves.

The flow includes path selection, sign-in, name, details, join code, transparency, joined overview, and feature overview. `RootView.swift` routes to onboarding when no people exist and onboarding is not complete.

The architecture has a good first-use principle: the user can skip sign-in for supporter and solo paths and can get a local record. That supports the offline-first promise and reduces first-screen account friction. It also creates the identity and billing risk described in ELD-01.

### Activation path analysis

| Stage | Current behavior | Strength | Risk or opportunity |
| --- | --- | --- | --- |
| Path choice | Three clear choices in `OnboardingFlow.swift:255-334` | Role-specific language is better than a generic account wall. | `You can change this later` implies a path switch that was not found. |
| Sign in | Sign in with Apple primary; email is feature-gated; skip available except joining | Keeps local use possible and uses a trusted account option. | Users may not understand that a local record is not shared or backed up until they sign in. |
| First name | Supporter uses `Their name`; solo uses `Your name` | Low cognitive load. | Validate Dynamic Type, VoiceOver labels, and name privacy copy. |
| Details | Eight steps, all skippable, with visible progress | Lets the user create a useful record without completing every field. | Eight screens before the full value reveal may create abandonment. Measure each step. |
| First record | Local record is created before details | Good for offline resilience and early activation. | If cloud group creation fails, the user proceeds without clear sharing recovery. |
| Feature overview | Shows records, sharing, and `Share when ready` | Helps explain breadth after setup. | It does not give a clear, contextual next action toward the second-person value or trial. |
| First useful screen | Today, Care, Sharing, Settings tabs | Strong information architecture. | A new user may not know whether to add a medication, emergency card, check-in, or helper first. |

### Onboarding improvements

1. Replace `You can change this later` with a true statement, such as `You can add another person or invite helpers later`, unless a path-switch action is added.
2. Define and measure activation as a sequence, not merely `onboarding complete`. A strong candidate is: first person created, one meaningful care record added, first Today action or emergency card viewed, then a second-person intent or invite intent.
3. Add a single explicit next action after the feature overview. For a supporter, this could be `Add the first medication` or `Open today's care plan`; for a solo user, it could be `Set up your first reminder`. Keep the additional-person purchase out of the first-person core path.
4. Consider progressive disclosure for the eight detail steps. Keep the emergency card and medication setup prominent, but defer optional providers, visits, bills, and family details until after the user has seen the Today screen.
5. If notification permission is denied, show a recoverable Settings route and explain the consequence without implying the care record is broken. `OnboardingDetailsFlow.swift:435-445` currently disables reminders after denial.
6. When group creation fails, show `Your record is saved on this phone. Sharing is not finished.` with `Retry sharing`, `Continue offline`, and a way to sign in later. Do not silently make the user believe the care circle exists.
7. Add a signed-out explanation before the first share or invite action. It should say that account creation enables cross-device and family sharing, while local use remains available.

### Invite and join flow

`docs/join.html` is a load-bearing invitation page, and `CLAUDE.md` says its path must remain exact. The page uses `elderhub://invite?code=...` and offers App Store search instructions. Validate the following in a clean device flow:

- invite link opened before the app is installed;
- App Store install, then return to the invite context;
- app already installed and link opened from Safari or Messages;
- invalid, expired, already-used, and revoked invite codes;
- user not signed in, then Sign in with Apple, then join;
- joined user sees the correct person and role without accidental local-data overwrite;
- family helper sees and updates the expected records;
- joining does not incorrectly show the additional-person paywall.

The join flow is both a download funnel and an activation funnel. Record invite page visits, app opens from invite, sign-in completion, join success, and time from invite creation to acceptance. Do not record the invite code, care names, medications, or free-form notes in analytics.

## 4. Trial, purchase, and paywall funnel

### Current offer model

The source shows a deliberate model:

- first care person is free;
- all care features are included for that first person;
- additional care people require Elderhub Plus;
- family helpers are free and do not consume a seat;
- subscription plans are monthly and yearly;
- lifetime is a non-renewing purchase;
- monthly and yearly subscriptions have a one-week introductory trial for eligible users;
- the paywall is reached from `PeopleView` when the user attempts to add a second person.

The local product IDs are in `Shared/Services/StoreService.swift:108-112`:

- `com.jackwallner.aging.pro.monthly`
- `com.jackwallner.aging.pro.yearly`
- `com.jackwallner.aging.pro.lifetime`

The local StoreKit catalog is `Aging/Services/Products.storekit`. It has monthly `$9.99`, yearly `$39.99`, lifetime `$89.99`, and a one-week free introductory period for the subscriptions. `scripts/asc-set-iap-prices.py` and `docs/index.html` repeat the same US launch values. These local values are aligned. They are not proof that the live ASC and RevenueCat offerings are aligned.

### Paywall strengths

`Aging/Views/PaywallView.swift` has several good conversion and trust decisions:

- trial language is based on `store.eligibleTrialDays`, rather than blindly claiming a trial;
- the selected plan defaults to yearly and falls back to the first available plan;
- monthly, yearly, and lifetime plans explain renewal or no-renewal behavior;
- price, period, auto-renewal, cancellation timing, Apple subscription settings, Terms, Privacy, and EULA are visible;
- Restore Purchases is present;
- the body explains the family circle, no seat fees for helpers, and feature inclusion;
- `safeAreaInset` keeps the footer and CTA visible;
- error and cancellation states are at least represented in the purchase and restore code.

### ELD-01: local-only purchase before group identity

This is the highest-risk static finding.

Observed code path:

1. `OnboardingFlow.swift` allows supporter and solo users to skip sign-in. `SignInView.swift` also exposes `Not now` for non-joining paths.
2. The first person can be saved locally. `OnboardingFlow.createFirstPerson` creates a remote group only when the signed-in path has the required identity.
3. `PeopleView.swift:163-174` allows Add person when the account is unlocked or the current person count is below the free limit. Once the local user has one person, the second-person attempt opens `PaywallView` even if the user is not signed in.
4. `StoreService.identify()` calls RevenueCat `logIn` only when the service is configured and a Supabase user ID exists. A local-only user has no UUID identity at this point.
5. `StoreService.purchase()` can still purchase through RevenueCat on a configured device. The local device can receive `store.isPro` immediately from RevenueCat.
6. `SupabaseFunctions/revenuecat-webhook/index.ts` validates a UUID `app_user_id`, ignores anonymous events, looks up owner or caregiver group membership, and ignores events with no group.
7. I did not find a later reconciliation path that takes a purchase made before sign-in or group creation and attaches it to the newly created group. `GroupService.refreshBilling` reads the group billing record populated by the webhook, but does not prove replay or purchase migration.

Likely result: the payer's current device appears unlocked, while other family devices and the future group may remain unentitled. The purchase could be valid in App Store billing but absent from the app's group access model. This is especially dangerous because the user may believe they bought family access and only discover the inconsistency after inviting somebody.

Preferred fixes, in descending safety:

- Require sign-in and a valid group before entering the additional-person purchase flow. Preserve local first-person use, but make the transition explicit: `Sign in to share and add another person`.
- Or, create the group before the purchase and retain a pending billing handoff that is completed after `logIn` and group membership are established.
- Or, implement an idempotent server-side reconciliation endpoint that receives the verified RevenueCat customer or transaction identity after sign-in, resolves the user and group, and writes group billing. Do not trust a client-only entitlement flag.
- Make accountless purchase a deliberate supported mode only if the product can later transfer or reconcile the purchase safely. Test reinstall, device transfer, restore, account creation after purchase, and group creation after purchase.

Required validation scenarios:

| Scenario | Expected result |
| --- | --- |
| Local-only user adds second person and taps paywall | Clear sign-in requirement, or a purchase that is safely attached to a group. |
| Local-only user purchases, then signs in | Existing purchase is reconciled exactly once and group access becomes visible. |
| Local-only user purchases, then reinstalls | Restore identifies the same Apple purchase and does not create duplicate or orphaned access. |
| Signed-in group owner purchases | Owner and eligible group members converge on Plus after webhook delay. |
| Caregiver or subject attempts purchase | Behavior is intentional, documented, and not silently ignored by the webhook. |
| Purchase completes before webhook arrives | UI shows a pending sync state or retries; it does not imply all members are already unlocked. |
| Refund, expiration, pause, renewal, and transfer | Device entitlement and group billing converge according to the documented policy. |

### ELD-02: indefinite loading on offerings failure

`StoreService.refresh()` catches production errors and logs them with `Logger`, but does not expose a failure state or a retry action. In `PaywallView`, the plans-empty branch renders a `ProgressView` with accessibility ID `paywall.loading`. If the offerings request fails, the user can remain on a spinner with no explanation, no retry, and no alternate support route.

This can directly reduce trial starts and create support contacts that look like a pricing or Apple billing issue. It is also hard to detect without telemetry.

Required states:

- loading, with an accessible progress label;
- loaded, with plans and eligibility state;
- unavailable, with an explanation that the App Store could not load plans;
- retrying, with disabled duplicate actions;
- restored or already entitled;
- no eligible trial, clearly distinct from product load failure;
- purchase failed, cancelled, pending, or succeeded;
- restore no purchase, restore failed, and restore succeeded.

The unavailable state should offer `Try again`, `Restore Purchases`, and a support link. It should not show a hardcoded price or allow a purchase using a partially loaded plan.

### Trial eligibility and clarity

`StoreService.introEligibility()` checks actual RevenueCat introductory eligibility for products with an introductory discount, and `PaywallView` hides or changes trial claims until eligibility resolves. This is technically honest, but the pending state needs careful copy. A user should not see a generic `Start My 7-Day Free Trial` button, tap it, then discover that the trial is unavailable after an account or store check.

Validate:

- new Apple account, eligible subscription;
- previously trialed Apple account, ineligible subscription;
- monthly eligible and yearly ineligible combinations;
- restore from a current subscription;
- expired subscription with trial no longer eligible;
- family sharing or transferred purchase behavior if supported;
- locale-specific price, currency, period, and trial wording;
- offline launch and network recovery while eligibility is unresolved.

Use the product's localized price and period everywhere in the live UI. Keep website prices framed as starting or illustrative values if the app can vary by territory.

### Paywall UX details

Current opportunities in `PaywallView.swift`:

- The screen is invoked by an additional-person attempt, but the context should say exactly what the user was trying to do, such as `Add another person to this care circle`.
- The yearly default may be commercially sensible, but it should be tested against monthly default and a neutral default. Record selection before purchase.
- The lifetime plan is visually comparable to subscriptions. Test whether it clarifies value or distracts from the trial path. Keep the no-renewal disclosure prominent.
- The CTA varies by selected plan and trial state. Test explicit CTA copy against generic `Continue`, but do not hide the price or make the user take an extra step to discover it.
- Restore is available, but the screen should explain that restore is for an existing Apple purchase and does not create a new trial.
- `Text("·")` separators in the footer can be read awkwardly by VoiceOver. Verify the full paywall with accessibility labels rather than relying on visual punctuation.
- The error message can remain in view after a paywall is reopened unless it is reset deliberately. Clear stale errors on a new impression and retain the underlying failure for telemetry.
- The `TrialTimeline` says the App Store reminds the user before a trial ends. Verify this wording for every offer, locale, and Apple policy version. Do not imply Elderhub controls Apple's reminder.
- The plan loading state is the largest functional problem. Visual polish is secondary until it can recover from a product load failure.

### Paywall is custom, not RevenueCat hosted UI

The app uses the RevenueCat SDK for offerings, entitlements, purchase, and restore, but the visible paywall is a custom SwiftUI view in `Aging/Views/PaywallView.swift`. I did not find RevenueCat's hosted or native Paywalls component in the inspected source.

This matters for experimentation. RevenueCat dashboard paywall experiments cannot be assumed to apply to this custom screen. Current experiment surfaces are code-owned:

- headline and subtitle;
- plan order and selected plan;
- trial and eligibility copy;
- CTA label;
- benefit order;
- lifetime anchor treatment;
- loading, error, restore, and legal footer layout;
- when the screen is invoked;
- whether identity is required before purchase.

If hosted RevenueCat Paywalls are desired, treat that as an architecture choice and revalidate accessibility, legal disclosure, custom family messaging, and the local StoreKit testing path before replacing the current view.

## 5. RevenueCat and custom attributes

### Current integration

`Shared/Services/StoreService.swift` contains:

- API key `appl_dvyPWLaZxKyjLUrFVzDynNGjVGb` in `RevenueCatConfig`;
- primary entitlement `Aging+`;
- fallback entitlements `pro` and `AgingPro`;
- product IDs for monthly, yearly, and lifetime;
- `Purchases.shared.logIn(userID.uuidString)` after Supabase identity is available;
- customer info refresh, offerings load, intro eligibility, purchase, restore, and entitlement application.

The production key is excluded for simulator runs in `configureIfNeeded`, which is correct and must remain true. Never use the production `appl_` key in a simulator or StoreKit render test.

`GroupService.refreshBilling()` reads group billing and caches entitlement, expiry, lifetime state, and source. The RevenueCat webhook writes group billing for qualifying events and keeps access through cancellation until the period expires. That policy should be documented as a tested invariant.

### Naming drift

The code and configuration contain several naming eras:

| Surface | Name |
| --- | --- |
| Customer-facing app | Elderhub |
| Internal Xcode scheme and bundle | Aging, `com.jackwallner.aging` |
| Primary RevenueCat entitlement | `Aging+` |
| Fallback RevenueCat entitlements | `pro`, `AgingPro` |
| ASC setup script reference group | `Med List Pro` |
| ASC setup script display group | `Elderhub Plus` |
| Local StoreKit group name | `Aging Pro` |
| Legacy function and SQL comments | `Med List (Aging)` |

Stable internal IDs do not need to be renamed. The problem is the absence of an explicit canonical table. A new agent could create a fourth product or entitlement instead of preserving the live identifiers. Add a current naming table to the canonical project guide in a future documentation change. Do not change product IDs, entitlement IDs, bundle IDs, or subscription group IDs solely for branding.

### Custom attributes not found

No RevenueCat custom attribute writes were found in the inspected source. That is not a defect by itself. Attributes should be sparse, non-sensitive, and used only to diagnose funnel state. Do not send medication names, diagnoses, conditions, allergies, vitals, care notes, names, free text, invite codes, or raw email addresses.

Candidate attributes, only after identity is known:

| Attribute | Values | Why useful | Safe insertion point |
| --- | --- | --- | --- |
| `onboarding_path` | `supporter`, `subject`, `solo` | Compare activation and purchase behavior by intended role. | `OnboardingFlow` path selection, then set after `StoreService.identify`. |
| `account_state` | `local_only`, `signed_in`, `group_member`, `group_owner` | Detect local-only paywall and sharing friction. | `StoreService.identify`, group refresh, and sign-out clearing. |
| `group_role` | `owner`, `caregiver`, `subject`, `none` | Explain billing and invite behavior without health content. | After `GroupService` membership load. |
| `group_size_bucket` | `0`, `1`, `2-3`, `4+` | Measure the additional-person value moment. | After group cache refresh. |
| `paywall_trigger` | `second_person`, `settings`, `other` | Compare contextual paywall performance. | Before `PeopleView` presents Paywall and any Settings upgrade route. |
| `trial_eligibility` | `eligible`, `ineligible`, `unknown`, `error` | Separate offer failure from true ineligibility. | After `StoreService.introEligibility`. |
| `last_paywall_variant` | Stable experiment ID | Attribute an outcome to one variant. | At paywall impression. |
| `app_version` | Marketing version | Segment regressions by release. | On identify and app activation. |
| `build_number` | Build string | Segment release candidates and hotfixes. | On identify and app activation. |
| `locale` | Locale identifier | Detect localized price or copy problems. | On identify, without recording location. |
| `notification_permission_state` | `authorized`, `denied`, `not_determined`, `restricted` | Explain reminder activation without health content. | After notification authorization result. |

Custom attributes should not become entitlement truth. RevenueCat customer info and the server-side group billing record remain the source of access decisions. Attribute writes must be rate-limited, asynchronous, and resilient to a missing account.

### Funnel events to add separately from custom attributes

If product analytics is introduced, use an event schema that omits health data:

- `onboarding_path_selected`
- `onboarding_sign_in_shown`
- `sign_in_completed`
- `sign_in_skipped`
- `first_person_created`
- `first_record_action_completed`
- `today_opened`
- `check_in_completed`
- `emergency_card_viewed`
- `invite_created`
- `invite_opened`
- `invite_accepted`
- `second_person_intent`
- `paywall_impression`
- `paywall_plan_selected`
- `trial_eligibility_resolved`
- `purchase_started`
- `purchase_succeeded`
- `purchase_cancelled`
- `purchase_failed`
- `restore_started`
- `restore_succeeded`
- `restore_no_purchase`
- `restore_failed`
- `group_billing_refresh_started`
- `group_billing_refresh_succeeded`
- `group_billing_refresh_failed`
- `review_gate_shown`
- `review_gate_accepted`
- `review_gate_deferred`

Recommended fields are event name, timestamp, app version, build, locale, onboarding path, account state, group role, paywall trigger, plan ID, trial eligibility, and error class. Do not include names, medications, diagnoses, vitals, note text, invite code, or raw user identifiers in event properties.

Exact insertion points:

- Path selection: `OnboardingFlow.swift:54-57`.
- Local first-person save: `OnboardingFlow.createFirstPerson`, approximately `204-237`.
- Add-person gate: `PeopleView.swift:163-174`, before presenting the paywall.
- Paywall impression and eligibility: `PaywallView.swift:191-200` and `StoreService.swift:247-284`.
- Plan selection: the plan row selection around `PaywallView.swift:304-370`.
- Purchase start, success, cancel, and error: `PaywallView.swift:372-383` plus `StoreService.purchase` around `311-320`.
- Restore result: `PaywallView.swift:286-301` and `SettingsView.swift:30-40`.
- Invite creation and join: `InviteSheet` generation and `JoinGroupView.join`.
- Group billing convergence: `GroupService.refreshBilling` around `320-356` and webhook write around `115-139`.

## 6. Ratings, reviews, and feedback

No match for `requestReview` or `SKStoreReviewController` was found. No in-app Settings action for rating or feedback was found in the inspected source. Because the app is not yet publicly listed, there is no current rating baseline, but adding a review funnel after launch should be planned now.

### Recommended review moments

Use a value gate, not a time gate. Candidate moments are:

1. After a first successful check-in that another family member can see.
2. After an emergency card is completed or exported successfully, provided the user is not in a crisis context.
3. After a user has completed several doses or tasks and returns to the Today screen.
4. After an invite is accepted and the user sees a shared update.

Do not ask immediately after a paywall impression, failed purchase, sync failure, sign-in failure, or emergency-card edit. A review prompt should have `Maybe later` or a natural dismissal path and should not block care work.

Recommended surfaces:

- StoreKit review request after a confirmed success event, subject to Apple's throttling.
- Settings action `Rate Elderhub` that opens the App Store page after availability.
- Settings or Support action `Send feedback` with a direct, privacy-conscious support route.
- A lightweight in-app question such as `Was Elderhub useful today?` can route positive users to the store and negative users to feedback, but avoid dark patterns, review gating, or suppressing legitimate criticism.

Validation:

- confirm the prompt never appears before a meaningful value event;
- confirm it is not repeated on every launch;
- test VoiceOver and Dynamic Type;
- test StoreKit review behavior in development and TestFlight, understanding that Apple controls display frequency;
- measure review gate shown, accepted, deferred, and feedback opened without storing care content;
- monitor rating volume and text by build after release.

## 7. Core UX and retention opportunities

### Today and care record

The app's strongest retention loop is a daily care action. The screenshots show a clear check-in button, medication status, tasks, and family updates. `RootView.swift` bootstraps group refresh, sync, notifications, and dose reminders on appearance and foreground transitions. This is a good foundation, but the following should be tested:

- cold launch offline with an existing local record;
- cold launch after data was changed on another device;
- foreground while a sync is in progress;
- duplicate taps on `Taken` or check-in;
- timezone and daylight-saving transitions for dose reminders;
- notification permission denied, revoked, or changed in Settings;
- user switches between people while Today loads;
- stale data labeling when the record has not synced;
- conflict resolution presentation that does not silently overwrite health data.

The user should always know whether a record is local, synced, pending, or conflicted. A small `last synced` indicator in Settings is useful, but critical record screens should surface stale or failed shared updates when that affects the user's expectation.

### People and the second-person moment

`PeopleView.swift` has a good monetization boundary: one person remains useful, and adding a second person is a natural indication of family value. The risk is discoverability. A user can complete the first record without understanding that Elderhub supports more than one person or that helpers are free.

Improve the bridge without gating the first person:

- show a low-pressure `Add another person` or `Invite a helper` affordance after first activation;
- explain `Your first care record is free. Helpers do not use a paid seat.`;
- when the second-person gate appears, preserve the name and intended action so the user does not feel they lost work;
- let a user back out to the care record without losing the draft;
- make the identity requirement explicit before purchase if that is the chosen fix for ELD-01;
- show whether the current user is the owner, helper, or subject before displaying billing language.

The People search prompt mentions meds, allergies, people, tasks, contacts, and notes. The current feature set also includes providers, visits, vitals, bills, conditions, and reminders. Consider whether the search affordance should mention the most important omitted terms or use a shorter generic prompt with searchable examples that rotate. This is a minor discoverability issue, not a launch blocker.

### Settings and account conversion

`SettingsView.swift:328-330` tells a signed-out user that everything stays on the phone. That is honest, but it leaves a high-intent account action hidden. Add `Sign in to back up and share` or equivalent, while preserving a clear local-only option. The copy must distinguish:

- local data on this device;
- signed-in data that can sync;
- group membership and shared access;
- RevenueCat purchase identity;
- deletion and account recovery.

Do not force account creation merely to inspect the first-person core. Require it only at the first operation that truly needs identity, such as invite, sharing, or safely attaching a multi-person purchase.

### Accessibility and content density

The paywall, emergency card, Today screen, and screenshot examples contain large text and high contrast, which is appropriate for a care context. Validate the actual UI rather than relying on screenshots:

- Dynamic Type through the largest accessibility sizes;
- VoiceOver reading order for plan rows, CTA, legal links, and `Text("·")` separators;
- touch target sizes for check-in, Taken, Add person, and emergency actions;
- high contrast and reduced motion;
- localization expansion even before adding locales;
- screen-reader labels that do not expose private health data in an unexpected context;
- portrait-only behavior on every supported iPhone size;
- keyboard and paste behavior for join codes and email sign-in.

## 8. A/B test and native paywall opportunity backlog

The current custom paywall means tests should be implemented as stable, named variants with one major variable per experiment. Do not start experiments until ELD-01 and ELD-02 are fixed and the purchase funnel is observable.

| Experiment | Control | Variant | Primary metric | Guardrails |
| --- | --- | --- | --- | --- |
| P1 contextual headline | `Add another person` | `Keep a second care record in the same family circle` | Paywall to trial start or purchase | First-person activation, dismiss rate, support complaints, refund rate |
| P2 plan default | Yearly selected | Monthly selected | Eligible paywall to paid conversion | Trial start, 7-day and 30-day paid retention, cancellation, lifetime mix |
| P3 plan order | Monthly, yearly, lifetime | Yearly, monthly, lifetime | Purchase conversion and revenue per paywall impression | Accessibility, price comprehension, refunds |
| P4 trial CTA | Current eligibility-specific CTA | Shorter `Start 7-Day Free Trial` where eligible | Trial start rate | Trial cancellation, paid conversion, complaint rate, no false trial claims |
| P5 lifetime anchor | Three equal cards | Yearly value emphasized, lifetime still visible | Revenue per paywall impression | Lifetime purchase rate, subscription conversion, refund rate |
| P6 trigger explanation | Paywall only after Add person | Add a pre-paywall explanation with `See plans` | Second-person intent to paywall and purchase | No first-person gate, no extra abandonment, no dark pattern |
| P7 identity timing | Ask for sign-in at paywall | Ask earlier before the second-person draft | Purchase integrity and trial conversion | Onboarding completion, sign-in completion, local-only retention |
| P8 feature overview | `Share when ready` | `Add a helper` plus `Add another person` | First invite or second-person intent | No pressure before first useful action |
| P9 product page first screenshot | Current check-in story | Emergency card or family update story | Product page to download conversion | First-person activation and correct audience quality |
| P10 landing CTA after launch | Direct App Store button | Direct button plus join-family explanation | Landing page to App Store click and install | Broken links, territory confusion, bounce rate |

Native or hosted RevenueCat paywall experiments should only be considered after confirming whether the project intends to adopt RevenueCat Paywalls. The current implementation does not use that component. If it stays custom, keep the experiment assignment local and deterministic, persist the variant for the session or account, and include the variant in every funnel event.

Do not test price, trial length, headline, plan order, and sign-in timing together. Do not use medical urgency, fear of missing medication, or emergency pressure to increase conversion. Do not place a paywall before the user gets a useful first-person record.

## 9. Website, terms, privacy, and consistency

### URL evidence

The following public URLs returned HTTP 200 on 2026-08-23:

- `https://jackwallner.github.io/elderhub/`
- `https://jackwallner.github.io/elderhub/privacy-policy.html`
- `https://jackwallner.github.io/elderhub/terms.html`
- `https://jackwallner.github.io/elderhub/support.html`
- `https://jackwallner.com/ios/elderhub/`
- `https://jackwallner.com/ios/elderhub/privacy-policy.html`
- `https://jackwallner.com/ios/elderhub/terms.html`
- `https://jackwallner.com/ios/elderhub/support.html`

This confirms reachability, not content equivalence or legal correctness. The join page and app deep links need separate end-to-end validation.

### Privacy and consumer health page

`docs/privacy-policy.html` and `docs/consumer-health-data.html` are detailed and recently updated, with August 17, 2026 dates. They describe account data, Supabase storage, care and health information, invitations, notifications, purchases, deletion, and rights. The consumer health page addresses Washington and Nevada policy requirements and mentions RevenueCat receipt and linked identifier handling.

The app also contains `PrivacyInfo.xcprivacy` with linked health, name, email, phone, user ID, device ID, other user content, and purchase history declarations, plus a not-tracking declaration. Per the request, this audit does not report any inconsistency between that manifest and RevenueCat as a defect.

Validation items:

- open Privacy from Settings and Paywall on a device with no network and with a network;
- confirm the link opens the same current policy version as ASC;
- confirm `consumer-health-data.html` is reachable from the privacy policy or another obvious legal index;
- verify data deletion and sign-out language matches actual Supabase deletion and local-store behavior;
- verify that the app's EU and UK availability restriction matches ASC territory configuration;
- confirm the legal pages do not promise a feature, retention period, or synchronization guarantee that the build does not provide.

### Terms and support

`docs/terms.html` is dated August 17, 2026 and contains subscription, auto-renewal, cancellation, one-purchase-per-care-circle, no-diagnosis, and availability language. `docs/support.html` is dated August 8, 2026 and describes onboarding, second-person Plus access, helpers, invites, Sign in with Apple, emergency card, check-in, and restore purchases.

The support page predates the privacy and terms pages. It appears broadly aligned, but verify its exact copy against the current build, especially:

- whether email sign-in is actually enabled, because `AuthFeatures.emailSignInEnabled` is currently false under the SMTP limitation described in `AuthService`;
- whether an invitation can be joined after installation without losing context;
- whether restore is available and meaningful on a real device;
- whether a signed-out user can recover sharing from Settings;
- whether `emergency card` wording explains that the user maintains the information;
- whether the one-person-free and additional-person boundary matches the actual count logic.

### Contact alias

The following customer-facing pages use `jackwallner+medlist@gmail.com`:

- `docs/privacy-policy.html:301-302`;
- `docs/consumer-health-data.html:216-217,255-256`;
- `docs/terms.html:151-152`;
- `docs/support.html:108-109`;
- `docs/join.html:98-99`.

The alias may still route correctly, but `medlist` is an old product name and can reduce trust, cause support triage confusion, or expose an internal history in a public legal document. Confirm it is intentional. A neutral `+elderhub` or support-domain alias would be clearer. Update all pages as one atomic legal and support change, then verify mirrored hosts.

### Site and source consistency table

| Concept | Local source | Website/legal | Risk |
| --- | --- | --- | --- |
| App name | `Elderhub`, internal `Aging` | Elderhub | Acceptable if internal names are documented. |
| First-person free | `PeopleView`, `PaywallView`, `SettingsView` | Homepage, terms, support | Appears aligned, validate the exact count definition. |
| Helpers free | `PaywallView`, `GroupService` role logic | Homepage, description, terms | Validate caregiver role and webhook behavior. |
| Prices | StoreKit, ASC script, JSON-LD | Homepage and paywall | Local values align, live ASC and RevenueCat unverified. |
| Trial | StoreKit one week, dynamic eligibility | Website and description | Verify eligibility wording and localized product terms. |
| Offline | local SwiftData mirror and sync docs | Homepage and support | State clearly that sharing requires identity and network. |
| EU and UK | `CLAUDE.md`, legal pages | Store availability must match | Confirm ASC territories. |
| App download | App ID in context | Website currently says coming soon | Must update after approval. |
| Contact | old `+medlist` alias | All legal and support pages | Brand mismatch. |

## 10. Crash, regression, and watchdog signals

### Current evidence

No MetricKit, crash service, analytics SDK, or watchdog integration was found in the inspected Elderhub source. The app uses OSLog categories such as `auth`, `groups`, `store`, `sync`, `push`, `dose-reminders`, and `checkin`. These logs help local debugging but do not notify an operator when a live user crashes.

No live crash spike or production incident can be claimed. The app is not publicly available in the evidence reviewed.

### What a MacBook watchdog can and cannot do

A script running on a MacBook cannot directly receive a crash callback from an arbitrary customer's iPhone. It needs a source that exposes diagnostics, such as a crash service, a server endpoint receiving MetricKit payloads, App Store Connect diagnostics, Supabase function logs, or RevenueCat webhook/API data. The script can then poll, compare against a baseline, deduplicate, and email an alert. It should not attempt to scrape private local device logs as a substitute for live-user telemetry.

The requested scaffold should eventually be configurable with:

- app ID and bundle ID;
- release build and release timestamp;
- polling interval;
- baseline window and comparison window;
- minimum event count before alerting;
- email destination and SMTP or local `sendmail` configuration;
- per-signal thresholds;
- state file for last seen event IDs and alert cooldowns;
- secret locations outside the repo;
- dry-run mode;
- redaction mode that excludes health data and identifiers.

Do not put ASC, RevenueCat, Supabase, or SMTP secrets in a checked-in script or in this repo's audit file.

### Signals to collect

#### Release health

- crash-free users and sessions by app version and build;
- fatal crashes by signature, device, OS, and release channel;
- watchdog terminations and launch crashes;
- hangs and launch duration percentiles;
- memory pressure or out-of-memory terminations;
- install, first launch, and app update failure signals;
- app version distribution and users remaining on the prior build.

#### Conversion health

- product page views, downloads, first launch, onboarding completion;
- first-person creation and first meaningful record action;
- paywall impressions by trigger;
- offerings load success, failure, and time to display;
- trial eligibility resolution success, ineligible, unknown, and error;
- trial start, purchase success, cancellation, pending, failure, restore success, and restore no purchase;
- conversion by monthly, yearly, and lifetime product;
- price and currency load failures;
- refunds, cancellations, renewal, expiration, and charge failures.

#### Group and sharing health

- invite creation, open, acceptance, expiration, and failure;
- sign-in completion and account-link errors;
- group creation and group membership errors;
- webhook received, rejected, retried, and applied;
- time from RevenueCat event to group billing update;
- device entitlement versus group entitlement divergence;
- sync failure, conflict, stale data, and local-to-cloud adoption failures.

#### Daily UX health

- notification permission result and reminder scheduling failures;
- check-in completion and duplicate action errors;
- emergency card open and share/export failures;
- Today load time and empty-state rate;
- foreground refresh and background sync failures;
- restore and sign-out/delete support errors.

### Suggested alert policy

Make thresholds configurable and establish the baseline after TestFlight and the first stable production window. A practical starting policy is:

- alert when the same fatal crash affects at least three distinct users in 15 minutes;
- alert when crash-free users fall materially below the previous seven-day build baseline, with a minimum session count;
- alert when a new build has a statistically meaningful increase in launch crashes, hangs, or watchdog terminations;
- alert when paywall offerings load errors exceed a small percentage of paywall impressions or remain above baseline for 10 minutes;
- alert when trial eligibility is `unknown` or error for a sustained period rather than treating ineligibility as an outage;
- alert when purchase failures increase but only after separating user cancellation from StoreKit failure;
- alert when a RevenueCat webhook is delayed or rejected beyond the agreed propagation window;
- alert when invite acceptance or group creation failures exceed baseline;
- send one deduplicated alert per signature and build, then a recovery message when the signal returns to normal.

Use a 0 to 2 hour high-attention window after release, then 24-hour and 72-hour checks. Compare by build, device, OS, territory, and release channel. A raw global rate can hide a regression affecting only one iOS version or one product.

### MetricKit implementation target

If native diagnostics are preferred, add an app-side `MXMetricManagerSubscriber` that uploads redacted diagnostic and metric payloads to a controlled endpoint. Prioritize crash, hang, launch, and memory diagnostics. The server should aggregate by app version and build and expose a small JSON endpoint that the MacBook watcher polls.

Do not upload care records or free-form content with diagnostics. Retain only the minimum technical fields needed to identify a release regression. The current OSLog categories can be preserved and correlated with build, but logs should not contain medication names, names, notes, vitals, or invite codes.

## 11. Test and validation gaps

### Existing strengths

- `AgingUITests/PaywallRenderUITests.swift` exercises StoreKit testing plan rendering and checks the three product identifiers.
- `AgingUITests/OnboardingHelpers.swift` covers the first path, `Not now`, the supporter name field, detail skipping, and opening the record.
- `AgingUITests/OfflineLaunchUITests.swift` tests a cold launch against an unreachable Supabase URL and verifies local behavior and emergency card access.
- `Aging/AgingApp.swift` has controlled UI test flags for reset, wipe, family, and seeded demo data.
- Production RevenueCat configuration is excluded from simulator runs, which protects production charts from fake simulator customers.

### Missing high-value tests

1. Real StoreKit purchase success for monthly and yearly products.
2. Trial eligibility and no-trial behavior for an account that has used an introductory offer.
3. Purchase cancellation, pending state, StoreKit error, duplicate tap, and retry.
4. Restore success, restore no purchase, restore failure, and restore after reinstall.
5. Signed-in group owner purchase and propagation to a second device.
6. Accountless second-person attempt, sign-in-after-purchase, and purchase-to-group reconciliation.
7. RevenueCat webhook idempotency, delayed delivery, invalid UUID, no group, owner, caregiver, subject, refund, expiration, renewal, and transfer.
8. Product offerings failure and recovery from the paywall. This test will require dependency injection or a test service because the current code only logs the error.
9. Group creation failure after local first-person save, with a recoverable sharing state.
10. Invite link before install, after install, already-installed app, invalid code, expired code, and sign-in interruption.
11. Legal links from Settings and Paywall, including offline behavior and mirrored host redirects.
12. Review gate timing and suppression after a failed purchase or emergency interaction, once implemented.
13. Accessibility for the paywall and first-run details at large Dynamic Type sizes.
14. Notification authorization denied, later re-enabled, and time-zone changes.
15. Release archive check for production APNs entitlement, no StoreKit test configuration, correct version, and correct bundle identity.

### Headless simulator validation constraints

When implementing these tests, follow the repo's iOS guidance:

- lease a device with `agent-sim checkout elderhub`;
- use the returned UDID, never a named destination;
- do not open Simulator.app;
- do not configure the production RevenueCat `appl_` key in simulator runs;
- use `Aging/Services/Products.storekit` for local purchase rendering;
- check the simulator back in after the run.

The current audit did not run a build, purchase, or simulator test. The findings above come from local inspection and available release evidence.

## 12. Agent documentation hygiene

### Good foundation

- `AGENTS.md` is a symlink to `CLAUDE.md`, so Claude and Codex receive the same canonical project guide.
- `CLAUDE.md` identifies the app name, bundle, scheme, RevenueCat entitlement, Supabase project, free-tier boundary, acquisition strategy, marketing paths, legal URLs, and shared iOS conventions.
- `archive/README.md` explicitly says archived material is historical and not current. Keep that rule.
- The project guide correctly warns about the similar `Elder Hub` app and names the load-bearing `docs/join.html` path.

### Confusion risks

1. No root `.cursor` directory was found. Cursor can still work from `AGENTS.md` or `CLAUDE.md`, but there is no explicit Cursor rule or pointer explaining the canonical source. A future documentation change should add a short source-of-truth map rather than duplicate the whole guide.
2. `ios27Aging.md` is a dated audit at the repo root and looks active. A new agent may treat it as current operating guidance. Move it under an explicit audit or archive directory after extracting unresolved items.
3. `aso-plan.md` contains a supersession notice, but it still contains a substantial old metadata direction. A new agent may implement the old strategy if it reads the body without respecting the notice. Split current ASO decisions from historical research or add a very prominent non-implementation marker.
4. `docs/research/01-groups-rbac-rls.md`, `02-offline-sync-swift6.md`, and `03-consent-compliance-billing.md` use old `Med List (Aging)` framing. They may still contain valid architecture rationale, but current invariants should be copied into a current architecture or runbook document and the originals labeled historical.
5. `scripts/asc-setup-iap.py` uses reference group name `Med List Pro` and display name `Elderhub Plus`. `Products.storekit` calls its group `Aging Pro`. The identifiers may be intentionally stable, but without a canonical table an agent can create duplicate products or entitlements.
6. `SupabaseFunctions/revenuecat-webhook/index.ts`, `escalate-check-ins/index.ts`, SQL migrations, and tests contain old internal comments. These are not customer-facing branding defects, but they increase search and maintenance noise.
7. `Shared/Services/MedListExporter.swift` is a stable code symbol with legacy naming. Do not rename it casually if it is part of an internal API or migration path. Document why it remains.
8. Archived audits contain findings that are no longer true in current source, such as old user-visible Med List paywall or legal branding. Agents should treat archives as evidence to recheck, not as an implementation queue.

### Recommended canonical reading order

The next documentation-only cleanup should establish this order:

1. `AGENTS.md` and `CLAUDE.md` for current project rules.
2. `docs/architecture.md` for current product and technical invariants.
3. A current `docs/aso/current.md` or equivalent for store and website decisions.
4. A current `docs/runbooks/release.md` for ASC, TestFlight, RevenueCat, legal URL, and watchdog checks.
5. A current `docs/runbooks/billing.md` for identity, entitlement, group propagation, and webhook behavior.
6. `audit823.md` for this audit's current findings and validation backlog.
7. `docs/research/` only when a referenced decision needs its rationale.
8. `archive/` only for historical context.

The map should state that internal identifiers remain stable, customer-facing branding is Elderhub, and all new product decisions must update the current documents first.

## 13. Recommended implementation backlog

### Before approval or first public traffic

1. Resolve ELD-01. The safest choice is to require identity and group context before the additional-person purchase. If product intent requires accountless purchase, implement server-side reconciliation and test it through restore, reinstall, and group creation.
2. Resolve ELD-02 with an explicit offerings failure and retry state.
3. Confirm ASC version, build, review notes, medical declaration, supported territories, metadata, and screenshot freshness.
4. Recreate the screenshot set from the final build, especially the paywall image.
5. Add a purchase, restore, trial, and group propagation smoke test on a real device or TestFlight environment.
6. Validate the reviewer's exact paths for first-person use, Sharing, invite, paywall, and restore.
7. Prepare the launch-day landing-page change for all download CTAs, JSON-LD, smart banner, and join page.
8. Confirm legal contact routing and decide whether to replace the `+medlist` alias.
9. Add at least minimal product funnel logging for offerings failure, paywall impression, trial start, purchase result, restore result, and group billing convergence.

### First 72 hours after approval

1. Verify the public App Store URL, direct website link, join page, Smart App Banner, canonical URLs, and social previews.
2. Watch crash-free users, launch crashes, hangs, paywall offerings failures, purchase failures, trial starts, and invite acceptance by build.
3. Manually run monthly, yearly, lifetime, trial-eligible, trial-ineligible, restore, and family propagation smoke checks.
4. Check RevenueCat entitlement and Supabase group billing convergence for a small set of real test accounts.
5. Review support contacts for name confusion with Elder Hub, accountless purchase confusion, restore confusion, and unsupported territory confusion.
6. Do not make an ASO or paywall experiment change until there is enough baseline data and the event pipeline distinguishes cancellation from failure.

### After baseline data exists

1. Run the screenshot and product page positioning experiment.
2. Run the yearly versus monthly default experiment.
3. Test the second-person value explanation and identity timing.
4. Add localization only where product page views and conversion justify it.
5. Complete the documentation source-of-truth cleanup and archive stale audits.

## 14. Validation matrix for the implementing agent

| Area | Scenario | Evidence to capture | Pass condition |
| --- | --- | --- | --- |
| ASC | Version and build | ASC version, build, status screenshot or API output | Submitted version is `1.0`, build is `27` or the deliberately approved replacement. |
| ASC | Review access | Screen recording or written clean-room steps | Reviewer reaches every promised review path without an impossible credential dependency. |
| ASC | Listing | Public app URL and metadata | Listing opens, name and subtitle match, screenshots match final build. |
| Website | Download CTA | All homepage and nav links | Every live CTA resolves to app ID `6796916172`; no `Coming to the App Store` remains after launch. |
| Website | Legal | HTTP status, canonical, content hash or manual comparison | GitHub Pages and canonical mirror serve the intended same versions. |
| Onboarding | Supporter | Clean local install, skip sign-in, create person, first action | User gets value without account and understands local versus shared state. |
| Onboarding | Solo | Clean local install, skip sign-in, add first record | User can use the core without a premature paywall. |
| Onboarding | Join | Invite before and after install | Correct group and person are joined, no lost invite context. |
| Billing | Additional person | Local-only and signed-in paths | No orphaned purchase; identity requirement or reconciliation is explicit. |
| Billing | Trial | New and previously trialed accounts | Trial claim matches eligibility and product terms. |
| Billing | Restore | Active, expired, no purchase, reinstall | Restore result is accurate and accessible. |
| Billing | Webhook | Delayed, duplicated, invalid, refund, expiration events | Group billing is idempotent, observable, and converges. |
| Paywall | Offerings outage | Inject product load failure | Error state has retry and support path, no infinite spinner. |
| UX | Accessibility | VoiceOver, Dynamic Type, contrast | Core and paywall actions remain understandable and usable. |
| Notifications | Permission changes | Deny, re-enable, time-zone change | Reminders explain state and reschedule correctly. |
| Reliability | Release | MetricKit or crash service dashboard | New build is compared with prior baseline within 2 hours, 24 hours, and 72 hours. |
| Reviews | Value gate | First success, failure, dismissal | Prompt appears only after value and does not block care work. |
| Docs | Agent handoff | New agent reads source-of-truth map | It does not implement superseded ASO, branding, or billing assumptions. |

## 15. Evidence ledger

### Direct facts

- ASC app ID and current status are available in context as `6796916172`, version `1.0`, `Waiting for Review`.
- The public App Store URL returned 404 on the audit date.
- Local version and build are `1.0.0` and `27` in `project.yml`.
- The customer-facing app name is Elderhub; internal scheme and bundle remain Aging.
- The free limit is one care person, and the additional-person action opens the paywall.
- RevenueCat primary entitlement is `Aging+`, with fallbacks `pro` and `AgingPro`.
- The webhook requires a UUID app user ID and an existing group relationship before writing group billing.
- The paywall renders only a progress state when plans are empty.
- The current source has no native review request or crash/analytics SDK match.
- The website download CTAs are prelaunch spans, not live App Store links.
- Seven screenshot files exist and were visually inspected; screenshot 7 shows `Continue` while current paywall source uses dynamic trial, lifetime, or subscribe wording.
- Public homepage and legal URLs returned 200 on both configured hosts.
- Customer-facing legal contact aliases still say `+medlist`.
- `AGENTS.md` symlinks to `CLAUDE.md`; no root `.cursor` directory was found.

### Strong inferences

- An accountless additional-person purchase can be locally successful but not represented in the group billing model.
- A product load failure can strand a user on the paywall.
- The current launch cannot diagnose trial or purchase conversion without new telemetry.
- The screenshot set may not represent the reviewed build.
- A post-approval landing page that remains unchanged will suppress downloads.

### Items requiring live confirmation

- Exact ASC build attached to the pending version.
- ASC regulated medical device declaration and territory availability.
- Live RevenueCat product IDs, offerings, entitlements, prices, trial eligibility, webhook deployment, and webhook secret enforcement.
- Whether any external crash or analytics service exists outside this repo.
- Actual TestFlight or production behavior of purchase, restore, invite, group sync, and notifications.
- Whether the old support email alias is intentionally routed and monitored.

## 16. Final decision list

### Fix or verify before launch

- Purchase identity and group reconciliation, ELD-01.
- Paywall offerings failure and retry, ELD-02.
- ASC review access and medical declaration, ELD-03 and ELD-11.
- Purchase, restore, trial, and webhook tests, ELD-10.
- Screenshot freshness, ELD-07.
- Basic release and conversion observability, ELD-04.
- Legal contact and mirror consistency, ELD-09 and ELD-18.

### Decide with product judgment

- Whether sign-in is required before the second-person paywall.
- Whether the app should use custom SwiftUI paywall experiments or adopt RevenueCat Paywalls.
- Whether the default should stay yearly.
- Whether to keep `dementia`, `alzheimers`, and `medical id` in the first keyword set.
- Whether the launch is intentionally en-US only.
- Whether local-only mode should be a durable product state or only an onboarding bridge.

### Improve after launch baseline

- Native review request and explicit feedback route.
- Progressive onboarding and more explicit activation actions.
- Settings sign-in and backup CTA.
- Current documentation map, naming table, and dated audit cleanup.
- Screenshot, landing-page, and metadata experiments.

The single most important validation is this: start as a local-only user, create one person, attempt to add a second person, and complete the full purchase, sign-in, group creation, restore, and second-device access sequence. Until that sequence is either blocked before purchase or reconciled end to end, Elderhub's most important monetization path is not proven safe.
