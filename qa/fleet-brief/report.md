# Release gate: elderhub-ship b317d6e637c9

Verdict: **BLOCK** (2026-11-01T17:30:59+00:00)

Every finding blocks except legacy backlog. `qa-gate fix <repo>` fixes them. Motion candidates need a judgement in the ledger: `qa-gate ledger <repo> accept` for an intended change, or `add` a P1 when it is a real glitch.

## Blocking (17)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P1 | cta-jump | newcomer | test1FirstRecordToTodayAndUpgrade / name | the main button "Continue" is at y 694, 334 by 66; on "fork" it was at y 524, 342 by 93 | `cta-jump|test1FirstRecordToTodayAndUpgrade|name|continue` |
| P1 | cta-jump | newcomer | test1FirstRecordToTodayAndUpgrade / sign-in | the main button "Sign in with Apple" is at y 652, 334 by 52; on "name" it was at y 694, 334 by 66 | `cta-jump|test1FirstRecordToTodayAndUpgrade|sign-in|sign in with apple` |
| P1 | cta-jump | newcomer | test1FirstRecordToTodayAndUpgrade / details | the main button "onboarding.details.continue" is at y 686, 342 by 66; on "sign-in" it was at y 652, 334 by 52 | `cta-jump|test1FirstRecordToTodayAndUpgrade|details|onboarding.details.continue` |
| P1 | overlap | newcomer | test1FirstRecordToTodayAndUpgrade / first-today | button "today.quick.tasks" overlaps "person.3" by 49% | `overlap|test1FirstRecordToTodayAndUpgrade|first-today|person.# / today.quick.tasks` |
| P1 | overlap | newcomer | test2TabsAndReturn / today-after-tabs | button "today.quick.tasks" overlaps "person.3" by 49% | `overlap|test2TabsAndReturn|today-after-tabs|person.# / today.quick.tasks` |
| P1 | overlap | newcomer | test2TabsAndReturn / today-after-relaunch | button "today.quick.tasks" overlaps "person.3" by 49% | `overlap|test2TabsAndReturn|today-after-relaunch|person.# / today.quick.tasks` |
| P1 | overlap | newcomer | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-today-empty | button "today.quick.tasks" overlaps "person.3" by 49% | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-today-empty|person.# / today.quick.tasks` |
| P1 | overlap | newcomer | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-after-relaunch | button "today.quick.tasks" overlaps "person.3" by 66% | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-after-relaunch|person.# / today.quick.tasks` |
| P1 | overlap | newcomer | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | button "today.medications" overlaps "person.2" by 42% | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|person.# / today.medications` |
| P1 | overlap | newcomer | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | button "today.medications" overlaps "gear" by 42% | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|gear / today.medications` |
| P1 | overlap | reduce-motion | test1FirstRecordToTodayAndUpgrade / first-today | button "today.quick.medications" overlaps "checklist" by 75% | `overlap|test1FirstRecordToTodayAndUpgrade|first-today|checklist / today.quick.medications` |
| P1 | overlap | reduce-motion | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-editor | button "Add a time" overlaps "" by 48% | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-editor|/ add a time` |
| P1 | overlap | reduce-motion | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-listed | button "person-detail.incidents" overlaps "person.3" by 88% | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-listed|person-detail.incidents / person.#` |
| P0 | journey-broken | duo | test1FirstRecordToTodayAndUpgrade /  | XCTAssertTrue failed | `journey-broken|test1FirstRecordToTodayAndUpgrade` |
| P0 | journey-broken | duo | test2TabsAndReturn /  | XCTAssertTrue failed | `journey-broken|test2TabsAndReturn` |
| P0 | journey-broken | duo | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch /  | XCTAssertTrue failed | `journey-broken|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch` |
| P0 | unit-tests | unit | aWeeklyMedicationSaysWhichDay /  | Expectation failed: med.scheduleLabel.contains("7:00")
med.scheduleLabel → "Mondays · 6:00 AM" | `unit-tests|aWeeklyMedicationSaysWhichDay` |

## Needs a judgement (3)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P1 | motion-jump | accessibility | test1FirstRecordToTodayAndUpgrade / sign-in | jump candidate at 36.82s of journeys.mp4 (score 0.195) ([sheet](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/accessibility/journeys.event-01.png)) | `motion-jump|test1FirstRecordToTodayAndUpgrade|sign-in|` |
| P1 | motion-jump | accessibility | test2TabsAndReturn / today-after-relaunch | jump candidate at 156.94s of journeys.mp4 (score 0.195) ([sheet](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/accessibility/journeys.event-07.png)) | `motion-jump|test2TabsAndReturn|today-after-relaunch|` |
| P1 | motion-jump | accessibility | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-today-empty | jump candidate at 177.39s of journeys.mp4 (score 0.193) ([sheet](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/accessibility/journeys.event-09.png)) | `motion-jump|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-today-empty|` |

## Legacy backlog, warns until fixed (100)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / care-after-upgrade | Contrast nearly passed (measured 3.5:1): "0 of 6 set up" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|care-after-upgrade|# of # set up` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / care-after-upgrade | Contrast nearly passed (measured 3.7:1): "EW" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|care-after-upgrade|ew` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / care-after-upgrade | Contrast nearly passed (measured 4.0:1): "Nothing recorded yet" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|care-after-upgrade|nothing recorded yet` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / details | Contrast nearly passed (measured 3.5:1): "onboarding.details.finish-later" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|details|onboarding.details.finish-later` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / details | Contrast nearly passed (measured 3.5:1): "onboarding.details.skip" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|details|onboarding.details.skip` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / details | Contrast nearly passed (measured 3.4:1): "Step 1 of 8" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|details|step # of #` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / first-today | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|first-today|today.setup-card` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / fork | Contrast nearly passed (measured 3.4:1): "You can change this later." | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|fork|you can change this later.` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / name | Contrast nearly passed (measured 3.4:1): "A copy stays on this phone, so it opens with no signal." | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|name|a copy stays on this phone, so it opens with no signal.` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / name | Contrast failed (measured 1.5:1): "Continue" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|name|continue` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / sign-in | Contrast nearly passed (measured 3.5:1): "Not now" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|sign-in|not now` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast failed (measured 3.6:1): "$89.99" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|$#` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast nearly passed (measured 3.5:1): "EULA" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|eula` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast failed (measured 3.5:1): "How the free trial works" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|how the free trial works` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast nearly passed (measured 3.5:1): "Lifetime" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|lifetime` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast failed (measured 3.6:1): "No payment now · Cancel any time" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|no payment now · cancel any time` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast failed (measured 3.6:1): "One payment, no renewal" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|one payment, no renewal` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast nearly passed (measured 3.5:1): "Privacy" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|privacy` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast nearly passed (measured 3.5:1): "Restore" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|restore` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast failed (measured 1.8:1): "Save 66%" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|save #%` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast nearly passed (measured 3.5:1): "Terms" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|terms` |
| P2 | a11y-contrast |  | test1FirstRecordToTodayAndUpgrade / upgrade | Contrast failed (measured 3.6:1): "·" | `a11y-contrast|test1FirstRecordToTodayAndUpgrade|upgrade|·` |
| P2 | a11y-contrast |  | test2TabsAndReturn / care | Contrast nearly passed (measured 3.5:1): "0 of 6 set up" | `a11y-contrast|test2TabsAndReturn|care|# of # set up` |
| P2 | a11y-contrast |  | test2TabsAndReturn / care | Contrast nearly passed (measured 3.7:1): "EW" | `a11y-contrast|test2TabsAndReturn|care|ew` |
| P2 | a11y-contrast |  | test2TabsAndReturn / care | Contrast nearly passed (measured 4.0:1): "Nothing recorded yet" | `a11y-contrast|test2TabsAndReturn|care|nothing recorded yet` |
| P2 | a11y-contrast |  | test2TabsAndReturn / settings | Contrast failed (measured 1.9:1): "Add more people to this care circle. Every feature is already free for the first person." | `a11y-contrast|test2TabsAndReturn|settings|add more people to this care circle. every feature is alread` |
| P2 | a11y-contrast |  | test2TabsAndReturn / settings | Contrast nearly passed (measured 3.5:1): "Hand the phone to them" | `a11y-contrast|test2TabsAndReturn|settings|hand the phone to them` |
| P2 | a11y-contrast |  | test2TabsAndReturn / settings | Contrast nearly passed (measured 3.5:1): "Set a caregiver code" | `a11y-contrast|test2TabsAndReturn|settings|set a caregiver code` |
| P2 | a11y-contrast |  | test2TabsAndReturn / settings | Contrast nearly passed (measured 3.5:1): "Set up Eleanor Wallner again" | `a11y-contrast|test2TabsAndReturn|settings|set up eleanor wallner again` |
| P2 | a11y-contrast |  | test2TabsAndReturn / settings | Contrast nearly passed (measured 3.5:1): "Upgrade to Elderhub Plus" | `a11y-contrast|test2TabsAndReturn|settings|upgrade to elderhub plus` |
| P2 | a11y-contrast |  | test2TabsAndReturn / today-after-background | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|test2TabsAndReturn|today-after-background|today.setup-card` |
| P2 | a11y-contrast |  | test2TabsAndReturn / today-after-relaunch | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|test2TabsAndReturn|today-after-relaunch|today.setup-card` |
| P2 | a11y-contrast |  | test2TabsAndReturn / today-after-tabs | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|test2TabsAndReturn|today-after-tabs|today.setup-card` |
| P2 | a11y-contrast |  | test2TabsAndReturn / today | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|test2TabsAndReturn|today|today.setup-card` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-after-relaunch | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-after-relaunch|today.setup-card` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | Contrast nearly passed (measured 4.0:1): "500 mg" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|# mg` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | Contrast nearly passed (measured 4.0:1): "7:00 AM" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|#:# am` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | Contrast failed (measured 4.0:1): "·" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|·` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | Contrast nearly passed (measured 4.0:1): "500 mg" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|# mg` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | Contrast nearly passed (measured 4.0:1): "7:00 AM" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|#:# am` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | Contrast failed (measured 4.0:1): "·" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|·` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | Contrast nearly passed (measured 4.0:1): "500 mg" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|# mg` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | Contrast nearly passed (measured 4.0:1): "7:00 AM" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|#:# am` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | Contrast failed (measured 4.0:1): "·" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|·` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-editor | Contrast failed (measured 3.5:1): "Add a time" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-editor|add a time` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-listed | Contrast nearly passed (measured 4.0:1): "7:00 AM" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-listed|#:# am` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-listed | Contrast nearly passed (measured 3.5:1): "Add medication" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-listed|add medication` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-listed | Contrast failed (measured 1.8:1): "None yet" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-listed|none yet` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-listed | Contrast failed (measured 1.8:1): "Nothing to do" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-listed|nothing to do` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-listed | Contrast nearly passed (measured 3.5:1): "person-detail.setup-card" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-listed|person-detail.setup-card` |
| P2 | a11y-contrast |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-today-empty | Contrast nearly passed (measured 4.0:1): "today.setup-card" | `a11y-contrast|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-today-empty|today.setup-card` |
| P2 | a11y-hit-region |  | test1FirstRecordToTodayAndUpgrade / details | Hit area is too small: "onboarding.details.finish-later" | `a11y-hit-region|test1FirstRecordToTodayAndUpgrade|details|onboarding.details.finish-later` |
| P2 | a11y-hit-region |  | test1FirstRecordToTodayAndUpgrade / sign-in | Hit area is too small: "Not now" | `a11y-hit-region|test1FirstRecordToTodayAndUpgrade|sign-in|not now` |
| P2 | a11y-hit-region |  | test1FirstRecordToTodayAndUpgrade / upgrade | Hit area is too small: "EULA" | `a11y-hit-region|test1FirstRecordToTodayAndUpgrade|upgrade|eula` |
| P2 | a11y-hit-region |  | test1FirstRecordToTodayAndUpgrade / upgrade | Hit area is too small: "Privacy" | `a11y-hit-region|test1FirstRecordToTodayAndUpgrade|upgrade|privacy` |
| P2 | a11y-hit-region |  | test1FirstRecordToTodayAndUpgrade / upgrade | Hit area is too small: "Restore" | `a11y-hit-region|test1FirstRecordToTodayAndUpgrade|upgrade|restore` |
| P2 | a11y-hit-region |  | test1FirstRecordToTodayAndUpgrade / upgrade | Hit area is too small: "Terms" | `a11y-hit-region|test1FirstRecordToTodayAndUpgrade|upgrade|terms` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | Hit area is too small: "500 mg" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|# mg` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | Hit area is too small: "7:00 AM" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|#:# am` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | Hit area is too small: "·" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|·` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | Hit area is too small: "500 mg" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|# mg` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | Hit area is too small: "7:00 AM" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|#:# am` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | Hit area is too small: "·" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|·` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | Hit area is too small: "500 mg" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|# mg` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | Hit area is too small: "7:00 AM" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|#:# am` |
| P2 | a11y-hit-region |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | Hit area is too small: "·" | `a11y-hit-region|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|·` |
| P2 | clipped |  | test1FirstRecordToTodayAndUpgrade / upgrade | button drawn as "Restor" but reads "Restore", cut off with no ellipsis (AX3 text only) | `clipped|test1FirstRecordToTodayAndUpgrade|upgrade|restore` |
| P2 | clipped |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | text drawn as "7:0" but reads "7:00 AM", cut off with no ellipsis (AX3 text only) | `clipped|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|#:# am` |
| P2 | clipped |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-due | text "Metformin" is broken across 2 lines: Met- / formin (AX3 text only) | `clipped|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-due|metformin` |
| P2 | clipped |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-kept | text "7:00 AM" is broken across 2 lines: 7:00A / M (AX3 text only) | `clipped|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-kept|#:# am` |
| P2 | clipped |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-dose-taken | text "7:00 AM" is broken across 2 lines: 7:00A / M (AX3 text only) | `clipped|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-dose-taken|#:# am` |
| P2 | cta-jump |  | test1FirstRecordToTodayAndUpgrade / details | the main button "onboarding.details.continue" is at y 686, 342 by 66; on "sign-in" it was at y 541, 334 by 52 (AX3 text only) | `cta-jump|test1FirstRecordToTodayAndUpgrade|details|onboarding.details.continue` |
| P2 | cta-jump |  | test1FirstRecordToTodayAndUpgrade / name | the main button "Continue" is at y 590, 334 by 66; on "fork" it was at y 567, 342 by 126 (AX3 text only) | `cta-jump|test1FirstRecordToTodayAndUpgrade|name|continue` |
| P2 | cta-jump |  | test1FirstRecordToTodayAndUpgrade / sign-in | the main button "Sign in with Apple" is at y 541, 334 by 52; on "name" it was at y 590, 334 by 66 (AX3 text only) | `cta-jump|test1FirstRecordToTodayAndUpgrade|sign-in|sign in with apple` |
| P2 | overlap |  | test1FirstRecordToTodayAndUpgrade / first-today | button "today.setup-card" overlaps "checklist" by 77% (AX3 text only) | `overlap|test1FirstRecordToTodayAndUpgrade|first-today|checklist / today.setup-card` |
| P2 | overlap |  | test1FirstRecordToTodayAndUpgrade / first-today | button "today.setup-card" overlaps "gear" by 34% (AX3 text only) | `overlap|test1FirstRecordToTodayAndUpgrade|first-today|gear / today.setup-card` |
| P2 | overlap |  | test1FirstRecordToTodayAndUpgrade / first-today | button "today.setup-card" overlaps "person.2" by 83% (AX3 text only) | `overlap|test1FirstRecordToTodayAndUpgrade|first-today|person.# / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-background | button "today.setup-card" overlaps "checklist" by 77% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-background|checklist / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-background | button "today.setup-card" overlaps "gear" by 34% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-background|gear / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-background | button "today.setup-card" overlaps "person.2" by 83% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-background|person.# / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-relaunch | button "today.setup-card" overlaps "checklist" by 77% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-relaunch|checklist / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-relaunch | button "today.setup-card" overlaps "gear" by 34% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-relaunch|gear / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-relaunch | button "today.setup-card" overlaps "person.2" by 83% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-relaunch|person.# / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-tabs | button "today.setup-card" overlaps "checklist" by 77% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-tabs|checklist / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-tabs | button "today.setup-card" overlaps "gear" by 34% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-tabs|gear / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today-after-tabs | button "today.setup-card" overlaps "person.2" by 83% (AX3 text only) | `overlap|test2TabsAndReturn|today-after-tabs|person.# / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today | button "today.setup-card" overlaps "checklist" by 77% (AX3 text only) | `overlap|test2TabsAndReturn|today|checklist / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today | button "today.setup-card" overlaps "gear" by 34% (AX3 text only) | `overlap|test2TabsAndReturn|today|gear / today.setup-card` |
| P2 | overlap |  | test2TabsAndReturn / today | button "today.setup-card" overlaps "person.2" by 83% (AX3 text only) | `overlap|test2TabsAndReturn|today|person.# / today.setup-card` |
| P2 | overlap |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-after-relaunch | button "today.setup-card" overlaps "checklist" by 92% (AX3 text only) | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-after-relaunch|checklist / today.setup-card` |
| P2 | overlap |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-after-relaunch | button "today.setup-card" overlaps "gear" by 40% (AX3 text only) | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-after-relaunch|gear / today.setup-card` |
| P2 | overlap |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-today-empty | button "today.setup-card" overlaps "checklist" by 77% (AX3 text only) | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-today-empty|checklist / today.setup-card` |
| P2 | overlap |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-today-empty | button "today.setup-card" overlaps "gear" by 34% (AX3 text only) | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-today-empty|gear / today.setup-card` |
| P2 | overlap |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-today-empty | button "today.setup-card" overlaps "person.2" by 83% (AX3 text only) | `overlap|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-today-empty|person.# / today.setup-card` |
| P2 | reduce-motion-ignored |  | all / all | with Reduce Motion on the journeys still moved for 43.7s against 52.5s without it (83%); check which animations ignore it | `reduce-motion-ignored|all|all|` |
| P2 | truncated |  | test1FirstRecordToTodayAndUpgrade / fork | button drawn as "I have an inv..." but reads "I have an invitation, Join a care circle from an email or code." (AX3 text only) | `truncated|test1FirstRecordToTodayAndUpgrade|fork|i have an invitation` |
| P2 | truncated |  | test1FirstRecordToTodayAndUpgrade / fork | button drawn as "Keep track..." but reads "Keep track of myself, Make a private care record for yourself." (AX3 text only) | `truncated|test1FirstRecordToTodayAndUpgrade|fork|keep track of myself` |
| P2 | truncated |  | test1FirstRecordToTodayAndUpgrade / fork | button drawn as "Start a care..." but reads "Start a care record, For a parent, partner, or anyone you help." (AX3 text only) | `truncated|test1FirstRecordToTodayAndUpgrade|fork|start a care record` |
| P2 | truncated |  | test1FirstRecordToTodayAndUpgrade / upgrade | button drawn as "Start My 7-Day Free Tr..." but reads "Start My 7-Day Free Trial" (AX3 text only) | `truncated|test1FirstRecordToTodayAndUpgrade|upgrade|paywall.continue` |
| P3 | a11y-element-description |  | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch / core-med-editor | Element has no description | `a11y-element-description|testCoreLoopAddMedicationTakeDoseSurvivesRelaunch|core-med-editor|` |

## Journeys

| Persona | Journey | Result | Seconds |
|---|---|---|---|
| newcomer | test1FirstRecordToTodayAndUpgrade | Passed | 96.01809799671173 |
| newcomer | test2TabsAndReturn | Passed | 105.70986700057983 |
| newcomer | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch | Passed | 116.08253109455109 |
| accessibility | test1FirstRecordToTodayAndUpgrade | Passed | 82.86468005180359 |
| accessibility | test2TabsAndReturn | Passed | 65.49360299110413 |
| accessibility | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch | Passed | 134.62945294380188 |
| reduce-motion | test1FirstRecordToTodayAndUpgrade | Passed | 94.09390997886658 |
| reduce-motion | test2TabsAndReturn | Passed | 81.1474289894104 |
| reduce-motion | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch | Passed | 119.76024806499481 |
| duo | test1FirstRecordToTodayAndUpgrade | Failed | 78.15167593955994 |
| duo | test2TabsAndReturn | Failed | 28.75176501274109 |
| duo | testCoreLoopAddMedicationTakeDoseSurvivesRelaunch | Failed | 74.12969601154327 |

## Motion

| Persona | Motion s | Windows | Candidates | Gaps > 25 ms | 60 fps |
|---|---|---|---|---|---|
| newcomer | 52.477 | 64 | 7 | 292 | True |
| accessibility | 71.532 | 66 | 11 | 296 | True |
| reduce-motion | 43.657 | 56 | 5 | 248 | True |

## Launch entrances to look at

Each launch's frames after the springboard zoom, left to right then down, 4 frames per
row at the recorded rate. A blank stretch, text that reflows, or content that arrives and
pushes the layout is a finding: `qa-gate ledger <repo> add`.

- [entrance-01-test1firstrecordtotodayandupgrade.png](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/newcomer/entrance-01-test1firstrecordtotodayandupgrade.png)
- [entrance-01-test1firstrecordtotodayandupgrade.png](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/accessibility/entrance-01-test1firstrecordtotodayandupgrade.png)
- [entrance-08-test1firstrecordtotodayandupgrade.png](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/accessibility/entrance-08-test1firstrecordtotodayandupgrade.png)
- [entrance-01-test1firstrecordtotodayandupgrade.png](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/reduce-motion/entrance-01-test1firstrecordtotodayandupgrade.png)
- [entrance-10-test2tabsandreturn.png](/Users/jackwallner/elderhub-ship/build/qa/b317d6e637c9/reduce-motion/entrance-10-test2tabsandreturn.png)

Skipped personas: german (app not localized).
