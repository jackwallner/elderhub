---
paths:
  - "android/**"
  - "scripts/play-products.py"
  - "scripts/play_assets.swift"
---

# Android port

Native Kotlin/Compose port in `android/`. Package and namespace
`com.jackwallner.aging` (same as the iOS bundle id, permanent once uploaded).
Listing name "Elderhub: Family Care Log", launcher label "Elderhub".
Started 2026-10-20 (fleet run `shift-android-elderhub-1-1792525535`, jmbp).

## What the Android build is

A local-only care record: onboarding (who you are here for, the person's name,
the permission attestation for a supporter), Today (doses with Taken/Skipped/
undo, appointments due within 7 days, running low), Care (people, Add Person),
the person hub (`CareFeature` tiles with blurbs and status lines), medications
(times, weekdays, as needed, refills, stop/restart), appointments and visit
notes, contacts (CALL FIRST, dial), providers, health details, the emergency
card with plain-text share, and Settings (Plus, restore, reviewer access, your
name, feedback, privacy, the medical disclaimer).

Storage is one JSON file (`filesDir/care.json`, `CareCodec`) whose field names
follow the Supabase columns. Backup and device transfer are excluded
(`data_extraction_rules.xml`). `CareStore` is the SwiftData stand-in: every
screen renders from it and nothing waits on a network.

## Parity rules (tested in `app/src/test`)

- `ScheduleEngine` mirrors the Swift one, including Foundation's elapsed-minute
  addition: on a spring-forward day the 8:00 dose lands at 9:00 local on both
  platforms (epoch checked by compiling the Swift call). Changing that to wall
  clock must happen on iOS and Android together, or `DoseLog` ids diverge.
- `DoseLog.deterministicId` is the iOS UUIDv5 (namespace
  `6f1d5b3e-...`, `"<med uuid lowercased>:<epoch minute>"`); vectors in
  `DeterministicIdTest` come from running `Shared/Services/DeterministicID.swift`.
- `MedListExporter` and `EmergencyCardScreen` print every critical section even
  when empty, in step, like iOS.
- Weekdays use Calendar numbering (1 = Sunday); `weekdayLabel` orders by locale.
- `recorded_by_name` is the caregiver name from Settings, never a literal "You".

## Paid boundary

Free tier is one care recipient (`PaidBoundary.canAddPerson`). Add Person on
the Care tab opens the paywall when locked. Entitlement `Aging+` with legacy
aliases `pro` and `AgingPro`; products `com.jackwallner.aging.pro.monthly`,
`.yearly` (Play base plans `monthly`/`yearly`, offer `trial-7d`) and
`.lifetime`. RevenueCat reads offering `android` if present, else current.
Debug uses the Test Store key (`REVENUECAT_TEST_KEY`, the one already in
`StoreService.swift`); release requires `REVENUECAT_PLAY_KEY` (`goog_`), the
reviewer digest and the upload key (`validateReleaseConfiguration`). The `qa`
build is R8-optimized with no key and no debug hooks.

## Platform gaps: decisions needed from Jack

1. **Family sharing (care circles, invites, sync).** iOS authenticates only with
   Sign in with Apple against Supabase `oygrxltpydcmmdtbreec`. Android needs a
   sign-in provider decision before any of `GroupService`/`SyncEngine` can be
   ported: (a) Sign in with Apple on Android through Supabase's OAuth web flow
   (needs an Apple Services ID, return URL and key in the Supabase Apple
   provider), or (b) add Google sign-in as a second Supabase provider (needs a
   Google OAuth client and account-linking rules for one person on two
   platforms), or (c) ship Android local-only (current build). Until decided,
   Android has no Sharing tab, no join links (`docs/join.html` invitations do
   not open the Android app) and no check-in push.
2. **Reminders.** Dose reminders, refill and appointment notifications and the
   check-in reminder are not ported. They need `POST_NOTIFICATIONS` and inexact
   `AlarmManager` scheduling (exact alarms need a Play declaration). Port next;
   no backend decision needed.
3. **Not yet ported features** (each needs a `CareFeature` case and a hub tile
   when it lands): tasks, vitals, symptoms/care events, notes, bills, timeline,
   search, handover mode, setup checklist, the in-app review ask.

## Build and test on jmbp

    cd android
    export JAVA_HOME=~/jdks/temurin-17/Contents/Home
    ./gradlew --no-daemon :app:testDebugUnitTest                       # 65 JVM tests
    ./gradlew --no-daemon :app:lintDebug :app:assembleDebug :app:assembleQa
    ANDROID_SERIAL=emulator-5584 ./gradlew --no-daemon :app:connectedDebugAndroidTest   # 9 device tests

Leased AVD: `agent-emu-1` (API 36 Google Play x86_64), booted headless with
`emulator -avd agent-emu-1 -port 5584 -no-window -no-audio -no-boot-anim
-no-metrics -no-snapshot-save`, stopped with `adb -s emulator-5584 emu kill`.
It renders with SwiftShader/SwANGLE, so frame cadence there is ~10 fps and is
not evidence about the app; motion review belongs on the Air.

Debug launch extras (`src/debug/.../DebugLaunchOptions.kt`): `resetAll`,
`seedDemo`, `seedDad`, `demoPro`, `previewStore` (+`previewTrialDays`,
`previewTrialUsed`), `openPaywall`, `tab`.

## Release state

- 2026-10-20: not on Play. No Play app, no RevenueCat Play app, no upload
  keystore, no products. Version 1.0.4 (versionCode 1), target/compile SDK 36.
- Listing, policy answers and graphics: `android/play-assets/listing-en-US.md`.
  Privacy policy has an Android section.
- Remaining, in order: decision on gap 1 (or accept local-only v1); Jack
  approves the Android price ladder; create the upload keystore on the Air
  (`~/.android/keystores/aging-upload.p12`, passwords in `~/.aging_credentials`);
  create the Play app and run `scripts/play-products.py`; add the Play app to the
  existing RevenueCat project with the same `Aging+` entitlement and packages,
  register it in `~/.rc-clean/apps.json`; signed AAB with 16 KB alignment check;
  internal track, licensed purchase/restore; App content forms; production only
  in its pacing slot.
