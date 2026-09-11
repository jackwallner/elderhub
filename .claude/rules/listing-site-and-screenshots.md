---
paths:
  - "fastlane/**/*"
  - "docs/**/*"
  - "aso-plan.md"
  - "scripts/capture-screenshots.sh"
  - "scripts/compose-screenshots.py"
  - "scripts/pull-appstore-metadata.sh"
  - "scripts/asc-restrict-territories.py"
  - "Shared/Services/InviteLink.swift"
  - ".github/workflows/*"
---

# Elderhub: listing, marketing site and App Store screenshots

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

### The Elderhub rename

Renamed from "Med List: Family Meds" on 2026-08-05. The medication-list title was an
ASO bet on `medication list` (pop 23 / diff 23), the one soft keyword in the category.
That bet is off: the product pivoted past meds-only, and acquisition is planned outside
App Store search. Everything in `aso-plan.md` about *what not to claim* still stands
(see below); only the title strategy changed. Note that **Elder Hub** (App Store id
1589043147, Elder Technologies, Medical) is a live same-category app with a near
-identical name, so watch for a name-confusion rejection at review.

### Acquisition and keywords

- **Acquisition is not App Store search.** The eldercare/caregiving vocabulary has no
  search demand (every term at Astro's popularity floor; ~30 competing apps, category
  ceiling 35 ratings since 2016), and as of the Elderhub rename the title no longer
  chases the one soft term. Plan the channel outside search. `aso-plan.md` is still the
  reference for what the category is; read it before touching metadata.

- Still true regardless of channel: do not put `caregiver`, `senior care` or `home care`
  in any ASC field. They are the only high-volume terms nearby and they resolve to job
  seekers and B2B agency software, so they buy wrong-intent installs and bad reviews.

- Free keyword-field trophies, since the field costs nothing: the `dementia` cluster
  (diff 5-13, unowned) and `medical id`.

### Marketing site, join page and the old medlist URLs

- **The marketing site lives in this repo's `docs/` directory.** GitHub Pages
  serves the current pages from `jackwallner.github.io/elderhub/`, and the
  `sync-landing-page.yml` workflow mirrors them to
  `jackwallner.com/ios/elderhub/`. The privacy, terms, and support URLs are
  compiled into shipped builds (`SettingsView`, `PaywallView`) and the ASC
  listing. Format and checklist: `~/ios/landing-pages/README.md`.

- **`docs/join.html` is part of the app, not a separate site.** Every
  invitation message points at it (`InviteLink.webBase`), and those messages sit
  in inboxes longer than the build that wrote them, so the page has to stay
  published at that exact path and the app must ship no build whose invite link
  is live before the page is. It is what makes an invitation openable from a
  desktop client or a phone with no app; `elderhub://` alone never was. §17 of
  `docs/architecture.md` has the rest.

- **The live 1.0 listing carries the pre-rename `jackwallner.github.io/medlist`
  URLs, and ASC refuses to edit them while the version is Ready for Sale.**
  `jackwallner/medlist` is a redirect-only repo standing those paths back up so
  the shipped listing's Developer Website, Support and Privacy Policy links
  resolve; it forwards to the `elderhub` pages and preserves the query string
  so `/medlist/join.html?code=...` still works. **1.0.1 must upload the correct
  metadata** (`fastlane/metadata/en-US/*_url.txt` already hold it, and the
  description's privacy link with them). Do not rename the `elderhub` repo to
  match the listing: the shipped binary's own links and every invitation ever
  sent point at `/elderhub/`.

## App Store screenshots
- The set is generated, not hand-shot. `scripts/capture-screenshots.sh <udid> <out>`
  is the product-evidence capture the shared renderer
  (`~/ios/appstore-screenshots`, manifest `configs/elderhub.json`, `capture.mode:
  command`) calls on a leased headless simulator; it owns boot, build, install and
  navigation, and the caller owns the lease. Render with
  `./bin/shotflow all configs/elderhub.json --output outputs/elderhub`.
- Composed frames live in `fastlane/screenshots/en-US/` and the raw device
  captures they were composed from in `fastlane/screenshot-captures/en-US/`,
  deliberately outside `fastlane/screenshots/` so `deliver` cannot read the
  folder as a locale.
- **The capture asserts its own status bar.** A shot taken right after a push
  intermittently catches the Dynamic Island drawn as a black pill over the
  status bar, which reads as a rendering fault on a store page. `shoot()` checks
  the strip and retakes rather than trusting the frame.
- Paywall, trial and purchase captures stay out of this script. A monetization
  shot must never reach an App Store set by accident.
