# Elderhub: Google Play listing (en-US)

Source of truth for the Play Console store listing and policy answers for the
Android build. Adapted from `fastlane/metadata/en-US/` to what the Android app
actually does: on-device only, no account, no sharing, no notifications. No
prices in copy, no em dashes, and never `caregiver`, `senior care` or
`home care` (the iOS ASC rule, kept on Play for one consistent listing).

## Listing text

`metadata/android/en-US/` (fastlane supply layout): title (25/30), short
description (74/80), full description (2394/4000). English only for v1.

## Graphics

- `icon-512.png`: the iOS icon, 512 x 512, no alpha.
- `feature-graphic.png`: 1024 x 500, rendered by `scripts/play_assets.swift feature`.
- `screenshots/01..05`: 1080 x 1920, no alpha. Real debug-build captures
  (`raw/`, seeded with `--ez seedDemo true`, status bar in demo mode) framed by
  `scripts/play_assets.swift shot`. No paywall shot: preview prices would drift
  from Play's regional prices. Copy them to
  `metadata/android/en-US/images/{icon.png,featureGraphic.png,phoneScreenshots/}`
  before a `fastlane supply --sync_image_upload` run.

## Store settings

- App name: Elderhub: Family Care Log. Category: Medical (matches iOS).
- Contact email: jackwallner+medlist@gmail.com (the in-app feedback address).
  Website: https://jackwallner.github.io/elderhub/
- Privacy policy: https://jackwallner.github.io/elderhub/privacy-policy.html
  ("The Android App" section, added 2026-10-20).
- Countries: mirror iOS. Not sold in the EU or UK (`scripts/asc-restrict-territories.py`).
- Managed publishing off (fleet default).

## App content answers (from the code, 2026-10-20)

- Ads: no ads.
- App access: everything is reachable without login. Elderhub Plus (second
  person) is behind a purchase: give reviewers the Settings > Reviewer access
  code (plaintext stays off-repo; only `PLAY_REVIEW_CODE_SHA256` ships in the
  release build).
- Target audience: 18+.
- Health apps declaration: medication and health record management for a
  family member. Not a medical device; no diagnosis or treatment claims.
- Government, financial features, news, COVID: no.
- Advertising ID: not used (no ads SDK; RevenueCat does not collect it here).
- Data safety:
  - Data collected: Purchase history (Financial info > Purchase history) via
    RevenueCat and Google Play, for app functionality (entitlement checks).
    App activity / identifiers: an anonymous RevenueCat app user id generated
    on the device. Nothing is shared with third parties for advertising.
  - Health and medication data: stays on the device, never transmitted.
    Device-only data is not "collected" under Play's definition.
  - Encrypted in transit: yes (HTTPS to RevenueCat and Google Play).
  - Deletion: uninstalling or clearing app storage deletes the record; there
    is no server copy. RevenueCat purchase records follow its retention.
- Content rating (IARC): reference app, no user-generated sharing, no
  violence; expect Everyone / PEGI 3 with In-App Purchases.

## Products (proposed, not created)

`python3 scripts/play-products.py --plan` prints the ladder. iOS is $9.99 /
$39.99 / $89.99 with a 1-week trial; the proposed Android ladder follows the
fleet's ~20% rule: $7.99 monthly and $31.99 yearly (base plans `monthly`,
`yearly`, offer `trial-7d`), $71.99 lifetime. Jack approves the prices before
the script runs against Play.
