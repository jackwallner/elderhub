# Aging app: ASO scoping + scope decision

Bundle: `com.jackwallner.aging` · RC app: `appl_dvyPWLaZxKyjLUrFVzDynNGjVGb`
Astro research app: id `121` ("Aging (pre-launch research)"), 94 keywords, US.
Date: 2026-07-31

> **2026-08-05 — superseded in part.** The app is now **Elderhub: Family Care Log**.
> The findings below are unchanged and still worth reading: the category really is a
> graveyard, and `caregiver` / `senior care` / `home care` really are wrong-intent
> traps that must stay out of every ASC field. What changed is the *conclusion drawn
> from them*. This plan said: since only `medication list` has demand, buy the title
> with it. The product then grew past meds-only (tasks, visits, vitals, providers,
> check-in, notes), and the call is that this app will not be an organic-search hit
> either way, so the title now carries the brand and the real job instead of a
> pop-23 keyword. Acquisition is to be built off-store. The "Metadata direction"
> section below is the part that no longer applies.

## Verdict up front

**Do not build "a hub for families coordinating an aging parent's care."** The category
has no App Store search demand, and ~30 apps have already built exactly that in the last
18 months with no traction. There is no organic acquisition channel for it.

There *is* a viable app adjacent to it. See "Recommended scope".

---

## Finding 1: the entire eldercare vocabulary is at the popularity floor

Astro's popularity floor is 5 (= no measurable search volume). Every single term that
describes this concept sits on the floor:

| keyword | pop | diff |
|---|---|---|
| family caregiver | 5 | 5 |
| elderly care | 5 | 37 |
| elder care | 5 | 41 |
| caregiving | 5 | 46 |
| aging parents | 5 | 15 |
| aging parent | 5 | 9 |
| caring for aging parents | 5 | 7 |
| elderly parents | 5 | 5 |
| care coordination | 5 | 11 |
| care team | 5 | 9 |
| caregiver support | 5 | 11 |
| respite care | 5 | 13 |
| long distance caregiving | 5 | 13 |
| sandwich generation | 5 | 21 |
| aging in place | 5 | 13 |
| elder care app | 5 | 11 |
| **alzheimers** | 5 | 13 |
| **dementia care** | 5 | 5 |
| **hospice** | 5 | 5 |
| memory care | 5 | 9 |
| senior safety | 5 | 17 |
| fall detection | 5 | 11 |
| elderly monitoring | 5 | 9 |
| power of attorney | 5 | 45 |
| advance directive | 5 | 9 |
| estate planning | 5 | 17 |
| end of life planning | 5 | 7 |

The low difficulty numbers are not opportunity. They are the signature of a term nobody
searches: no one bothers to compete for it. `caring for aging parents` at diff 7 is
winnable and worth nothing.

## Finding 2: the supply side confirms it. This is a graveyard.

Apps found across the `aging parents` / `family caregiver` / `care coordination` /
`elderly care` SERPs, with rating counts:

Elderella 4 · Caily 12 · CareMynd 0 · Kinnecta 0 · MyParentHQ 0 · Kin 0 · Hyey 4 ·
CircleCare 4 · Brelti 3 · Carewall 0 · WeCare 0 · Rally 0 · KinPass 0 · Warm 0 ·
Tessa Family 0 · Buddy of Parents 0 · Family Visits 0 · Journey Together 8 ·
CareSync 1 · CareGiver+ 1 · Family Caregiver 3 · Trualta 1 · United Care Force 0 ·
Thrive Together 2 · Donna 4 · Kyoiru 0 · Elsy 1 · SeniorSafe 0 · Place My Parent 0

Nearly all shipped in the last 12-18 months. The all-time ceiling in this neighborhood
is **Caring Village at 35 ratings** (live since 2016) and **tendercare at 38**. Ten years
of the category and nobody has cleared 40 ratings. That is not a gap in the market, it is
a market that does not transact on the App Store.

## Finding 3: `caregiver` (pop 52) is a false friend

It is the only high-popularity term in the space and it fails the SERP intent guardrail
completely. Top 20 is two intents, neither of them ours:

- **Job seekers**: Care.com Caregiver (149k ratings), Care.com (39k), Instawork (97k),
  Papa Pal (880), HomeCare.com CNA Jobs (154), CaregiverGO, Wag, Rover, Sittercity.
- **B2B agency clock-in / EVV**: WellSky Personal Care (8457), AxisCare (27473),
  HHAeXchange (2136), MatrixCare, Mobile Caregiver+, Billiyo, Ankota, GT Independence.

Same story for `home care` (pop 22, diff 23): the entire SERP is agency EVV software.
Both terms are off-limits. Ranking for them would deliver caregivers looking for shifts.

## Finding 4: the only real demand nearby is medication + records

These are the only terms in the whole 94-keyword pull with volume above noise:

| keyword | pop | diff | SERP owner |
|---|---|---|---|
| caregiver | 52 | 50 | WALL, wrong intent (see above) |
| pill reminder | 46 | 51 | WALL: Medisafe 100k, All-in-One 27.5k |
| shared calendar | 45 | 70 | WALL |
| medication tracker | 35 | 57 | WALL |
| symptom tracker | 33 | 51 | contested |
| blood pressure log | 27 | 48 | contested |
| **medication list** | **23** | **23** | **SOFT — best target found** |
| family organizer | 23 | 52 | wrong intent |
| appointment reminder | 22 | 58 | contested |
| health journal | 22 | 51 | contested |
| med reminder | 21 | 53 | WALL |
| senior care | 18 | 47 | wrong intent (jobs/agency) |
| daily check in | 16 | 45 | contested |
| **dementia** | **14** | **5** | **OPEN — trophy cluster** |
| medical records | 13 | 51 | contested |
| caregiver app | 9 | 43 | low value |
| medical id | 7 | 23 | soft |

### The two openings

**`medication list` — pop 23, diff 23.** A real-volume term with a soft SERP. Rank 1 is
"Medication List" by JOJO APPS at 450 ratings (not a giant); ranks 3/4/5 have 11, 11 and
7 ratings. Medisafe only shows at rank 6 here. This is the single best entry point in
everything pulled.

**`dementia` — pop 14, diff 5.** Modest volume, essentially zero competent competition.
Entire SERP is 0-7 rating apps; the only large app is ALZ Fundraising (a donation app,
not a competitor). The whole dementia cluster (`dementia care` 5/5, `dementia caregiver`
5/9, `memory care` 5/9, `alzheimers` 5/13) is ownable for free as a low-difficulty
trophy set. Volume is small, but it costs nothing to take and it is real intent.

---

## Recommended scope

Build **a medication + medical-record tracker that handles more than one person**, and
let the aging-parent use case be the marketing story rather than the keyword strategy.

The reframe matters: the searched job is "keep track of Mom's meds and what the doctor
said." The unsearched job is "coordinate our family's caregiving." Same app, different
front door. Lead with the one people type into the search box.

**Positioning line:** meds and health records for the people you look after.

### v1 featureset

Core (this is what earns the keywords):
- **Multi-profile** from the first screen: Mom, Dad, yourself. This is the single
  differentiator against every med tracker on the store, all of which assume one user.
- **Medication list** per person: name, dose, schedule, prescriber, purpose, photo of
  the bottle. Optimized for *showing someone else* (a printable / shareable one-page
  summary to hand an ER nurse) more than for self-reminders.
- **Reminders** per person, with "mark taken on their behalf."
- **Doctor visit log**: date, provider, what was said, follow-ups, next appointment.
- **Vitals**: BP, weight, glucose. Manual entry, chart over time.
- **Emergency card**: allergies, conditions, meds, contacts, insurance. One tap, works
  offline, big text.

Deliberately out of v1:
- Real-time family sync / shared accounts. It's the expensive part (backend, invites,
  permissions, conflict resolution) and it is what every dead app in Finding 2 led with.
  Ship single-device first; add share-by-export. Only build sync if v1 retains.
- Fall detection, GPS, life-alert. Hardware-adjacent, liability-adjacent, no search volume.
- Legal/estate document vault. `power of attorney` pop 5, `estate planning` pop 5.
- Any care-team task assignment / chore board.

### Metadata direction (US)

- Title: lead with `Medication List` or `Med List`, plus a multi-person qualifier.
- Subtitle: carry `tracker`, `reminder`, `records`, and the for-someone-else framing.
- Keyword field: `dementia` cluster + `medical id` + `caregiver journal` / `care log`
  (both pop 5 but diff 11, free trophies) + `medication` combos not already in title.
- Keep `caregiver`, `senior care`, `home care` OUT. Wrong intent, wall difficulty.

### Compliance notes

- Health & Fitness or Medical category: never claim to treat, cure or diagnose
  (App Review 1.4.1). Complementary / organizational framing, plus a disclaimer.
- Medical category triggers the **Regulated Medical Device declaration** at submission
  (UI-only, not in the ASC API). Set it before attempting to submit.
- Storing another person's health data: be explicit in the privacy copy that data is
  local-only in v1. That is also a selling point in this SERP ("My Meds" at rank 3 leads
  with "No Data Collected - 100% Local").

---

## Appendix A: brainstorm round 1 (2026-07-28), priced

Context (2026-07-28 iMessage, Dad → Chris): Dad pitched an "Aging Parents Dashboard"
sourced from a ChatGPT brainstorm, tracking medications, appointments, doctor notes,
grocery needs, reminders, emergency contacts, shared family communication. Chris added
three: paid caregiver schedule, parent/loved one passwords, links to helpful resources.

Every feature run through Astro:

| feature | keyword | pop | diff | verdict |
|---|---|---|---|---|
| medications | medication list | 23 | 23 | **KEEP — the only one with demand** |
| appointments | appointment reminder | 22 | 58 | contested, secondary |
| doctor notes | doctor visit notes | 5 | 40 | floor, keep as sub-feature only |
| emergency contacts | emergency contacts | 5 | 9 | floor, keep as sub-feature only |
| grocery needs | grocery list | 52 | 67 | WALL (AnyList, Apple Reminders); unrelated to eldercare |
| shared family comms | family updates | 5 | 49 | floor |
| " | family notes | 5 | 46 | floor |
| paid caregiver schedule | caregiver schedule | 5 | 21 | floor |
| " | caregiver shift | 5 | 15 | floor |
| " | home aide | 5 | 15 | floor |
| parent passwords | password manager | 63 | **75** | WALL (1Password/Bitwarden/Dashlane) |
| " | shared passwords | 5 | 23 | floor |
| " | family passwords | 5 | 49 | floor |
| " | digital legacy | 5 | 5 | floor |
| helpful resources | senior resources | 5 | 17 | floor |

**Passwords**: the demand is entirely in generic password management (pop 63), which is
unwinnable at diff 75, and every caregiving-specific variant is at the floor. Separately,
storing a parent's credentials is a serious security and liability surface that does not
belong bolted onto a v1 health tracker. Skip.

**Paid caregiver schedule**: floor demand, and the buyers who genuinely need shift
scheduling are agencies, already served by AxisCare (27k ratings) and HHAeXchange (2.1k).
Skip.

**Resource links**: floor demand, content maintenance burden, no acquisition value. Skip.

### The one real demand signal in the aging orbit, and why it's still a no

`medicare` pop 40 / diff 53 and `medicaid` pop 32 / diff 67 are the only high-volume
terms anywhere near this space. The SERP explains it and closes it: UnitedHealthcare
(814k ratings), MyChart (690k), GoodRx (699k), Sydney Health (549k), Aetna (373k),
MyHumana (35k), plus the official CMS app. That volume is people opening their own
insurer's app. Not addressable.

### The distinction worth passing back to Dad

"Huge market" is true and not the issue. Tens of millions of adults do manage an aging
parent. But market size and App Store search demand are different things, and only the
second one is an acquisition channel. These families are not typing "aging parents" into
the App Store; they cope with a notes app, a shared calendar, and a shoebox of paperwork.
That gap between real pain and zero search volume is exactly what produced the graveyard
in Finding 2: 30 teams saw the same demographic argument, built the same dashboard, and
none of them got found.

The medication angle works because it's the one part of the job people actively search
for a tool to do.

---

## Appendix B: brainstorm round 2 (2026-08-02), priced

Context: Dad sent a second, much longer pass (18 numbered categories plus a
"features I would add" list), generated against the actual spreadsheet he kept for
Mom. The spreadsheet is the valuable part of that message: it is a real caregiver's
real data model, and it confirms which entities matter. The *framing* he wraps it in
("the operating system for family caregiving", "unify every domain into one
collaborative workspace") is precisely the pitch of all 30 apps in Finding 2. Take
the entities, refuse the framing.

### Already shipped (round 2 asked for these and they exist)

| Dad's category | where it lives |
|---|---|
| 1 Dashboard | `TodayView` |
| 4 Medications | `Medication` + `ScheduleEngine` |
| 5 Appointments | `Visit` (provider, reason, notes, follow-up, next appointment) |
| 6 Care journal (vitals half) | `VitalReading` |
| 7 Contacts | `EmergencyContact` |
| 13 Emergency | `EmergencyCardView`: allergies, conditions, meds, contacts, offline |
| 15 Family collaboration | groups, roles, invites, sync, `recordedBy` attribution |
| 18 Reports | `MedListExporter` one-pager |

### Build (on-strategy, cheap, in rough priority order)

1. **Refill tracking.** Nothing in the model tracks quantity on hand. Add
   `quantityRemaining`, `daysSupply`/`lastFilledAt`, and a "running low" local
   notification. Highest-value gap: it is the top complaint against the incumbent
   `medication list` SERP apps, and it is squarely inside the keyword we are buying.
2. **`Provider` as a first-class model.** Today `Medication.prescriber`,
   `Medication.pharmacy` and `Visit.provider`/`.specialty` are loose strings retyped
   every time. Dad's spreadsheet has one row per provider with phone, address, portal
   link, notes, which is exactly right. New synced entity, referenced by `Medication`
   and `Visit`, surfaced on the emergency card and the ER one-pager. Supports
   `medical records` (pop 13) at no metadata cost.
3. **Timeline (his #14).** Near-free: every entity already carries `createdAt`,
   `updatedAt` and `recordedBy` and already syncs. A merged chronological read across
   doses, visits, vitals, med changes and check-ins is a query plus a view, no schema.
   Real differentiator, and it feeds `health journal` (pop 22).
4. **Incident / symptom log.** `symptom tracker` is pop 33, the second-highest
   real-volume term in the entire 94-keyword pull. One typed note entity covers falls,
   ER visits, mood, appetite, sleep, pain, the rest of his #6. **Logging an incident is
   fine; nothing may detect one (I6).**
5. **Search.** Only worth building once 2-4 exist. Local, offline, no server.
6. **Paperwork photos on a `Visit`.** Not a document vault: the same
   `Medication.labelPhoto` pattern extended to discharge paperwork and lab results.
   Decide blob-sync cost before it goes cross-device.
7. **Weekly family digest.** The deterministic version of his #17/#18: "3 doses missed,
   BP up, visit Thursday", pushed to the group. Rides the migration-0007 `group_notices`
   + edge-function path that already exists. Retention, not acquisition.

### Refuse

| Ask | Why not |
|---|---|
| 9 Password vault ("Digital Keys") | `password manager` diff **75**; `family passwords` pop 5. Holding a parent's live credentials is a breach surface a one-dev Supabase project should not carry. Already out of scope in `architecture.md` §14. |
| 4-bonus Interaction checker | Clinical decision support. Fastest available route to a 1.4.1 rejection and to the regulated-medical-device question that is *already* gating submission. |
| 10 Insurance, 11 Financial | Pop 5 across the board, and bank/policy/claim data multiplies breach exposure for zero discoverability. |
| 8 Documents (as a vault), incl. POA/trust/passport | Priced in Appendix A: `power of attorney` 5/45, `estate planning` 5/17. Item 6 above is the useful 10% of it. |
| ~~2 Care tasks with owners/due dates~~, 12 Living situation | **Item 2 was reversed on 2026-08-04 and built (`CareTask`, migration 0012).** The keyword finding is unchanged and still binding: `caregiver schedule` is pop 5, this is the signature feature of the graveyard, and **nothing about it may enter any ASC metadata field**. It shipped as a retention feature, not an acquisition one, on the argument that a shared list is only possible because the app already has family groups, which is the one thing the graveyard apps did not have. Living situation stays refused. |
| 17 AI assistant | Breaks I1: offline *is* the product, and an assistant is the one screen that cannot work in the ER with no bars. Also ships PHI to a third party, which invalidates the privacy policy and ASC data disclosures just written, and costs per-query against a fixed subscription. Items 3 + 5 + the existing exporter deliver most of the asked-for answers deterministically. |
| Fall detection, location sharing | I6, already out (`architecture.md` §14). |
| Apple Health integration | Answered in `architecture.md` § "Vitals: where the numbers come from": the reading and the phone are in different hands. |
| Voice-to-text notes | Not a feature; the system keyboard already dictates. |

### The structural note

18 top-level categories is not an information architecture, it is the spreadsheet with
tabs. The med list has to stay the first thing on screen and the thing the App Store
listing is about. Everything in "Build" above attaches to an existing entity (a
medication, a visit, a person) rather than adding a tab.
