# Consent, App Review, privacy labels, legal exposure, and billing for family sync

Research brief for moving Aging (App Store title **Med List: Family Meds**) from
local-only SwiftData to a Supabase-backed family group with a proof-of-life
check-in feature. Written against `CLAUDE.md`, `aso-plan.md`, and
`docs/research/01-groups-rbac-rls.md`. Guideline text is quoted verbatim from
developer.apple.com where cited; anything I could not verify against a primary
source is labeled **Unverified**. Legal sections are analysis, not legal
advice — flagged again at point of use.

---

## Recommendations up front

**Consent and dignity (§1)**
- Build a "Who can see me" screen as a first-class, permanently-accessible
  surface for any linked subject: exactly who is in the group, their role, and
  what data class each role can read/write. Not a settings sub-page — reachable
  in one tap from the subject's home screen.
- Subject **can** leave the group or unlink unilaterally. Gate it behind a
  friction step (re-type a phrase, not just a confirm dialog) and a mandatory,
  immediate, unmuteable notification to every caregiver/owner — "Mom has left
  the family group and can no longer be reached through Med List." No cooling-off
  delay that blocks the action itself; the safety net is the announcement, not
  a lock on the door.
- For no-account recipients (dementia, no phone): they cannot consent in-app
  because there is no app on their end. Treat this explicitly as **surrogate
  entry by a caregiver**, not as the recipient's own action, and say so in the
  UI at the point of creation ("You're adding a profile for someone who won't
  use this app themselves"). Do not simulate consent that didn't happen.
- For capacity/dementia: do not build a consent flow that pretends to assess
  capacity — that is a clinical judgment call an indie consumer app has no
  business making. Follow the MyChart "proxy access" pattern (a caregiver
  attests, on the record, that they are authorized to act for this person) and
  say plainly in copy that this is a family/household decision the app is not
  adjudicating.

**App Review (§2)**
- 1.4.1 already governs Aging's disclaimer; extend the same "never claim to
  treat/cure/diagnose" posture to the check-in feature explicitly — a missed
  check-in is a *notification*, never a *diagnosis* or *emergency detection*.
- The single highest-risk phrase across the whole feature is any variant of
  "alert," "emergency," "911," "help is on the way," or "monitoring for your
  safety" applied to the check-in button or its push copy. Apple has no
  dedicated "life-safety claims" clause to quote, but 1.4.1's "could provide
  inaccurate data... used for diagnosing" scrutiny plus common rejection
  patterns for wellness/safety apps point the same direction: never imply the
  app detects an emergency or dispatches help. It notifies family members,
  nothing more. See Appendix for the exact boundary language.
- 5.1.1(v): every account holder (caregiver, owner, and any subject with a
  real login) needs in-app account deletion. Route it through the
  `delete_account` RPC already designed in `01-groups-rbac-rls.md` §4, which
  correctly separates "delete my account" from "delete the family's medical
  history" — Apple will reject a flow that can't delete the *account* even if
  shared data legitimately survives.
- 5.1.2/5.1.3: get affirmative, specific consent before a caregiver's phone
  syncs another named person's meds/conditions/vitals off-device, and disclose
  in the privacy policy that this data describes people who are not the
  device's account holder. This is not textually required by 5.1.2/5.1.3 (they
  are written around "the user's" data) but it is the honest reading of "you
  may not use, transmit, or share **someone's** personal data without first
  obtaining their permission" (5.1.2(i), verbatim below) applied to a third
  party's data flowing through your account.
- 4.8 does not apply unless a third-party social login (Google, Facebook,
  etc.) is offered. Supabase email/password or magic-link auth does not
  trigger it. If Google Sign-In is ever added, Sign in with Apple becomes
  mandatory as an equivalent option.

**Privacy labels and manifest (§3)**
- App Privacy answers move from "Data Not Collected" to declaring Health &
  Fitness data, Contact Info, Identifiers, and User Content, all **linked to
  the user**, **not used for tracking**, for the purposes of App Functionality
  (and Customer Support if applicable). Do this before submission — mismatched
  labels are an independent rejection/removal risk under 5.1.1(i).
- `PrivacyInfo.xcprivacy` needs `NSPrivacyCollectedDataTypes` entries added and
  probably a `UserDefaults` required-reason declaration once Supabase's and
  RevenueCat's SDKs are in the binary (both commonly touch `UserDefaults` for
  session caching) — verify with Xcode's build-time privacy report rather than
  guessing which reason code applies.

**Legal exposure (§4)**
- Not a HIPAA covered entity or business associate. Plainly a consumer app
  under FTC jurisdiction instead (and the FTC Health Breach Notification Rule
  is the closer analog than HIPAA — flagged as a real, underweighted
  requirement).
- Washington's My Health My Data Act is very likely **in scope** the moment
  any Washington resident's data (including a cared-for parent who never
  touched the app) is processed, and its private right of action via the
  Washington Consumer Protection Act is real, not theoretical (first suit
  filed Feb 2025). This is the legal risk I'd rate highest for a solo
  developer, above HIPAA and above GDPR. Treat the "specified purpose,
  granular, opt-in" consent bar as the actual bar for the whole app, not just
  for Washington users — it's cheaper to build one correct consent flow than
  to geofence.
- CCPA/CPRA: health data here is "sensitive personal information," and — this
  is the correction worth making explicit — the HIPAA/CMIA carve-out in CPRA
  does **not** rescue Aging, because that exemption requires the data to be
  governed by HIPAA or CMIA in the first place, and Aging is neither.
- GDPR/UK GDPR: territory-restrict Aging away from the EU/UK in App Store
  Connect. This meaningfully reduces exposure but is not a legal bright line
  (extraterritorial reach under GDPR Art. 3 doesn't key off store geo-fencing
  alone) — treat it as risk *reduction*, and don't market or actively target
  EU users regardless of storefront settings.
- The user-consents/data-subject-is-a-third-party wrinkle has no clean
  statutory answer for a solo developer. The practical mitigation is the same
  one used above: make the *caregiver* who enters someone else's data attest,
  at entry time, that they are authorized to do so on that person's behalf,
  log that attestation, and give every linked subject the transparency screen
  and revocation described in §1. This does not make the app compliant by
  citation; it is the standard of care a reasonable court or regulator would
  look for absent a bright-line rule.

**Billing (§6)**
- Key `subscriptions`/entitlement off **`group_id`**, not `user_id`. One payer
  (almost always the `owner`) purchases; every member's entitlement check
  resolves through group membership, not their own purchase history.
- Implement via RevenueCat's documented promotional-entitlement pattern
  (backend grants a promotional entitlement to every member's RevenueCat
  `app_user_id` on `INITIAL_PURCHASE`/`RENEWAL`, revokes on `EXPIRATION`/
  `CANCELLATION`) — this is what RevenueCat's own "team subscriptions" guidance
  describes, and it is compatible with Apple's rules because the purchase
  itself still goes through IAP; only the *unlock* is fanned out server-side.
  Apple's built-in Family Sharing for IAP is the wrong tool here: it shares
  based on iCloud Family Sharing membership, not this app's group membership,
  and gives no way to make one member a reduced-capability `subject` — don't
  use it as the sync mechanism, though there's no harm leaving it enabled as a
  secondary path for a caregiver's *own* separate account.
- The subject must **never** see a paywall on the check-in button. Enforce
  this as an unconditional rule in code, not a product convention: the
  check-in write path checks nothing but `care_recipients.linked_user_id`
  (already the design in `01-groups-rbac-rls.md` §2/§6) and the client never
  renders a paywall on that screen, full stop, regardless of the group's
  billing state.
- New free tier: **one care recipient, unlimited caregiver members on that
  recipient.** This preserves the existing paywall trigger (a second person)
  while accommodating the reality that a multi-sibling family isn't "extra
  users" in the old single-device sense — they're all managing the same one
  or two parents. The upgrade prompt lives on `PeopleView`/add-recipient flow,
  which structurally never appears on the subject's own screen.

---

## 1. Consent and dignity for the cared-for person

This is the part with the least written guidance because Apple, the states,
and RevenueCat all write their rules around "the user," and the load-bearing
fact of this app is that the most vulnerable person in it is sometimes not
capable of being "the user" in any meaningful sense. I'm reasoning this
through rather than citing, and flagging where I'm confident vs. where I'm
guessing.

### What the parent must be able to see about who is watching them

Three tiers of transparency, matched to what's technically true in each case:

1. **Linked subject (has an account, presses their own button).** They have
   a real session and real RLS visibility. Recommendation: a dedicated,
   always-reachable screen — call it "Who can see me" — listing every group
   member by name, their role (`caregiver`/`owner`), and, in plain language,
   what each role can read (their medications, doses, visits, vitals,
   emergency card) versus what's off-limits to them (nothing is off-limits to
   staff in the current v1 capability matrix — say that too, not just what's
   visible). This should read like a permissions screen, not legal boilerplate:
   "Sarah, Tom, and Jack can see your medications, appointments, and vitals.
   They get a notice if you don't check in." One line per person, one line per
   data category, no scrolling wall of text.
2. **No-account recipient (Dad, dementia, no phone).** There is no "their own
   screen" to put this on. The transparency obligation shifts entirely onto
   the caregiver who created the profile: at creation time, and periodically
   (e.g. a yearly re-attestation prompt, not just once-ever), the app should
   say plainly that this person cannot see or control what's tracked about
   them, and ask the creating caregiver to affirm they're entering this data
   as the person's authorized representative. This doesn't give Dad
   visibility he structurally cannot have (no phone, no login); it makes the
   *absence* of his consent visible to the family instead of quietly assumed.
3. **A subject who later loses the phone/account relationship** (e.g. the
   device breaks, they stop being able to operate it) reverts to case 2 —
   the `linked_user_id` unlink already designed in `01-groups-rbac-rls.md`
   §4 handles this cleanly on the data side; the product surface should
   proactively surface "Mom hasn't checked in and doesn't seem to be using
   her own login anymore — do you want to switch her to caregiver-managed
   tracking?" rather than silently degrading.

### The revocation dilemma

The tension as stated is real and doesn't resolve to a clean rule, so here is
a reasoned position, not a citation:

- **Unilateral revocation must be possible.** An app that cannot be left by
  the person it tracks is not a family tool, it's a monitoring tool with a
  consenting-adult's name on the account. Anthropic's own read of "dignity"
  in this brief and the general shape of adult social-care ethics (a
  competent adult's right to decline monitoring, even against their own
  interest) both point the same way: the subject's ability to leave has to be
  real, not cosmetic.
- **The safety-net-vanishing-silently failure mode is solved by loud
  announcement, not by a lock.** A revoke that's possible but *silent* is the
  actually dangerous design (family thinks the safety net is live; it isn't).
  A revoke that's *blocked* just converts the app into exactly the
  surveillance tool the dilemma worries about. So: make revocation
  **immediate and unblockable**, but require (a) a distinct, harder-than-normal
  confirmation step (typing "leave" or similar, not a single tap — this is
  the same asymmetry recommended for `leave_group`/`delete_group` in
  `01-groups-rbac-rls.md` §4) and (b) an **unmuteable, immediate push to every
  remaining owner/caregiver** the moment it happens: "Mom has left the family
  group. Med List can no longer track her check-ins or share her records with
  you." Loud, not silent; possible, not blocked.
- **A cooling-off period that delays the revocation itself is the wrong
  mechanism** — it just relocates the "silent gap" problem to inside the
  cooling-off window instead of removing it, and it's paternalistic in a way
  that undercuts the dignity argument. A cooling-off period that delays
  *re-inviting the same person back in* (to prevent a caregiver from
  re-adding someone who just left, without a fresh explicit invite) is
  reasonable and doesn't have that problem — that's a design choice for a
  future re-invite flow, not for the leave action.
- **No-account recipients cannot revoke because they never consented in the
  first place — there is nothing in-app to revoke.** The check on this side
  of the dilemma isn't a revoke button, it's the creation-time and periodic
  attestation from §"transparency" above, plus keeping the profile editable
  and deletable by any caregiver at any time (already true by capability
  matrix) so a family can stop tracking someone the moment it's no longer
  appropriate, without needing the tracked person's action to trigger it.

### Capacity and dementia: what the app should say and require

I looked at how regulated and consumer health products actually handle this,
because it's a solved-enough problem elsewhere that reinventing it badly
would be a mistake:

- **MyChart (Epic's patient portal, the closest real analog)** runs a formal
  "Diminished Capacity Proxy Access" process: a caregiver requests proxy
  access, and the health system requires **documentation showing medical
  necessity** before granting it, distinct from ordinary (competent-adult,
  self-authorized) proxy access. That's a clinical-grade, institution-backed
  process — a hospital's compliance department stands behind the
  determination. An indie app has no equivalent authority and should not
  pretend to.
- **Apple's own Family Setup** (Watch/Health for a family member without an
  iPhone) is the closer model for *scale*: it does not attempt to adjudicate
  capacity at all. It requires the pair to already be in the same iCloud
  Family Sharing group (an existing trust relationship, not assessed
  in-the-moment) and frames health-sharing as something the family member
  "may choose to share," revocable by them where they're capable of doing so.
  Apple sidesteps the capacity question by resting on the pre-existing family
  relationship rather than trying to verify consent quality.
- **What Aging should actually do**, combining both: don't build a capacity
  test. Build an **attestation**, not an assessment. The caregiver adding a
  no-account recipient checks a box and reads a specific sentence (see
  Appendix) affirming they are entering this data because the person can't or
  doesn't use the app themselves, that this is a family/household decision,
  and that the app is not verifying legal authority (power of attorney,
  guardianship, etc.) — that's on the family, not on Med List. This is
  honest about the limits: **it is not legal consent, it is not a
  determination of capacity, and it should never be described as either in
  the UI or the App Store listing.** It is a paper trail (`created_by` +
  timestamp, already in the schema per `01-groups-rbac-rls.md`) that the
  family made a deliberate choice, nothing more.
- Be honest in the doc, and I'll be honest here: **there is no version of
  this that is legally airtight for a solo developer.** Real surrogate
  consent for someone who's lost capacity is a power-of-attorney or
  guardianship question, and no app-level checkbox substitutes for that. The
  right posture is "we make the family's decision visible and logged, we
  don't adjudicate it" — not "we've solved consent for dementia patients."
  Don't let App Store copy or onboarding copy imply otherwise.

### Onboarding copy for the subject's side (see Appendix for exact strings)

The design goal: tell the subject, at signup, in one short screen, exactly
what leaves their control and who gets it, before they press anything that
creates the relationship. Structure: (1) who invited them and their role in
plain terms, (2) the two or three concrete things caregivers can see
(meds, check-ins, vitals — name the actual categories, not "your data"),
(3) that they can leave at any time and exactly what happens when they do,
(4) the disclaimer that this is not medical monitoring or an emergency
service. See Appendix.

---

## 2. App Review exposure

### 1.4.1 — extending the existing disclaimer to check-ins

> "Medical apps that could provide inaccurate data or information, or that
> could be used for diagnosing or treating patients may be reviewed with
> greater scrutiny... Apps should remind users to check with a doctor in
> addition to using the app and before making medical decisions."
> — [App Review Guidelines, 1.4.1](https://developer.apple.com/app-store/review/guidelines/)

The existing `CLAUDE.md` posture ("never claim to treat, cure or diagnose")
already covers meds/vitals/visits. The check-in feature adds a new surface
this clause reaches: a missed check-in is data the app is presenting about a
person's status, and if it's framed as a diagnosis-adjacent signal ("Mom may
be having a medical emergency") rather than a plain fact ("Mom hasn't pressed
the button"), it inherits exactly the scrutiny 1.4.1 describes. Keep it a
literal, mechanical statement of fact — button pressed / not pressed — never
an inference about wellbeing.

### Emergency/life-safety framing — no dedicated clause, so draw the line from adjacent text and known enforcement patterns

I could not find a standalone "you may not imply emergency response
capability" clause in the current Guidelines text (checked 1.4, 1.4.1, 1.4.3,
5.1). The closest textual anchor is 5.1.5 on location:

> "Location-based APIs shouldn't be used to provide emergency services..."
> — [App Review Guidelines, 5.1.5](https://developer.apple.com/app-store/review/guidelines/)

This is narrowly about location APIs, not a general rule, but it establishes
that Apple treats "this app provides emergency services" as a claim requiring
special handling it doesn't want indie apps making casually.
**Unverified**: I could not find a documented case of an app being rejected
specifically for "sounding like a medical alert system" in current search
results; the risk here is my judgment based on (a) how 1.4.1 is enforced for
adjacent accuracy claims, (b) how the FTC treats safety-app marketing claims
generally (a separate, non-Apple risk — see §4), and (c) plain product sense:
a family who reads "Med List will alert us if something's wrong" and doesn't
get a push because the parent's phone died overnight has been actively
misled about what the product does, which is the kind of complaint that
triggers manual review escalation regardless of which specific clause it's
filed under.

**Recommended language boundary** (see Appendix for exact strings):
- **Never use**: "emergency," "alert" (as a noun implying dispatch), "911,"
  "monitoring," "safety monitoring," "help is on the way," "medical alert,"
  "life alert," "SOS."
- **Always use instead**: "check-in," "notify," "let your family know,"
  "reminder to check on them yourself." The push notification body must
  describe an absence of information ("No check-in from Mom today"), not an
  inferred state ("Mom may need help").
- The App Store description, onboarding, and every push body should carry
  some form of "this is not a medical device, emergency service, or
  substitute for calling 911" near the check-in feature specifically, not
  just buried once in Settings.

### 5.1.1 and 5.1.1(v) — account deletion in a shared-data world

> "(v) Account Sign-In: If your app doesn't include significant account-based
> features, let people use it without a login. If your app supports account
> creation, you must also offer account deletion within the app."
> — [App Review Guidelines, 5.1.1](https://developer.apple.com/app-store/review/guidelines/)

Aging is adding real accounts, so this now applies to every role that logs
in: `owner`, `caregiver`, and any linked `subject`. The requirement is about
the *account*, not about every row that account ever touched — Apple wants
"delete my ability to log in and my personally-identifying data," not
"delete every fact this account ever wrote to a shared medical record." That
distinction is exactly what `01-groups-rbac-rls.md` §4's `delete_account` RPC
already implements (unlink `care_recipients.linked_user_id`, keep the shared
history, remove the membership row, then cascade `auth.users`). Ship it as
designed; it satisfies 5.1.1(v) as written. Two things worth adding on top:
- Surface deletion from **Settings**, not buried under support contact —
  Apple explicitly checks for an in-app deletion path, not "email us."
  (Already implied by "within the app" in the clause text above.)
- The confirmation copy for a sole `owner` with other members should say what
  actually happens (auto-promotion of the longest-tenured caregiver) — don't
  let a user believe deleting their account deletes the family's data if it
  doesn't; that's a support/trust problem even though it isn't itself a
  guideline violation.

### 5.1.2 and 5.1.3 — third-party health data

> "(i) Unless otherwise permitted by law, you may not use, transmit, or share
> someone's personal data without first obtaining their permission... You
> must clearly disclose where personal data will be shared with third
> parties... Apps that share user data without user consent or otherwise
> complying with data privacy laws may be removed from sale..."
> — [App Review Guidelines, 5.1.2](https://developer.apple.com/app-store/review/guidelines/)

> "(i) Apps may not use or disclose to third parties data gathered in the
> health, fitness, and medical research context... for advertising,
> marketing, or other use-based data mining purposes other than improving
> health management... You must disclose the specific health data that you
> are collecting from the device.
> (ii) Apps must not write false or inaccurate data into HealthKit or any
> other medical research or health management apps, and may not store
> personal health information in iCloud."
> — [App Review Guidelines, 5.1.3](https://developer.apple.com/app-store/review/guidelines/)

Two observations specific to this app:
1. **5.1.2(i)'s "someone's personal data," not "the user's,"** is the textual
   hook for the third-party-subject problem. Apple's guideline as written
   already contemplates data about people other than the account holder — it
   just doesn't spell out a mechanism, which leaves "get permission from the
   person whose data it is" as the literal reading and "have the caregiver
   attest they're authorized to act for the subject" as the only practical
   implementation when the subject has no account. This is the same
   attestation mechanism recommended in §1; it does double duty as the App
   Review answer and the ethical answer.
2. **5.1.3(ii)'s "may not store personal health information in iCloud"** is
   specifically about *Apple's* iCloud, not about Supabase/Postgres — this
   app is fine on that specific point since it's moving to its own backend,
   not iCloud. Don't accidentally trip it later if a CloudKit-based backup
   feature is ever added for the local store.
3. Aging is not gathering data *from HealthKit* (no HealthKit integration
   exists per `CLAUDE.md`), so 5.1.3(i)'s HealthKit-specific restriction on
   downstream use doesn't technically attach — but the same *norm* (health
   data only for the purpose the user understood, never for ads/marketing/
   data-mining) is worth holding the app to anyway, and is required
   separately by 5.1.2(i)'s general "permission first" rule plus the state
   laws in §4.

### 4.8 — Sign in with Apple

> "Apps that use a third-party or social login service (such as Facebook
> Login, Google Sign-In...) to set up or authenticate the user's primary
> account with the app must also offer as an equivalent option another login
> service with the following features: the login service limits data
> collection to the user's name and email address; the login service allows
> users to keep their email address private... Another login service is not
> required if: Your app exclusively uses your company's own account setup and
> sign-in systems."
> — [App Review Guidelines, 4.8](https://developer.apple.com/app-store/review/guidelines/)

Supabase email/password or magic-link auth is "your company's own account
setup" for 4.8's purposes (it's not a *social* login provider) — **not
required**. If a Google/Facebook sign-in button is ever added for
convenience, Sign in with Apple becomes mandatory at that point, not before.

### Other exposure worth flagging

- **4.5.4 (push notifications)**: "Push Notifications must not be required
  for the app to function, and should not be used to send sensitive personal
  or confidential information." ([source](https://developer.apple.com/app-store/review/guidelines/))
  The escalation push ("No check-in from Mom today") names a real person and
  implies a health-adjacent status. Keep the body generic (Appendix has exact
  wording) and never put medication names, diagnoses, or vitals values in a
  push notification body — that's squarely what 4.5.4 is warning against, and
  it also shows up on a locked screen where anyone can read it.
- **Regulated Medical Device declaration** (already flagged in `CLAUDE.md`):
  the check-in feature does not change this — it's still a UI-only,
  submission-time ASC declaration, not something exposed via the API. No new
  action beyond keeping it set correctly.
- **Rejection patterns I could not source directly** (labeled unverified,
  reasoning from general App Review behavior rather than a specific citation):
  apps that gate core safety-adjacent functionality behind a paywall get
  flagged in review notes even when no single guideline number is cited —
  this is the practical argument, independent of the legal/ethical one in
  §1, for never letting the subject's check-in button hit a paywall.

---

## 3. Privacy labels and privacy manifest

### App Privacy (Nutrition Label) — what changes

Today Aging almost certainly declares "Data Not Collected" across the board
(local-only, no network). Once meds/conditions/allergies/visits/vitals/
check-ins sync to Supabase and APNs tokens are stored server-side, the
correct declaration set becomes:

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Health & Fitness → Health | Yes | Yes | No | App Functionality |
| Contact Info → Name | Yes (display name, care-recipient name) | Yes | No | App Functionality |
| Contact Info → Phone/Email | Yes (auth identity) | Yes | No | App Functionality, Account/authentication |
| Identifiers → User ID | Yes | Yes | No | App Functionality |
| Identifiers → Device ID | Yes (APNs token) | Yes | No | App Functionality (push) |
| User Content → Other User Content | Yes (visit notes, free-text fields) | Yes | No | App Functionality |
| Diagnostics → Crash Data (if any crash reporter is in the stack) | Depends on SDKs actually shipped | Yes/No per SDK | No | App Functionality |

Apple's own definitions, for the "linked" and "tracking" columns:

> "You'll need to identify whether each data type is linked to the user's
> identity (via their account, device, or other details) by you and/or your
> third-party partners."
> — [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

> "'Tracking' refers to linking data collected from your app about a
> particular end-user or device... with Third-Party Data for targeted
> advertising or advertising measurement purposes, or sharing data collected
> from your app about a particular end-user or device with a data broker."
> — [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

Everything above is linked (it's tied to a real Supabase auth identity) and
none of it is tracking under Apple's definition (no ad targeting, no data
broker sharing) — so `NSPrivacyTracking` stays `false`, but the collected-data
list expands substantially from empty. Get this right before submission:
mismatched labels are reviewable independently under 5.1.1(i)'s privacy
policy requirements and have been a documented source of app removals
industry-wide (general knowledge, not from a specific fetched source here —
verify current enforcement posture at submission time).

**One nuance specific to this app**: the Health & Fitness data collected
includes data *about* people other than the account holder (a caregiver's
account transmits their parent's medications). Apple's label schema has no
separate "data about someone else" checkbox — it's declared the same as any
other Health data, linked to the account that transmits it. The privacy
*policy* (prose, not the label) is where this needs to be spelled out in
plain English (see §4/Appendix), since the structured label can't express it.

### `PrivacyInfo.xcprivacy` changes

1. **`NSPrivacyCollectedDataTypes`**: add entries mirroring the table above —
   at minimum `NSPrivacyCollectedDataTypeHealth`, `NSPrivacyCollectedDataTypeName`,
   `NSPrivacyCollectedDataTypeEmailAddress` and/or `NSPrivacyCollectedDataTypePhoneNumber`
   (whichever Supabase auth method ships), `NSPrivacyCollectedDataTypeUserID`,
   `NSPrivacyCollectedDataTypeDeviceID` (APNs token), `NSPrivacyCollectedDataTypeOtherUserContent`
   (visit notes / free text), each with `NSPrivacyCollectedDataTypeLinked: true`
   and `NSPrivacyCollectedDataTypeTracking: false`, purpose
   `NSPrivacyCollectedDataTypePurposeAppFunctionality`.
2. **Required-reason API declarations**: check the actual build's generated
   privacy report (Xcode → Product → Analyze, or the aggregated report at
   archive time) rather than guessing, but the most likely new trigger is
   **`NSPrivacyAccessedAPICategoryUserDefaults`**, because both the Supabase
   Swift SDK and RevenueCat's SDK commonly persist session/cache state via
   `UserDefaults`. **Unverified** at the specific-reason-code level — I could
   not get a verbatim current list of the five required-reason categories and
   their approved reason codes from Apple's docs in this session (the fetch
   returned only a page title, likely JS-rendered content); confirm the exact
   category (File Timestamp / System Boot Time / Disk Space / Active Keyboard
   / User Defaults) and the specific approved reason code against
   `https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing-use-of-required-reason-api`
   directly in Xcode or a browser before shipping, and against each
   third-party SDK's own shipped `PrivacyInfo.xcprivacy` (Supabase's and
   RevenueCat's SDKs should already ship their own manifests declaring their
   own required-reason usage — verify they're present in the resolved SPM
   packages rather than writing declarations for their internals yourself).
3. Since push notifications and a background check-in escalation job are new,
   double check whether any background-refresh or notification-service
   extension code touches disk space or file timestamps directly (e.g. a
   notification service extension caching payloads) — if one gets added,
   it needs its own manifest.

---

## 4. Legal exposure beyond Apple

**Not legal advice** — this is analysis to prioritize what to take to a real
lawyer before or shortly after this feature ships, given the scale of a solo
developer's practical risk tolerance.

### HIPAA

Plainly **not** a covered entity or business associate. HHS's own framing:

> "A covered entity is a health care provider, health plan, or health care
> clearinghouse... A business associate is a person or entity... who performs
> functions or activities on behalf of, or provides certain services to, a
> covered entity that involve access... to protected health information."
> — [HHS, Covered Entities and Business Associates](https://www.hhs.gov/hipaa/for-professionals/covered-entities/index.html)

Aging doesn't transact with a doctor, insurer, clearinghouse, or health plan
on the user's behalf — it's a consumer record-keeping tool the family uses
independently. That places it outside HIPAA by construction, not by careful
design.

**What actually applies instead: the FTC Health Breach Notification Rule.**
This is the piece I'd flag as most likely to be underweighted relative to
HIPAA, precisely because "not HIPAA" gets read as "not regulated," which is
wrong. The FTC rule requires notice to consumers, the FTC, and sometimes media
on a breach of unsecured identifiable health information held by a vendor of
personal health records or a related third party — the FTC has explicitly
applied it to consumer health apps in enforcement actions (GoodRx, BetterHelp,
Premom) in recent years. **Unverified in this session at the level of exact
current rule text** — I did not fetch the rule text directly; before launch,
read 16 CFR Part 318 and the FTC's own guidance on which apps qualify as
"health apps" under it, because Aging (multi-person health records, synced
to a backend) is a plausible fit for the rule's intent even though it isn't
a HIPAA entity.

### Washington's My Health My Data Act (MHMDA) — the one I'd weight highest

> "Consumer health data" — "personal information that is linked or reasonably
> linkable to a consumer and that identifies the consumer's past, present, or
> future physical or mental health status," including conditions, treatments,
> and biometric/genetic data.
>
> "Consent" — "a clear affirmative act that signifies a consumer's freely
> given, specific, informed, opt-in, voluntary, and unambiguous agreement."
> Consent cannot be obtained through general terms-of-service acceptance or
> dark patterns.
>
> A "regulated entity" is any legal entity that conducts business in
> Washington or provides products/services targeted to Washington consumers
> and determines the purposes and means of collecting/processing consumer
> health data.
> — RCW 19.373 (Washington My Health My Data Act), summarized from statute
> text via [apps.leg.wa.gov](https://apps.leg.wa.gov/rcw/default.aspx?cite=19.373&full=true)

Applicability reasoning, not a citation: MHMDA's territorial trigger is
"conducts business in Washington or targets Washington consumers," which is
satisfied the instant one Washington-resident family uses the app — there is
no revenue or size threshold like CCPA's. Aging syncing a Washington parent's
medications and check-in status to Postgres is squarely "consumer health
data" under the statute's own definition. Two aggravating facts specific to
this app:
- **Consent has to be "specific" and "opt-in," and general ToS acceptance
  doesn't satisfy it.** A blanket "I agree to Terms" checkbox at signup is
  not MHMDA-adequate consent for syncing another family member's medication
  list; the statute's own language ("clear affirmative act," "specific,"
  "opt-in") points toward the same granular, named-category consent
  recommended in §1/§2 on independent App Review and ethical grounds — one
  well-built consent screen satisfies all three concerns at once.
- **The third-party-subject problem has no MHMDA carve-out.** My search found
  no provision letting a "regulated entity" treat a family member's proxy
  action as the data subject's own consent (**unverified**, but multiple
  practitioner sources agree MHMDA does not build in an "authorized agent"
  concept the way CCPA does for opt-out requests) — meaning the parent whose
  medications sync is, on a strict reading, a "consumer" under MHMDA whose
  consent the statute contemplates being obtained directly, not via the
  caregiver. This is very likely unworkable to satisfy literally for a
  no-account, no-phone recipient, which is exactly the scenario in this
  brief. The realistic mitigation is documentation (the caregiver
  attestation from §1) plus minimizing what's collected about the
  no-account recipient to what's operationally necessary, not a claim of
  full statutory compliance.
- **Enforcement**: "any violation of the Act is a per se violation of the
  Washington Consumer Protection Act... enforced by the Attorney General as
  well as through private action," and the first class action under MHMDA
  was filed February 10, 2025. There's no fixed statutory damages figure —
  a plaintiff has to show actual damages to "business or property" — which
  raises the bar for a lone consumer suing over a bug but does not remove
  AG enforcement risk, and per-se-CPA-violation status means normal
  Washington consumer-protection remedies (including fee-shifting) are live.
  — [Clark Hill, "It's Here"](https://www.clarkhill.com/news-events/news/its-here-the-who-what-and-how-of-washingtons-new-my-health-my-data-act-and-its-private-right-of-action/), [WilmerHale, first MHMDA lawsuit](https://www.wilmerhale.com/en/insights/blogs/wilmerhale-privacy-and-cybersecurity-law/20250220-first-lawsuit-filed-under-washingtons-my-health-my-data-act)

Comparable states as of this research: **Nevada** has a similar consumer
health data law; **Connecticut** amended its comprehensive privacy law to add
health-data-specific provisions (effective July 1, 2026); **New York**'s
Health Information Privacy Act was pending signature at last check.
**Unverified — confirm current status of each before relying on this list**;
state privacy legislation moves quickly and this research pass is a snapshot.

### CCPA/CPRA

Health data here is "sensitive personal information" under CPRA. The
important correction to a common misreading (which a search summary
initially surfaced and which I want to flag explicitly rather than pass
through uncritically): **CPRA's HIPAA/CMIA carve-out does not exempt Aging.**
The exemption applies to data *already governed by* HIPAA or California's
Confidentiality of Medical Information Act (CMIA — which covers licensed
California healthcare providers), not to "any data that happens to be
medical in nature." Since Aging is neither a HIPAA entity (§ above) nor a
CMIA-covered provider, its health data is **not** exempt and falls under
ordinary CPRA sensitive-personal-information treatment: the right to limit
use/disclosure, opt-out mechanics, and CPRA's general notice-at-collection
and purpose-limitation requirements apply in full.

### GDPR / UK GDPR

Applies if EU/UK residents use the app, regardless of where Aging's servers
or developer are based, once the app "targets" or "monitors" them (GDPR Art.
3). Health data is Art. 9 "special category" data, requiring both an Art. 6
lawful basis and a separate Art. 9(2) condition — explicit consent is the
practical one here, and it has to be tied to specific, clearly-communicated
purposes, not blanket ToS acceptance (same shape of requirement as MHMDA
above, which is a useful consolation: one well-built consent flow serves
both).

**Practical recommendation**: territory-restrict Aging to exclude the EU/UK
in App Store Connect availability settings, as the brief notes is an option.
This is a real risk *reduction* — it removes App Store distribution as an
acquisition channel into those markets — but it is not a legal safe harbor by
itself; GDPR's extraterritorial trigger is about targeting/monitoring
behavior, not store geo-fencing, so don't market toward EU/UK users or
knowingly onboard EU-resident families through other channels while treating
the store restriction as sufficient.

### The user-consents / data-subject-is-a-third-party wrinkle, across all of the above

Every regime above (MHMDA, CCPA, GDPR) is written assuming the person
providing consent and the person the data is about are the same. None of
them, on the sources found in this pass, cleanly solves "my adult child
entered my medication list into an app I've never opened." The realistic
posture for a solo developer, stated plainly:

- **You cannot make this fully compliant by clever consent-flow design** —
  the statutes don't contemplate proxy data entry cleanly enough for that.
- **You can make it defensible**: require and log a caregiver attestation of
  authorization at the point a no-account person's data is first entered
  (same mechanism as §1/§2), minimize what's collected about that person to
  what the product actually needs, give any linked subject who *does* get an
  account full visibility and an easy, working exit, and put a clear,
  specific privacy policy in front of every user describing exactly this
  situation in plain language rather than generic boilerplate.
- **This is a genuine unresolved tension in the product, not a bug to
  engineer away.** Say that in the terms of service, not just internally:
  users should be told, in plain words, that entering another person's health
  information is their responsibility to have the right to do, not something
  the app verifies.

### Privacy policy and terms — hosting

Aging has no marketing site. Bond's pattern (GitHub Pages served from
`docs/`, per `/Users/jackwallner/bond/docs/`) is a reasonable template to
follow structurally, but the *content* needs to be specific to Aging's data
flows, not copied: it must name the actual data categories synced (meds,
conditions, allergies, visits, vitals, check-ins), state plainly that some
of that data describes people other than the account holder, describe the
Supabase-hosted backend, cover account deletion mechanics and what survives
it (per 5.1.1(i)'s explicit requirement to "explain retention/deletion
policies and describe how a user can revoke consent and/or request deletion
of the user's data"), and include the granular, specific-purpose consent
language MHMDA/GDPR require rather than industry-boilerplate consent
language. See Appendix for a starting structure.

---

## 5. Liability copy for the check-in feature

Design goal: short enough that a stressed adult child actually reads it, and
precise enough that "the app said it would alert us" can never become a
believable complaint. Full strings are in the Appendix; the principles:

- **State the mechanism, not the promise.** "We'll notify you if no check-in
  arrives" is a mechanism. "We'll alert you if something's wrong" is a
  promise about the world the app cannot verify.
- **Name the failure modes the family should actually worry about** (dead
  phone battery, no signal, forgot, app not open) in the disclaimer once, so
  it's not a surprise when the notification is a false alarm or a missed
  real event — both directions of failure are real and should be named.
- **Every escalation push repeats the boundary**, briefly, because it's the
  moment of highest anxiety and highest risk of over-reading the message —
  see Appendix push body.
- **The disclaimer belongs in three places**: onboarding (when the check-in
  feature is first configured), Settings (persistent, matching the existing
  pattern for the medical disclaimer), and the emergency card (already a
  precedent per `CLAUDE.md`).

---

## 6. Billing across a group

### Does Apple permit one account's purchase to unlock functionality for other accounts?

Yes, with a specific mechanism required. Guideline 3.1.1 requires that
**unlocking features/functionality within the app must go through In-App
Purchase** — it does not say the purchaser and the unlocked user must be the
same Apple ID:

> "If you want to unlock features or functionality within your app... you
> must use in-app purchase."
> — [App Review Guidelines, 3.1.1](https://developer.apple.com/app-store/review/guidelines/)

This is exactly the shape that lets Slack-, Notion-, and Basecamp-style
"one admin pays, teammates get seats free" apps exist: the *purchase* is a
real IAP transaction by one account; the *unlock* for other accounts is the
app's own server-side entitlement logic, which Apple's guidelines don't
regulate (they regulate the purchase mechanism, not what your backend does
with the result). Two things to keep clean:
- Don't let a second Apple ID *also* be charged for the same access — that's
  the "duplicate payment" pattern Apple's cross-app subscription-sharing
  language explicitly warns against in the streaming-games context, and it's
  bad practice generally.
- The subscription must still genuinely be purchasable and manageable by the
  one Apple ID that buys it (App Store subscription management UI, refunds,
  etc. all still apply to that one account).

**Apple's built-in Family Sharing for IAP is a different, narrower mechanism
and the wrong fit here.** It only shares eligible non-consumable IAPs and
auto-renewable subscriptions among people who are *already* in the same
iCloud Family Sharing group — a decision made at the OS/Apple-ID level, not
this app's group model — and it's all-or-nothing (a shared subscriber gets
full access, there's no way to make one Family-Sharing member a reduced-
capability `subject`). It also doesn't help at all for the actual target
scenario here: three adult siblings coordinating care for a parent are
routinely *not* in the same iCloud family, and the parent (a `subject`)
should get reduced capability, not the same access as a paying caregiver.
Leaving Family Sharing eligibility on for the IAP products is harmless (it
just gives a caregiver's own separate account a second path to the same
entitlement if they happen to share an Apple family with another caregiver)
but it cannot be the sync mechanism for group access.

### What RevenueCat supports

RevenueCat's documented pattern for this ("team subscriptions" /
one-to-many entitlements) is: the paying user completes a normal IAP
purchase against their own RevenueCat `app_user_id`; your backend listens for
RevenueCat webhooks (`INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`,
`CANCELLATION`) and calls RevenueCat's **Grant a Promotional Entitlement**
REST API to grant the same entitlement to every other member's
`app_user_id`, tracked against your own database of group membership —
re-granting on renewal, revoking on expiration/cancellation.
([RevenueCat community, "Enabling Team Subscriptions with RevenueCat"](https://community.revenuecat.com/featured-articles-55/enabling-team-subscriptions-with-revenuecat-3366);
[RevenueCat, Entitlements docs](https://www.revenuecat.com/docs/getting-started/entitlements))
This is a documented, first-party-recommended pattern, not a workaround.

### Recommendation for Aging specifically

- **`subscriptions` keys off `group_id`.** Add a `group_id` foreign key (or
  equivalent) on whatever subscription-state table gets ported over from
  RevenueCat webhooks, mirroring the flag already raised as open in
  `01-groups-rbac-rls.md`'s anti-patterns section. The client-side
  entitlement check (`StoreService.isPro` today) becomes "is *this group*
  entitled," resolved via the group's payer state, not "is *this device's
  account* entitled."
- **The payer is the `owner`** by default (matches the existing capability
  matrix's "Billing / subscription management: Y for owner, N for
  caregiver/subject" row already specified in `01-groups-rbac-rls.md` §2).
  A `caregiver` should be allowed to become payer too (siblings split who
  actually holds the card in real families), but ownership of the
  *subscription* and ownership of the *group* don't need to be forced
  identical — track a `paying_member_id` separate from `groups.owner`, so
  "who pays" can change without a full ownership transfer.
- **A non-paying member** (any `caregiver` in a group whose entitlement comes
  from someone else's purchase) sees the full app — this is the whole point
  of group-level billing; individually re-paywalling caregivers who didn't
  personally purchase defeats the "one payer, whole family" value
  proposition RevenueCat's own pattern exists to support.
- **The subject never sees a paywall, unconditionally.** This isn't just a
  product nicety, it's a correctness requirement given the headline feature:
  a parent who was told "press this button every morning" and then hits a
  paywall on the button itself is exactly the failure mode this whole
  feature exists to prevent. Implementation guarantee: the check-in write
  path's authorization (per `01-groups-rbac-rls.md` §2/§6) is keyed on
  `care_recipients.linked_user_id = auth.uid()`, which has **no billing
  check anywhere in it** — the RLS policy and the RPC don't reference
  `group_id`'s subscription state at all, so there's no code path for a
  paywall to attach to even by accident. Enforce the same absence on the
  client: the subject's check-in screen should not import or reference
  `StoreService` at all.
- **New free tier: one care recipient, unlimited group members on that
  recipient.** The old "one person" free tier doesn't map cleanly onto "a
  group of people jointly managing one or two parents" — a family of three
  siblings all tracking Mom for free, then hitting a wall the moment they
  add Dad too, preserves the meaningful paywall trigger (more people being
  *tracked*, which is where the real backend/storage cost and the real
  product value scale) without punishing a family for being a family of more
  than one *caregiver*.
- **Upgrade prompt placement**: on the "add a care recipient" flow
  (`PeopleView`'s existing trigger point, now scoped to recipients not
  members) and, secondarily, on the invite-a-member flow only if the group
  is somehow both free-tier and already at its recipient cap when a new
  invite is sent (edge case, low priority). Never on the check-in screen,
  never on any screen reachable only by a `subject` role — enforce this as a
  code-review checklist item given how much the button's trustworthiness
  depends on it.

---

## Appendix: ready-to-use copy

### Onboarding — subject's "who can see you" screen (first-run, before any data syncs)

> **Sarah invited you to Med List**
> Sarah, Tom, and Jack will be able to see:
> - Your medications and when you take them
> - Your doctor visit notes and vitals
> - Whether you've checked in today
>
> They'll get a notice if you don't check in. You can leave this group any
> time from Settings — they'll be told right away if you do.
>
> This app is not a medical device and does not detect emergencies. It's a
> way to keep your family in the loop.
>
> [Join the family group]   [Not now]

### Persistent "Who can see me" screen (Settings, reachable in one tap)

> **Who can see me**
> - **Sarah** (caregiver) — meds, visits, vitals, check-ins
> - **Tom** (caregiver) — meds, visits, vitals, check-ins
> - **Jack** (owner) — meds, visits, vitals, check-ins, and manages billing
>
> **Leave this group**
> Leaving stops everyone above from seeing your information or your
> check-ins. They'll be notified immediately that you've left. Your past
> records stay with the family's history; your account is no longer linked
> to them.

### Leave-confirmation friction step

> Type **LEAVE** to confirm. Sarah, Tom, and Jack will be notified right
> away that you're no longer sharing your information or check-ins with
> them.
> [_______] [Cancel] [Leave Group]

### Caregiver attestation — adding a no-account recipient (Dad, dementia, no phone)

> **You're creating a profile for someone who won't use this app**
> Dad won't have his own login or be able to see or manage what's tracked
> here. By continuing, you're confirming that you're entering this
> information as his family, because he isn't able to manage it himself.
>
> Med List doesn't verify legal authority (power of attorney, guardianship,
> etc.) — that's between your family and, if needed, your lawyer. We just
> keep a record that you added this profile and when.
>
> [I understand — Create Dad's profile]

### Check-in feature disclaimer (onboarding + Settings + emergency card)

> **About check-ins**
> The check-in button lets [Name] tell their family they're okay with one
> tap. If no check-in arrives in the time window you set, Med List sends a
> notification — nothing more.
>
> Med List is not a medical device, a medical alert system, or an emergency
> service. It does not call 911, does not detect falls or emergencies, and
> cannot guarantee a notification will arrive (a dead phone, no signal, or a
> forgotten check-in all look the same to us). If you're worried about
> [Name]'s safety right now, call them or call 911 — don't wait on this app.

### Escalation push notification body

> "No check-in from [Name] today. This isn't an emergency alert — check in
> with them yourself."

(Title: "No check-in from [Name]" — body carries the boundary language every
time, not just once at onboarding, because this is the highest-anxiety
moment and the easiest to over-read.)

### App Store description sentences (safe, inside the rules)

> "Get a notification if [Name] hasn't checked in — a simple way to know
> they're okay without a phone call every day."
>
> "Med List is not a medical device and does not provide emergency response.
> It's a private way for your family to track meds, records, and daily
> check-ins together."

Avoid entirely in ASC metadata, onboarding, or push copy: *alert, emergency,
911, SOS, life alert, monitoring, safety monitoring, help is on the way,
medical device* (except in the negation "not a medical device").

### Privacy policy — structural outline (host from `docs/`, GitHub Pages, per Bond's pattern)

1. What we collect: name the exact categories (medications, conditions,
   allergies, doctor visit notes, vitals, check-in timestamps, account
   email/phone, push token) — no generic "usage data" language.
2. **A dedicated paragraph**: "Some of the information in Med List describes
   people other than the account holder — for example, a family member's
   medications entered by their caregiver. If you are the person being
   described and did not create your own account, the person who added your
   information is responsible for having the right to do so."
3. Where it's stored (Supabase/Postgres, region), that it is not stored in
   Apple iCloud, and that it's not shared with advertisers or data brokers.
4. Consent mechanics: what specific consent is asked for and when
   (account creation, first sync of another person's data, check-in
   feature setup) — matches MHMDA/GDPR's "specific, opt-in, not
   bundled-into-ToS" requirement.
5. Retention and deletion: what account deletion does and does not remove
   (mirrors the 5.1.1(i) requirement verbatim — "explain retention/deletion
   policies and describe how a user can revoke consent and/or request
   deletion").
6. A named contact method for privacy requests (even a solo developer's
   email is sufficient, but it must exist and be monitored).
7. State-specific rights sections for Washington (MHMDA) and California
   (CCPA/CPRA) at minimum, written to the actual granular-consent and
   right-to-delete mechanics implemented, not boilerplate.
