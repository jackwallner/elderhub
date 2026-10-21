# Elderhub: Google Play listing (en-US)

Source of truth for the Play Console store listing and policy answers for the
Android build. Adapted from `fastlane/metadata/en-US/` to what the Android app
actually does: works on-device with no account; family sharing through Sign
in with Google and the same Supabase care circles as iOS; local dose
reminders, no push. No
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

## App content answers (from the code, 2026-10-21)

- Ads: no ads.
- App access: the whole care record is reachable without login. Family
  sharing (the Sharing tab) needs Sign in with Google with the reviewer's own
  Google account; no credentials to hand over. Elderhub Plus (second person)
  is behind a purchase: give reviewers the Settings > Reviewer access code
  (plaintext stays off-repo; only `PLAY_REVIEW_CODE_SHA256` ships in the
  release build).
- Target audience: 18+.
- Health apps declaration: medication and health record management for a
  family member. Not a medical device; no diagnosis or treatment claims.
- Government, financial features, news, COVID: no.
- Advertising ID: not used (no ads SDK; RevenueCat does not collect it here).
- Data safety (2026-10-21, with family sharing):
  - Collected, only when the user signs in (optional): Personal info > Name
    and Email address (from the Google sign-in token, stored by Supabase), and
    App info > User IDs (Supabase account id). Purpose: app functionality and
    account management.
  - Collected, only for records shared to a care circle (optional): Health and
    fitness > Health info (medications, dose history, allergies, conditions,
    visits, providers), Personal info > Name and Phone number (people tracked
    and emergency contacts), Personal info > Other info (relationship, notes).
    Purpose: app functionality. Shared with: no third party; other members of
    the user's own care circle see it, which Play counts as user-initiated, not
    sharing. Processed by Supabase as a service provider.
  - Collected for purchases: Financial info > Purchase history via RevenueCat
    and Google Play (entitlement checks), plus the RevenueCat app user id
    (anonymous until sign-in, then the Supabase id).
  - Records never shared to a circle stay on the device and are not
    "collected" under Play's definition. No location, no advertising id, no
    push token.
  - Encrypted in transit: yes (HTTPS to Supabase, RevenueCat and Google Play).
  - Deletion: Settings > Delete account removes the account (the `delete_account`
    RPC); the family's shared history keeps the author's name snapshot, as on
    iOS. Uninstalling or clearing storage deletes the phone's copy. Provide
    the account-deletion URL Play requires (the support page) in Data safety.
- Content rating (IARC): reference app; users share records only with the
  care circle they invite (answer the "users can interact or exchange content"
  question yes, limited to invited family); no violence; expect Everyone /
  PEGI 3 with In-App Purchases and Users Interact.

## Products (proposed, not created)

`python3 scripts/play-products.py --plan` prints the ladder. iOS is $9.99 /
$39.99 / $89.99 with a 1-week trial; the proposed Android ladder follows the
fleet's ~20% rule: $7.99 monthly and $31.99 yearly (base plans `monthly`,
`yearly`, offer `trial-7d`), $71.99 lifetime. Jack approves the prices before
the script runs against Play.
