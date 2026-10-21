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

A care record that works on the phone alone and shares through the same
Supabase circles as iOS once someone signs in with Google: onboarding (who you
are here for, the person's name, the permission attestation for a supporter,
or "I have an invitation"), Today (doses with Taken/Skipped/
undo, appointments due within 7 days, running low), Care (people, Add Person),
the person hub (`CareFeature` tiles with blurbs and status lines), medications
(times, weekdays, as needed, refills, stop/restart), appointments and visit
notes, contacts (CALL FIRST, dial), providers, health details, the emergency
card with plain-text share, Sharing (sign-in, circle, members, invites,
join, leave), and Settings (Plus, restore, reviewer access, your name, the
account and sync status, conflicts, sign out, delete account, feedback,
privacy, the medical disclaimer).

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

## Family sharing (Jack decided 2026-10-20: Google sign-in)

- **Sign-in.** `GoogleSignIn` (Credential Manager, `GetSignInWithGoogleOption`
  with the SHA-256 of a raw nonce) then `SupabaseClient.signInWithIdToken`
  (`grant_type=id_token`, provider `google`, raw nonce), the shop pattern.
  `GOOGLE_WEB_CLIENT_ID` comes from ignored `local.properties`; without it the
  button is hidden (`IdTokenSource.isAvailable`) and `validateReleaseConfiguration`
  fails. Supabase reported the Google provider enabled on 2026-10-21
  (`/auth/v1/settings`). Not yet verified end to end: no emulator here has a
  Google account, and the Android OAuth client (package + signing SHA-1) is the
  separate Console job. Debug, QA and Play signing each need their SHA-1 on an
  Android OAuth client in the same Google Cloud project as the web client.
- **Sessions** follow `AuthService.swift`: read from storage with no network,
  refreshed after first paint, signed out only on the GoTrue codes in
  `SupabaseClient.REVOKING_CODES`; a transport failure or 5xx only sets
  `isOffline`. RevenueCat `logIn(<supabase user id>)` after sign-in, `logOut`
  on sign-out, so `revenuecat-webhook` credits `group_billing`. `AppGraph.isPlus`
  is `store.isPro || groups.hasPlus`, and only the circle's people count toward
  the free slot.
- **Accounts are not linked.** One person on iPhone (Apple) and Android
  (Google) is two Supabase users, two `profiles` rows and two members of a
  circle. Nothing matches them by email (Apple relays are private) and nothing
  merges them; each joins with its own invitation. Settings says so. Linking
  would need Supabase manual identity linking and a deliberate UI, a decision
  for Jack if anyone asks.
- **What syncs.** `SyncEntity` covers `care_recipients`, `providers`,
  `medications`, `dose_logs`, `visits`, `emergency_contacts`, the tables this
  port has screens for. Vitals, care events, tasks, notes, bills, check-ins and
  check-in settings are never pulled, so no cursor passes their rows and the
  build that ports one pulls it from the start. `care_recipients.last_check_in_at`
  is pulled and shown on the hub ("Last check-in today at 9:12 AM"), so a
  check-in pressed on an iPhone is visible after any sync.
- **Bookkeeping is derived, not called.** `CareStore.update` diffs every local
  write (`SyncTracker`): changed rows get dirty meta and one outbox entry,
  removed rows a `Tombstone` holding the wire row, but only for rows of the
  circle this phone is in (`CareStore.circleId`). Deleting a person or a
  medication tombstones that row only; its children leave this phone with it
  and the other phones drop theirs when the tombstone arrives, as on iOS. Server writes
  go through `applyRemote`, which tracks nothing. Leaving, sign-out and an
  access restriction remove rows with `removeLocally`, never a tombstone (I5).
- **Engine rules** match `SyncEngine.swift` (parents first, defer vs discard,
  compound `(updated_at, id)` cursor from server time only, per-table catch so
  the push always runs, 42501 to `needsReview`, other errors back off 10s,
  20s... to 6 attempts) with two deliberate differences, both in the
  `SyncEngine` KDoc: a dirty person or medication newer than the incoming row
  is kept (iOS overwrites it with the older server copy), and `deleted_at` is
  always sent, so a dose re-taken after an undo is live on the server too (iOS
  omits nil and leaves that server row deleted; worth fixing there). Other nil
  optionals are omitted so `linked_user_id` and `last_filled_at` survive an
  Android upsert. Device clock vs server `updated_at` skew can still flag a
  false conflict on an edit made within seconds of a push, on both platforms.
- **Invitations.** `InviteLink`/`InviteMessage` port the iOS rules; the message
  says "on your phone", not "iPhone". The manifest takes
  `https://jackwallner.com/ios/elderhub/join.html` (App Link, `autoVerify`) and
  `elderhub://invite`. Verification needs
  `https://jackwallner.com/.well-known/assetlinks.json` listing package
  `com.jackwallner.aging` with the **Play app-signing** SHA-256 (Play Console >
  Test and release > App integrity, after the first upload) plus the upload and
  debug SHA-256 if wanted. jackwallner.com's root is not this repo's `docs/`
  (that mirrors to `/ios/elderhub/`), so the file goes in the site repo that
  serves the domain root. Until then Android shows the browser, and the join
  page's "Open in Elderhub" button opens the scheme. `docs/join.html` still
  says Elderhub is iPhone-only: change that copy, with a Play link, the day the
  Play listing is live, not before.
- **The person being looked after** gets the Transparency screen before
  anything syncs, then a two-tab app (Today, You). There is no check-in button
  on Android yet.
- **Check-in push needs FCM: decision for Jack.** iOS caregivers get the
  "no check-in" push from `escalate-check-ins` via APNs device tokens. Android
  registers no token, so an Android caregiver is not told; they see the last
  check-in after a sync. Porting means a Firebase project for
  `com.jackwallner.aging`, `google-services.json`, an FCM token column or table
  beside the APNs one (migration), FCM HTTP v1 sending in the edge function with
  a service account secret, and the Play data-safety and privacy updates.
- Fake backend for tests and screenshots: `src/debug/.../FakeCareServer.kt`,
  launch extras `fakeCloud`, `fakeSignedIn`, `fakeCircle`, `fakePendingInvite`,
  `fakeInvite`, `fakeOffline`. It mirrors the RPC rules tests rely on and holds
  no secret; release and QA builds cannot reach it.

## Other gaps

1. **Reminders.** Dose reminders are ported (`DoseReminderPlanner`,
   `ReminderService`): one notification per person per dose time, a per-person
   switch on the hub (`dose-reminders.<ID>`), one rolling `setWindow` alarm
   (5-minute window, no exact-alarm permission or Play declaration), re-planned
   on every record change (pulled ones included), launch, boot, update and
   clock change. Blocked permission shows the Settings alert. Not yet ported:
   refill and appointment notifications, the check-in reminder, and routing a
   tapped notification to the person (it opens Today, which lists everyone).
2. **Not yet ported features** (each needs a `CareFeature` case, a hub tile and
   a `SyncEntity` when it lands): tasks, vitals, symptoms/care events, notes,
   bills, check-in button and settings, timeline, search, handover mode, setup
   checklist, the in-app review ask.

## Build and test on jmbp

    cd android
    export JAVA_HOME=~/jdks/temurin-17/Contents/Home
    ./gradlew --no-daemon :app:testDebugUnitTest                       # 126 JVM tests
    ./gradlew --no-daemon :app:lintDebug :app:assembleDebug :app:assembleQa
    ANDROID_SERIAL=emulator-5584 ./gradlew --no-daemon :app:connectedDebugAndroidTest   # device tests

Leased AVD: `agent-emu-1` (API 36 Google Play x86_64), booted headless with
`emulator -avd agent-emu-1 -port 5584 -no-window -no-audio -no-boot-anim
-no-metrics -no-snapshot-save`, stopped with `adb -s emulator-5584 emu kill`.
It renders with SwiftShader/SwANGLE, so frame cadence there is ~10 fps and is
not evidence about the app; motion review belongs on the Air.

Debug launch extras (`src/debug/.../DebugLaunchOptions.kt`): `resetAll`,
`seedDemo`, `seedDad`, `demoPro`, `previewStore` (+`previewTrialDays`,
`previewTrialUsed`), `openPaywall`, `tab` (0 Today, 1 Care, 2 Sharing,
3 Settings), and the fake-backend extras above.

## Release state

- 2026-10-20: not on Play. No Play app, no RevenueCat Play app, no upload
  keystore, no products. Version 1.0.4 (versionCode 1), target/compile SDK 36.
- Listing, policy answers and graphics: `android/play-assets/listing-en-US.md`.
  Privacy policy has an Android section.
- 2026-10-21: family sharing ported (fleet run
  `shift-android-elderhub-google-1-1792573537`). Release now also needs
  `GOOGLE_WEB_CLIENT_ID` in the Air's `local.properties`.
- Remaining, in order: the Google Cloud Android OAuth clients (debug, upload
  and Play app-signing SHA-1) beside the web client Supabase trusts, then one
  real sign-in on a device with a Google account; Jack approves the Android
  price ladder; create the upload keystore on the Air
  (`~/.android/keystores/aging-upload.p12`, passwords in `~/.aging_credentials`);
  create the Play app and run `scripts/play-products.py`; add the Play app to the
  existing RevenueCat project with the same `Aging+` entitlement and packages,
  register it in `~/.rc-clean/apps.json`; signed AAB with 16 KB alignment check;
  internal track, licensed purchase/restore, a real Google sign-in, invite and
  sync with an iPhone in the same circle; publish `assetlinks.json` with the
  Play app-signing SHA-256; App content forms (Data safety now declares name,
  email, user ids and the shared health record, see the listing file); update
  `docs/join.html` for Android when the listing is live; production only in its
  pacing slot. FCM check-in push stays a separate decision.
