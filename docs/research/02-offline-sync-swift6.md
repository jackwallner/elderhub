# Offline-first sync, Swift 6 concurrency, and local data protection for Med List (Aging)

Research brief for moving Aging's SwiftData store from local-only to a synced mirror
of the Supabase schema designed in
[`01-groups-rbac-rls.md`](./01-groups-rbac-rls.md), without breaking the app's actual
job: a full, readable medication list and allergy card with **zero network**, at the
moment someone is standing in an ER with a dead signal. Written against
`Shared/Models/CareModels.swift` and `Shared/Services/CareModelStore.swift`, and the
house style already established in `~/bond/Bond/Services/`.

All `supabase-swift` source citations below are read directly from the `main` branch
of `supabase/supabase-swift` on 2026-08-01, which at that date matched the latest
tagged release, `v2.54.1` (published 2026-07-29,
<https://github.com/supabase/supabase-swift/releases/tag/v2.54.1>). Pin to `2.54.1`
or later and re-verify these behaviors on any major-version bump — see the
`emitLocalSessionAsInitialSession` note in §1, which the SDK's own doc comment says
will change default value in "the next major release."

---

## Recommendations up front

- **Gate the UI on the SDK's synchronous, non-throwing `currentSession` property, not
  on the async `session` property.** `currentSession` reads straight from the local
  Keychain-backed store and never touches the network or throws
  (`AuthClient.swift:196-198`, quoted in §1). Use it (or `currentSession?.user.id`) as
  the single source of truth for "is there a locally-known identity," and never block
  first paint on `try await client.auth.session`. See §1.
- **Set `emitLocalSessionAsInitialSession: true` in `AuthClient.Configuration`.** This
  is a real, already-shipped SDK option that emits the cached local session
  immediately on launch (even if expired) and attempts a background refresh whose
  failure is silently swallowed (`try?`) and never turns into a `.signedOut` event
  (`AuthClient.swift:1522-1536`, quoted in §1). It defaults to `false` today for
  backward compatibility but is exactly the offline-launch behavior this app needs.
  See §1.
- **Do not trust "the SDK never signs you out on a failed refresh" as a permanent
  guarantee** — two closed issues (#596, #630, cited in §1) show this has regressed
  before. Add app-level defense in depth: never call `signOut()` or delete cached
  care data in response to a caught error unless that error is a definitive server
  rejection of the refresh token (`AuthError.api` with an `invalid_grant`/"Refresh
  Token Not Found" body), never in response to a `URLError`/transport failure. See
  §1.
- **The default `KeychainLocalStorage` already writes with
  `kSecAttrAccessibleAfterFirstUnlock`** (confirmed from `Internal/Keychain.swift`,
  quoted in §1) — the right class for background sync/notification handling, and no
  custom `AuthLocalStorage` is required just to fix accessibility. A custom storage
  implementation only becomes necessary later if a widget/watch target needs an
  App Group access group (out of scope — v1 has neither, per `CLAUDE.md`).
- **Reuse the existing client-generated `UUID` (`Person.id`, `Medication.id`, …) as
  the server primary key**, exactly as `01-groups-rbac-rls.md`'s SQL sketches already
  assume. This is not just convenient — it is what makes every push, retry, and the
  one-time local-data-adoption migration (§5) idempotent for free via Postgres
  `ON CONFLICT (id) DO UPDATE`. See §2, §5.
- **Sync metadata**: add `updatedAt` (server-authoritative, never client-set),
  `deletedAt` (tombstone, no hard deletes), a local-only `dirty` flag, and a local
  device-wide cursor (`Date`, stored outside SwiftData) per entity. See §2.
- **Cursor must be server time.** Compare against `updated_at` returned by Postgres,
  never the device clock, and break ties with a compound `(updated_at, id)` cursor so
  same-timestamp rows at a page boundary are neither skipped nor duplicated. See §2.
- **Outbox pattern for push, with per-row coalescing.** Queue local writes in an
  outbox table; coalesce multiple queued edits to the same `Medication`/`Person` row
  into one upsert (only final state matters), but never coalesce `DoseLog` inserts
  (each is a discrete event). Retry with backoff; a 403 from a role that changed
  mid-flight moves the entry to "needs review," never an infinite retry loop. See §2.
- **Conflict resolution is asymmetric by entity, matching the brief's framing
  exactly**: `DoseLog` is de-duplication (unique `(medication_id, scheduled_at)`,
  never overwritten), `Medication`/`Person` (allergies, conditions, dosage) use
  optimistic-concurrency + a surfaced manual-resolve UI (last-writer-wins is not
  acceptable for a drug dosage), `Visit`/`VitalReading`/`EmergencyContact` use
  optimistic-concurrency + LWW-by-last-editor (lower stakes, ship the simpler path,
  promote to manual-resolve later if wrong). See §2.
- **Sync trigger: foreground-first, push-assisted, no persistent background socket.**
  Sync on every foreground transition (primary, reliable), Supabase Realtime only
  while actively foregrounded (nice-to-have live updates), silent APNs push to nudge
  a background sync opportunistically (reuse the same APNs pipeline brief 01 already
  requires for check-in escalation — don't build a second delivery path),
  `BGAppRefreshTask` as a best-effort bonus, never the guarantee. See §2, §6.
- **Swift 6: a `@ModelActor` background sync engine, a `@MainActor @Observable`
  UI-facing service** (same shape as Bond's `SupabaseService`/`PairingService`),
  cross-actor data only as `PersistentIdentifier` or plain `Sendable` DTO structs,
  never a `ModelContext` or `@Model` instance. See §3.
- **File protection: `NSFileProtectionCompleteUntilFirstUserAuthentication` on the
  SwiftData store**, set explicitly (don't rely on the platform default), plus the
  SDK's already-`AfterFirstUnlock` Keychain. Full third-party encryption
  (SQLCipher-class) is disproportionate for this app and not natively supported by
  SwiftData's SQLite store — do not build it. See §4.
- **Migration of existing local-only installs**: local data stays local-only and
  fully usable until the user opts into an account; adoption is a sequence of
  idempotent upserts keyed on the existing client UUIDs, resumable after a kill at
  any point, and never mutates or deletes the local rows it's adopting. See §5.
- **Background execution is a freshness nice-to-have, not a correctness mechanism.**
  The offline-launch guarantee is satisfied by definition (SwiftData already holds
  the last-synced snapshot); `BGAppRefreshTask` cannot be relied on for anything
  time-sensitive (see the Apple Developer Forums findings in §6). The one thing that
  *must* be reliable — the daily check-in reminder on the parent's own device — is a
  locally scheduled `UNCalendarNotificationTrigger`, not a background task, and the
  escalation-to-caregivers side is entirely server-driven (already specified in brief
  01), independent of the parent's device background execution. See §6.
- **Test with in-memory `ModelContainer`s (already the pattern in
  `CareModelStore.makeInMemoryContainer()`) fronting a protocol-abstracted
  `SyncRemote`.** A fake in-memory remote is the only practical way to deterministically
  test cursor pagination, version conflicts, and RLS-role-changed rejections. See §7.

---

## 1. Session persistence and offline auth

This is correctly flagged as the highest-risk item: get it wrong and the app shows a
login wall to someone who needs Mom's allergy list *right now*.

### Where the session lives today (default `supabase-swift` behavior)

`AuthClient.Configuration.defaultLocalStorage` on Apple platforms is a
`KeychainLocalStorage`
(<https://github.com/supabase/supabase-swift/blob/main/Sources/Auth/Storage/AuthLocalStorage.swift>):

```swift
#if !os(Linux) && !os(Windows) && !os(Android)
  public static let defaultLocalStorage: any AuthLocalStorage = KeychainLocalStorage()
#endif
```

`KeychainLocalStorage` namespaces items under the Keychain service
`"supabase.gotrue.swift"` by default
(<https://github.com/supabase/supabase-swift/blob/main/Sources/Auth/Storage/KeychainLocalStorage.swift>).
The actual Keychain write, in `Internal/Keychain.swift`
(<https://github.com/supabase/supabase-swift/blob/main/Sources/Auth/Internal/Keychain.swift>),
sets the accessibility class explicitly:

```swift
func setQuery(forKey key: String, data: Data) -> [String: Any] {
  var query = baseQuery(withKey: key, data: data)
  query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
  return query
}
```

**This answers half of the "which Keychain accessibility class" question for free:
the SDK already defaults to `kSecAttrAccessibleAfterFirstUnlock`**, not
`WhenUnlocked`. That's the correct choice for this app (see the accessibility-class
discussion below) and means no custom `AuthLocalStorage` is required purely to fix
accessibility — a custom implementation only becomes worth writing later for a
different reason (e.g. a Keychain access group shared with a future widget/watch
target; out of scope for v1 per `CLAUDE.md`, which has no App Group yet).

### What happens on offline launch with an expired token

Read directly from `SessionManager.swift`
(<https://github.com/supabase/supabase-swift/blob/main/Sources/Auth/Internal/SessionManager.swift>):

```swift
func session() async throws -> Session {
  guard let currentSession = sessionStorage.get() else {
    throw AuthError.sessionMissing
  }
  if !currentSession.isExpired { return currentSession }
  return try await refreshSession(currentSession.refreshToken)   // network call
}

func remove() { sessionStorage.delete() }
```

`refreshSession` makes an HTTP call to `POST /token?grant_type=refresh_token`. If that
call throws (no network, timeout, DNS failure — any transport error), the throw
propagates straight out of `session()`. **Critically, nothing in this code path calls
`sessionManager.remove()`.** Searching `AuthClient.swift` for every call site of
`sessionManager.remove()` and every emission of `.signedOut` turns up exactly one
call site for each, both inside `signOut()`:

```swift
public func signOut(scope: SignOutScope = .global) async throws {
  guard let accessToken = currentSession?.accessToken else { return }
  if scope != .others {
    await sessionManager.remove()
    eventEmitter.emit(.signedOut, session: nil)
  }
  // ... best-effort server-side logout, 401/403/404 are swallowed ...
}
```

**So, as of `v2.54.1`, a failed token refresh due to lack of network does not clear
the local session.** The error simply propagates to whatever caller awaited
`client.auth.session`. This is good news, but it means the app's own code is the only
thing standing between "offline, expired token" and "user incorrectly signed out" —
if app code naively does `catch { await signOut() }` on any error from
`client.auth.session`, it recreates the exact bug the SDK itself avoids.

### The mechanism that actually solves offline launch: `currentSession` + `emitLocalSessionAsInitialSession`

Two things in the SDK do the job directly, and neither requires custom storage:

1. **`currentSession` is synchronous, `nonisolated`, and never throws or touches the
   network** (`AuthClient.swift:196-198`):

   ```swift
   /// The session returned by this property may be expired. Use `session` for a
   /// session that is guaranteed to be valid.
   nonisolated public var currentSession: Session? {
     sessionStorage.get()
   }
   ```

   This *is* the "locally-cached last known good identity" the brief asks for — it
   already exists, is already backed by Keychain, and requires no additional caching
   layer. **Gate app launch and the emergency card on `currentSession != nil`, never
   on `await session`.**

2. **`emitLocalSessionAsInitialSession`**, a documented `AuthClient.Configuration`
   option
   (<https://github.com/supabase/supabase-swift/blob/main/Sources/Auth/AuthClientConfiguration.swift>):

   ```swift
   /// Default is `false` for backward compatibility. This will change to `true` in
   /// the next major release.
   public let emitLocalSessionAsInitialSession: Bool
   ```

   With it `true`, `emitInitialSession` (`AuthClient.swift:1522-1536`) does exactly
   the right thing:

   ```swift
   private func emitInitialSession(forToken token: ObservationToken) async {
     if configuration.emitLocalSessionAsInitialSession {
       guard let currentSession else {
         eventEmitter.emit(.initialSession, session: nil, token: token)
         return
       }
       eventEmitter.emit(.initialSession, session: currentSession, token: token)
       Task {
         if currentSession.isExpired {
           _ = try? await sessionManager.refreshSession(currentSession.refreshToken)
           // No need to emit `tokenRefreshed` nor `signOut` — refreshSession does it.
         }
       }
     } else {
       let session = try? await session   // <-- blocks on network + refresh first
       eventEmitter.emit(.initialSession, session: session, token: token)
       ...
     }
   }
   ```

   The default path (`false`) is the trap: it `try? await session` *before* emitting
   anything, which is the async/throwing path from §1's `SessionManager.session()` —
   on a cold, offline, expired-token launch this can stall on a network timeout
   before the app even knows it has a cached identity. Flipping the flag emits the
   cached session **immediately**, unconditionally, then fires the refresh as an
   unstructured `Task` whose failure is caught with `try?` and produces no event at
   all — not `.signedOut`, not an error the app sees. Set
   `emitLocalSessionAsInitialSession: true` in the client config and drive routing
   off `.initialSession`/`currentSession`, not off waiting for `.tokenRefreshed`.

### Distinguishing "offline" from "genuinely signed out"

The SDK gives you the primitives (§ above) but not the policy — that has to live in
app code, because the SDK's own error type doesn't pre-classify for you. Recommended
rule, to be implemented once in the sync/auth service and never duplicated:

- **Transport/connectivity errors** (`URLError` — `.notConnectedToInternet`,
  `.timedOut`, `.cannotConnectToHost`, `.networkConnectionLost`, etc., or any error
  that isn't a well-formed HTTP response) → **offline**. Do nothing to the cached
  session or cached care data. Leave the outbox/pending state as-is and retry later.
- **`AuthError.api` with a 4xx response whose body is an explicit revocation**
  (`invalid_grant`, "Refresh Token Not Found", "Invalid Refresh Token") → **genuinely
  signed out** (token was rotated/revoked server-side, e.g. signed in elsewhere with
  session invalidation, or an admin/owner action revoked access). Only in this case
  is it correct to route to a re-authentication screen — and even then, do **not**
  delete the local SwiftData care data; the app should still show the cached
  emergency card read-only with a "sign in again to sync" banner, not a blank slate.
- Never wire "refresh failed" generically to `signOut()`. `signOut()` should be
  reachable only from an explicit user action in Settings.

### Known regressions to treat as a live risk, not settled history

Two closed `supabase-swift` issues show this exact failure mode (offline refresh ⇒
session wiped) has actually shipped before, which is why the app-level defense above
matters even though the current source reads clean:

- **#596, "Token refresh offline deletes session"**
  (<https://github.com/supabase/supabase-swift/issues/596>), reported against
  `2.20.5`: an `NSError`-wrapped `URLError` failed to cast to the SDK's internal
  `RetryableError` protocol, so an offline refresh failure was treated as
  unrecoverable rather than retryable. Closed, but the fetched issue page shows no
  linked PR or maintainer confirmation of the exact fix commit — **treat the
  underlying classification logic (which errors count as "retryable" internally) as
  unverified beyond "the currently-read main-branch code path no longer calls
  `remove()` on this path," not as "provably permanently fixed."**
- **#630, "Auto-refreshing of tokens can fail and never restart again"**
  (<https://github.com/supabase/supabase-swift/issues/630>): the periodic
  `autoRefreshTokenTick()` loop (confirmed present in the `main` source quoted above)
  silently swallows a failed refresh with `try?` inside the tick — it doesn't clear
  the session, but it also means a background auto-refresh failure produces no
  visible signal at all. A referenced PR (#822) appears closed against this, but the
  fetched issue content didn't confirm the specific resolution. Because of this,
  **don't rely on `startAutoRefresh()`'s background loop as the thing that keeps a
  session valid** — explicitly call `try? await client.auth.session` (or
  `refreshSession()`) on every foreground transition as a deliberate, observable
  refresh attempt, in addition to whatever the SDK's internal timer does.

**Unverified, stated plainly per the task instructions**: I could not find a
maintainer-authored design doc or changelog entry stating "a failed refresh will
never clear your session" as an intentional, permanent contract — this brief's
conclusion is derived from reading the current `main`/`v2.54.1` source directly
(quoted above), not from an explicit guarantee in the docs. Re-read
`Sources/Auth/Internal/SessionManager.swift` and `AuthClient.swift` against whatever
version is actually pinned in `Package.resolved` before shipping, and add the app-level
offline/revoked classification (previous subsection) regardless — it's cheap
insurance against exactly the two regressions above recurring.

---

## 2. Sync architecture

### Client UUID as server PK

`Person.id`, `Medication.id`, `DoseLog.id`, etc. are already client-generated `UUID`s
(`self.id = UUID()` in every model's initializer). Reuse them verbatim as the
Postgres primary key on `care_recipients`, `medications`, `dose_logs`, `visits`,
`vital_readings`, `emergency_contacts` — exactly what `01-groups-rbac-rls.md`'s SQL
sketches already assume (`id uuid primary key default gen_random_uuid()`, overridden
by the client-supplied value on insert).

This buys **idempotency for free**: every push becomes `insert ... on conflict (id) do
update set ...`. A retried push after a dropped connection, a re-run of the local-data
adoption migration (§5) after a kill, or a duplicate outbox entry from a race all
collapse to the same row instead of creating duplicates. No separate local-id ↔
server-id mapping table is needed anywhere in this design — the two are the same id,
always.

### Sync metadata to add per entity

Add to every synced `@Model` (not to `DoseLog`'s conflict model — see below — but to
its metadata shape too):

| Field | Type | Set by | Synced to server? |
|---|---|---|---|
| `id` | `UUID` | client, at creation | yes — becomes the PK |
| `groupID` | `UUID?` | set once adopted (§5) | yes — denormalized `group_id` per brief 01 |
| `remoteUpdatedAt` | `Date?` | **server only** — mirrors Postgres `updated_at` | pulled, never pushed |
| `version` | `Int` | **server only** — incremented per update, for optimistic concurrency | pulled, never pushed by client directly (see push below) |
| `deletedAt` | `Date?` | either side | yes — tombstone, no hard deletes |
| `isDirty` | `Bool` | client, local-only | **not synced** — local bookkeeping |
| `lastSyncedAt` | `Date?` | client, local-only, set on successful push/pull | **not synced** |

`remoteUpdatedAt`/`version` are populated by a Postgres trigger
(`updated_at = now(), version = version + 1` on every `update`), the same house style
as the audit-trail triggers `01-groups-rbac-rls.md` §5 already specifies for
`medications`/`dose_logs`. Client never sets either directly; it sends the `version`
it *last saw* as a `where version = $expected` guard on push (see below), and adopts
whatever the server echoes back as the new local value.

The **sync cursor is per-device, not per-entity-row**, and lives outside SwiftData
(UserDefaults or a tiny local-only SwiftData row) as a single `Date` (or one per table
if tables are pulled independently): `lastPulledAt: [String: Date]` keyed by table
name.

### Pull: cursor-based, server time, paginated, tie-broken

```sql
select * from medications
where group_id = any($1)
  and (updated_at, id) > ($2, $3)   -- compound cursor: (last_updated_at, last_id)
order by updated_at asc, id asc
limit 500;
```

- **The cursor must be the value Postgres returns in `updated_at`, never
  `Date()` read on the device.** Device clocks drift (seconds to, in the worst case
  of a misconfigured device, minutes); if the client used its own clock as the "I've
  seen everything before time T" watermark, a row written by the server at server
  time `T_server` but pulled by a device whose clock reads earlier than `T_server`
  could be silently skipped on the next pull, and worse, a device whose clock reads
  *later* than actual server time would skip a valid update outright. Always persist
  the `updated_at` **from the last row actually received**, never `Date.now()`.
- **Pagination**: loop `limit`-sized pages until a page returns fewer than `limit`
  rows, advancing the compound cursor by the last row of each page.
- **Tie-breaking**: two rows written in the same trigger execution (or the same
  transaction) can share an identical `updated_at` to microsecond precision. A plain
  `updated_at > cursor` cursor would non-deterministically include or exclude
  same-timestamp rows depending on page boundaries. The `(updated_at, id)` compound
  cursor above with `order by updated_at, id` and `where (updated_at, id) > (cursor)`
  makes the pagination strictly monotonic and gap-free regardless of ties.
- **Soft deletes propagate as ordinary pulled rows**: a row with `deleted_at` set is
  pulled exactly like any updated row (it has a fresh `updated_at` from the delete
  itself); the client's merge step checks `deletedAt != nil` and removes/hides the
  local `@Model` instance (soft-delete locally too, or hard-delete locally once
  confirmed — hard-deleting locally is safe once the tombstone itself has been
  durably pulled, since the server keeps the historical row).

### Push: outbox pattern

Every local write goes through an outbox table (sketch in §"Swift type sketches"
below) rather than direct network calls from view code — this is what makes offline
writes possible at all, and what makes retry/backoff/ordering a single well-tested
code path instead of scattered try/catch in every view.

- **Coalescing**: for `Medication`, `Person`/`care_recipients`, `Visit`,
  `VitalReading`, `EmergencyContact` (all *mutable records*), multiple queued edits to
  the same row before the next successful sync collapse into a single outbox entry —
  only the final local state matters to the server, and coalescing means a caregiver
  editing a dosage three times offline produces one push, not three (which would also
  triple the optimistic-concurrency conflict surface for no benefit). **For `DoseLog`
  (an append-only event log), never coalesce** — each logged dose is a discrete
  outbox entry that must reach the server as its own row.
- **Ordering**: strict order only matters within a single row's queued edits (already
  guaranteed by coalescing collapsing them to one entry) and for insert-before-child
  dependencies (a `Medication` insert must reach the server, or at least be
  in-flight/known-accepted, before a `DoseLog` referencing it — enforce this simply
  by processing the outbox in creation order and letting a `DoseLog` push retry if its
  parent `Medication` hasn't confirmed yet, rather than building a dependency graph).
  Independent rows (an edit to Mom's Lisinopril and Dad's blood pressure reading) have
  no ordering requirement between them and can push concurrently.
- **Retry with backoff**: exponential backoff with jitter, capped (e.g. 30s → 5min
  ceiling), and a max-attempts threshold after which the entry is marked
  `failedPermanently` and surfaced in a small "N changes couldn't be saved" UI
  affordance rather than retried forever silently. This mirrors the same "don't
  infinite-loop on a permanent failure" principle as the RLS-rejection case below.
- **RLS rejection because the caller's role changed while offline** (the brief's named
  case: a caregiver is demoted, then comes back online with queued `Medication`
  edits). The push gets a PostgREST `403` (RLS `with check` failure). Recommended
  handling:
  1. **Do not retry this push automatically** — a 403 from a role check will not
     resolve itself on the next attempt; retrying wastes battery/requests and, worse,
     could mask the real problem from the user indefinitely.
  2. Move the outbox entry to a `rejected` state distinct from `pendingRetry`.
  3. Trigger an immediate re-pull of `group_members`/the caller's own role for that
     group, so the local role cache (used to show/hide UI affordances) reflects
     reality on the very next screen render — the user should stop seeing "Edit"
     buttons for a group they can no longer write to.
  4. Surface the rejected entries explicitly: "This change to Mom's Lisinopril
     couldn't be saved — your access changed." with a way to discard the entry
     (accept the loss) — never silently drop it and never silently keep retrying it
     forever in the background.

### Conflict resolution per entity kind

The brief's framing is exactly right and is the correct basis for the design:

- **`DoseLog` — de-duplication, not conflict.** Two devices independently logging
  "Mom took her 8am Lisinopril" produce two distinct rows with different `id`s but the
  same logical event. Enforce a Postgres partial unique index on
  `(medication_id, scheduled_at)` (scoped to non-deleted rows). A push that violates
  it comes back as a `409`/unique-violation; the client's response is **never** to
  retry as a new row — pull the existing server row for that
  `(medication_id, scheduled_at)`, show it in place of (or merged with, e.g. keeping
  the local `note` field as an addendum) the local duplicate, and drop the local
  duplicate from the outbox. LWW does not apply here — there is nothing to "win," the
  two records represent the same real-world event and only one should exist.
- **`Medication`, `Person`/`care_recipients` — real conflicts, optimistic concurrency +
  manual resolve.** These carry the fields the brief specifically calls out as unsafe
  to silently overwrite: dosage/schedule, allergies, conditions. Push includes the
  `version` the client last saw:
  `update medications set ... , version = version + 1 where id = $1 and version = $2`.
  A zero-row result means someone else's edit landed first. On that result:
  1. Pull the current server row.
  2. If the *fields the local queued edit actually touched* are unchanged from what
     the client last saw (e.g. someone else changed `pharmacy` while the client's
     queued edit only touched `strength`), auto-merge — apply the local edit on top of
     the fresh row and retry the optimistic push once.
  3. If the touched fields actually differ (two edits to `strength`/`scheduleMinutes`),
     **do not auto-resolve.** Surface both versions ("Sarah changed Mom's Lisinopril to
     20mg while you were offline. You changed it to 15mg.") and require an explicit
     choice or manual merge before either write is finalized. This is the "manual
     resolution" tier — appropriate here specifically because a silently-dropped
     dosage change is a patient-safety bug, not a UX inconvenience.
- **`Visit`, `VitalReading`, `EmergencyContact` — same optimistic-concurrency
  mechanism, simpler resolution.** Ship record-level LWW-by-last-successful-write for
  v1 (a losing optimistic push just re-pulls and retries with the local edit reapplied
  wholesale, no field diffing) — genuinely simultaneous edits to a single vitals
  reading or visit note by two caregivers are rare and lower-stakes than a dosage
  change. If `EmergencyContact` (a phone number a family might dial in a crisis) turns
  out to need the same manual-resolve treatment as `Medication`, that's a small,
  additive promotion later, not a redesign.
- **Do not build field-level automatic merging (CRDT-style) for v1.** It's the
  technically "best" answer for a mutable-record conflict, but it's meaningfully more
  code and more subtle bugs than this app's actual conflict rate justifies — family
  groups are small, simultaneous edits are rare, and the manual-resolve path above
  already prevents silent data loss, which is the actual risk being managed. (General
  background on this tradeoff, consistent with the above:
  <https://docs.powersync.com/handling-writes/custom-conflict-resolution>,
  <https://www.sachith.co.uk/offline-sync-conflict-resolution-patterns-architecture-trade%E2%80%91offs-practical-guide-feb-19-2026/>.)

### Realtime, silent push, polling, or a combination

Recommendation: a layered combination, none of them the sole mechanism.

1. **Foreground sync (primary, always-correct path).** On every transition to
   foreground (`scenePhase == .active`), run a pull for every group the user belongs
   to, then flush the outbox. For a medication tracker, the app is opened multiple
   times a day around dose times — this alone keeps the local mirror close to fresh
   for the overwhelmingly common case, and it's the one mechanism with zero OS
   discretion involved.
2. **Supabase Realtime, foreground-only.** Subscribe to Postgres changes on the
   user's groups' tables while the app is active, for live "Sarah just logged Dad's
   dose" updates without waiting for the next foreground transition. **Do not keep the
   Realtime WebSocket open in the background** — iOS suspends/kills backgrounded
   sockets anyway, and holding one open is a pure battery cost with no delivery
   guarantee once suspended; tear it down on background, reopen on foreground.
3. **Silent push (`content-available: 1`) to nudge a background sync.** Reuse the
   exact APNs pipeline `01-groups-rbac-rls.md` already requires for check-in
   escalation (pg_cron/edge-function-driven) rather than standing up a second push
   path — have the same write-triggers that populate `audit_log` also (or via a
   lightweight `pg_notify`/edge function call) fire a generic "group `$id` changed, go
   sync" silent push to other group members' devices. Treat delivery as best-effort:
   Apple throttles and can defer or fully suppress `content-available` pushes once a
   device's daily energy/data budget is exceeded, and the execution window on receipt
   is ~30 seconds — enough for one bounded pull-and-flush, not for anything longer.
4. **`BGAppRefreshTask` as a bonus, not a guarantee** — see §6 for why it can't be
   relied on.
5. **Do not poll on a timer.** Polling is the one option this combination doesn't need
   — foreground sync already covers the "user is looking at the app" case, and a
   timer-driven poll while backgrounded has the same battery cost as an idle Realtime
   socket for strictly worse freshness than push.

---

## 3. Swift 6 strict concurrency

### `@ModelActor` for the background sync engine

`@ModelActor` is a macro that turns an `actor` declaration into a SwiftData-aware
actor: it synthesizes a private `ModelContext` (created from an injected, `Sendable`
`ModelContainer`), a `modelExecutor`, and a `modelContext` accessor, giving the actor
its own serial, isolated context distinct from whatever context `@MainActor` SwiftUI
code uses. Practical shape:

```swift
@ModelActor
actor SyncEngine {
  // modelContext, modelContainer synthesized by the macro.
  func pullAndMerge(remote: some SyncRemote) async throws { ... }
  func flushOutbox(remote: some SyncRemote) async throws { ... }
}
```

Construct it with `SyncEngine(modelContainer: CareModelStore.sharedModelContainer)` —
the container itself is the one SwiftData type that *is* `Sendable` and is meant to be
handed across actor/task boundaries; each actor that needs data access creates its own
private `ModelContext` from the shared container rather than sharing one context.

### Why `ModelContext` and `@Model` instances are not `Sendable`

Under Swift 6 strict concurrency the compiler enforces (rather than merely
documents) that a `ModelContext` and any `@Model`-annotated class instance vended by
it are **not** `Sendable` and cannot cross actor/task boundaries — attempting to pass
a `Medication` fetched on the `@MainActor` into a function isolated to `SyncEngine`
is a compile error, not a runtime data race. This is a real, useful tightening versus
Core Data, where the equivalent (`NSManagedObject`/`NSManagedObjectContext`) could be
passed across contexts unsafely and would only fail at runtime, if at all
(<https://www.polpiella.dev/core-data-swift-data-concurrency>,
<https://killlilwinters.medium.com/taking-swiftdata-further-modelactor-swift-concurrency-and-avoiding-mainactor-pitfalls-3692f61f2fa1>,
Apple Developer Forums thread on exactly this class of error:
<https://developer.apple.com/forums/thread/775661>).

The non-`Sendable`-ness reflects something stronger than "shared mutable state, be
careful": a `@Model` instance is only valid *within the `ModelContext` that vended
it* — even a read-only touch from another actor is unsupported, not just racy. So the
fix is never "add a lock" — it's "don't move the object at all."

### Passing data across the boundary correctly

Two supported shapes, both explicitly recommended over passing model objects:

1. **`PersistentIdentifier`** — a lightweight, `Sendable` value type that uniquely
   identifies a specific model instance's underlying row, independent of which
   context fetched it. Pass the identifier, then re-fetch (`context.model(for:)` /
   a fetch predicate on `persistentModelID`) on the *receiving* actor's own context.
2. **Plain `Sendable` DTO structs** — when the receiving side needs a snapshot of
   values rather than a live, refetchable reference (e.g. the sync engine reporting
   "here are the 12 rows that just changed" back to the `@MainActor` service for a
   toast/badge), mirror only the fields needed into a plain `struct: Sendable` and
   pass that. Never pass the `@Model` class itself, even for read-only display.

### `@MainActor` for the UI-facing service

Mirror Bond's existing house style exactly
(`~/bond/Bond/Services/SupabaseService.swift`,
`~/bond/Bond/Services/PairingService.swift` — both `@MainActor @Observable final
class`, holding plain `Sendable` state like `UUID?`/`Bool`/DTO structs, calling into
`async` SDK methods and awaiting them from the main actor): a `SyncService` that
SwiftUI views bind to directly (no actor-hopping in view code), owning UI-relevant
state (`isSyncing`, `lastSyncedAt`, `pendingConflicts: [ConflictSummary]`) as plain
`Sendable` values, delegating the actual pull/merge/push work to the `@ModelActor`
`SyncEngine` and awaiting `Sendable` results back.

### Known sharp edges

- **A background `@ModelActor` write is not automatically visible to a `@MainActor`
  `@Query`.** SwiftData's change notification/autosave plumbing needs the main
  context to actually refresh; a common gotcha is a background sync completing
  successfully but the UI not updating until the next unrelated main-context save or
  an explicit refetch
  (<https://useyourloaf.com/blog/swiftdata-background-tasks/>,
  <https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency>).
  Have `SyncEngine` post a lightweight `Sendable` "sync completed, these
  `PersistentIdentifier`s changed" signal that the `@MainActor` service consumes to
  explicitly trigger a main-context refresh, rather than assuming `@Query` will just
  notice.
- **Relationship traversal is context-bound.** Don't fetch a `Medication` on
  `SyncEngine` and then, on another actor, touch `.person` or `.doses` — relationships
  are only safe to walk within the context/actor that fetched the root object.
  Refetch on whichever actor needs the traversal.
- **`ModelConfiguration`/`ModelContainer` creation itself should stay
  `@MainActor`-adjacent or at least single-sited** — `CareModelStore` already does
  this correctly today (a single `static let sharedModelContainer`); keep the sync
  engine consuming that same container rather than creating a second one, or the two
  contexts can observe different underlying store instances.
- **Enable complete concurrency checking** (Swift 6 language mode, which the project
  should already be on per `CLAUDE.md`'s "Swift 6 / SwiftUI (strict concurrency)")
  so all of the above are caught at compile time, not discovered as a Sendable
  runtime crash later.

---

## 4. Local data protection

### Recommendation: `NSFileProtectionCompleteUntilFirstUserAuthentication`, set explicitly

- **`.complete`** makes the file inaccessible the instant the device locks, and the
  decryption key is wiped from memory shortly after
  (<https://pspdfkit.com/blog/2017/how-to-use-ios-data-protection/>). That's
  incompatible with two things this design needs: the `SyncEngine`'s background
  pull/push (triggered by silent push or `BGAppRefreshTask`, §2/§6) touching
  SwiftData while the phone is locked in someone's pocket, and any future local
  notification handling that needs to read care data to build a rich notification
  body while locked.
- **`.completeUntilFirstUserAuthentication`** has been the actual default protection
  class for app data since iOS 7
  (<https://pspdfkit.com/blog/2017/how-to-use-ios-data-protection/>), is explicitly
  recommended for exactly this situation — "files that need to be accessed sometime
  later in the background when the device is locked, such as during a background
  fetch job" — and still fully protects the realistic threat model (device lost or
  stolen before ever being unlocked once since the last reboot). For a device that
  gets unlocked routinely (every real user's phone), the practical window during
  which data is inaccessible-and-therefore-safe versus accessible-and-therefore-usable
  is "before first unlock after a reboot" only — which is the correct trade for a
  medication-list app whose entire value proposition depends on background/locked
  readability.
- **Don't rely on the platform default without setting it explicitly.** Whether a
  given store file actually gets the platform default class can depend on
  entitlements, MDM profiles, or how/when the file was created; set it explicitly on
  the store URL (and its `-wal`/`-shm` companions) right after `ModelContainer`
  creation:

  ```swift
  try? FileManager.default.setAttributes(
    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
    ofItemAtPath: url.path
  )
  ```

  Apply this after **every** path that (re)creates the store file, including
  `CareModelStore`'s existing wipe-and-retry fallback (the schema-change recovery
  path already in `makeContainer`/`sharedModelContainer`) — a freshly recreated store
  file needs the attribute reapplied, it isn't inherited automatically in a way this
  design should depend on.

### Note on the ER scenario specifically

File protection only gates *background/locked-state* access — it has nothing to do
with the "no network, but the phone is unlocked and in the person's hand, actively
running the app" scenario, which is purely a networking/auth-gating concern (§1). The
two are easy to conflate; keep them conceptually separate when reviewing this design:
file protection protects the data at rest from an *attacker with the physical
device*, not from *the app itself* when its rightful user is holding it open.

### Full encryption (SQLCipher-class): not warranted

- iOS Data Protection classes are themselves a real encryption scheme — AES-256 keyed
  off a combination of the passcode/biometry-derived key and hardware UID, not "no
  encryption until you add a third-party library." `.completeUntilFirstUserAuthentication`
  plus the SDK's Keychain (`.afterFirstUnlock`, already the default per §1) already
  provides genuine at-rest, hardware-backed protection.
- A third-party encrypted-SQLite layer (SQLCipher or equivalent) mainly adds
  protection against a *different, higher* threat model: an attacker with the device
  unlocked and a jailbreak/runtime-inspection capability. That's a real threat for,
  e.g., a banking app; it is disproportionate engineering cost for a solo-developer
  consumer health app that (per `01-groups-rbac-rls.md`'s own framing) is explicitly
  "responsible design," not HIPAA/BAA-grade.
- Practically, it's also not a clean fit here: SwiftData's SQLite store doesn't have a
  first-class SQLCipher integration path the way raw Core Data or a hand-rolled GRDB
  store might, so adopting it would mean dropping SwiftData for the persistence layer
  entirely — a disproportionate architectural cost for the threat being mitigated.
- **Recommendation: file protection + Keychain is the right, proportionate bar for
  v1.** Revisit only if the product ever takes on an actual covered-entity/BAA
  obligation, which brief 01 already establishes it does not.

---

## 5. Migration of existing local-only installs

A TestFlight user today has local `Person`/`Medication`/etc. rows and no account.
Requirement: adopt them into a newly created group on sign-up, without duplicating
data, resumable if the migration fails partway, and non-destructive if the user
abandons signup.

### Migration sequence

1. **Never block launch on this.** The user opens the updated app and sees their
   existing local data immediately, exactly as before — the sign-in prompt is a
   visible but dismissible affordance, not a modal wall, consistent with the
   offline-first requirement running through the whole brief.
2. **On successful account creation**, call a `security definer` RPC —
   `adopt_local_group(p_user uuid) returns uuid` — that creates exactly one fresh
   `groups` row with the caller as `owner` and returns its `id`. One fresh signup
   always creates exactly one group; there's no ambiguity about "which group to
   adopt into" because none existed before.
3. **Client-side, walk local rows and upsert with the existing client UUIDs
   preserved as the server PK** (the §2 idempotency payoff, applied directly here):
   for each local `Person`, `upsert` a `care_recipients` row with
   `id = person.id`, `group_id = <returned group id>`, and the mapped fields; then
   for each of that person's `Medication`/`Visit`/`VitalReading`/`EmergencyContact`/
   `DoseLog` rows, `upsert` with `id` unchanged and the new `group_id`/foreign keys.
   Every insert is `on conflict (id) do update`, so re-running this step is always
   safe.
4. **Idempotent-by-construction, not idempotent-by-checking.** Don't try to make
   "did I already migrate this row" bulletproof via a flag check before every retry —
   the upsert semantics already make re-sending identical rows a no-op. Do keep a
   lightweight local `Set<UUID>` of confirmed-adopted ids (in UserDefaults, not
   SwiftData, so it survives a store wipe) purely as an optimization to skip
   re-uploading rows that haven't changed since their last confirmed sync, not as a
   correctness requirement.
5. **Resumable after a kill.** Because every step is an independent, idempotent
   upsert rather than one all-or-nothing transaction, an app kill (or lost network)
   partway through migrating, say, 3 people's worth of data simply means: relaunch,
   see the same "sign in to sync" prompt is now "syncing," and the walk resumes —
   already-adopted rows re-upsert harmlessly, not-yet-reached rows get picked up.
6. **Non-destructive on abandonment.** The migration is purely additive from the
   local store's point of view: it never deletes, mutates in place, or "cuts over"
   local rows. If the user backs out of signup entirely, the local SwiftData store is
   byte-for-byte what it was before — the app keeps working exactly as it does today,
   fully local-only, until they do sign up. Local data only becomes "a synced mirror"
   once a row is confirmed adopted; before that it's exactly what it already is.
7. **Schema change is additive, matching `CareModelStore`'s existing
   fail-soft philosophy.** Add the new sync-metadata fields (§2) as optional/defaulted
   properties (`var groupID: UUID?`, `var remoteUpdatedAt: Date?`, `var version: Int =
   0`, `var deletedAt: Date?`, `var isDirty: Bool = false`) rather than restructuring
   existing models. SwiftData's lightweight migration handles additive optional/
   defaulted columns automatically, and a migration failure still degrades to
   "local-only, unsynced" — consistent with the wipe-and-retry-then-memory-fallback
   pattern `CareModelStore.sharedModelContainer` already implements, rather than
   introducing a new way for this app to lose data on a schema hiccup.

---

## 6. Background execution

### `BGTaskScheduler`/`BGAppRefreshTask`: best-effort bonus only

Apple Developer Forums threads on real-world `BGAppRefreshTask` behavior are
consistent and blunt: scheduling requests are not guaranteed timers — "iOS decides
when to run them" and can decline entirely for infrequently-opened apps
(<https://developer.apple.com/forums/thread/725675>); on real devices developers have
reported not being able to trigger execution more than about once a day even when
requesting more frequent refresh, and processing-class background work is further
gated on power/network conditions
(<https://developer.apple.com/forums/thread/724506>,
<https://developer.apple.com/forums/thread/766206>). Treat any code path relying on
`BGAppRefreshTask` running "soon" or "regularly" as broken by design — it's a
supplementary top-up, registered because it's cheap to add and occasionally helps,
never load-bearing for anything the product depends on.

This also means the offline-launch guarantee this whole brief is built around is
**not** at risk from `BGAppRefreshTask` unreliability: the emergency card's
correctness property is "show the last-synced snapshot the device already has," which
SwiftData already satisfies unconditionally the moment any sync has ever succeeded
(foreground sync, §2, covers this in practice multiple times a day for an app people
open around dose times). "How stale can that snapshot be" is a UX quality question,
not the correctness question the brief is worried about.

### Silent push budget

Apple throttles `content-available` delivery against a per-device energy/data budget
that resets roughly daily and cannot be adjusted by the developer or user
(<https://medium.com/@shobhakartiwari/ios-silent-push-limits-7d0c65b642f4>); once
exhausted, further silent pushes are simply not delivered until the reset. Design
around this by treating silent push as "a nudge that sometimes lands," same tier as
`BGAppRefreshTask` — real value, no guarantee, foreground sync remains the mechanism
the correctness story depends on.

### Daily proof-of-life check-in reminder: local notification, not a background task

The parent's own "please check in" reminder must fire reliably at a set time of day —
this is exactly the case where `BGTaskScheduler` would be the wrong tool. Use a
locally scheduled `UNCalendarNotificationTrigger` (repeating, matching the configured
time-of-day) registered via `UNUserNotificationCenter` at setup time. This is OS-native
scheduled notification delivery, which iOS handles independently of background app
refresh budgets or task scheduling discretion — it's the one piece of this whole
design that should be treated as reliably delivered, precisely because it deliberately
avoids the background-execution machinery discussed above. The escalation side (family
gets notified if Mom didn't check in) is entirely server-driven per
`01-groups-rbac-rls.md`'s `pg_cron`/edge-function/APNs design — correctly, this does
**not** depend on anything running on Mom's device at all beyond the one reliable local
notification asking her to tap the button.

---

## 7. Testing

### In-memory containers, extended for multi-device scenarios

`CareModelStore.makeInMemoryContainer()` already exists for previews/tests. Extend the
same pattern to spin up two (or more) independent in-memory `ModelContainer`s
representing separate physical devices in the same family group, each driven through
its own `SyncEngine`, both talking to one shared fake remote — this is what makes
multi-device conflict scenarios (two caregivers editing offline, then both syncing)
testable at all without any real backend.

### Protocol-fronted remote

```swift
protocol SyncRemote: Sendable {
  func pull(table: String, groupIDs: [UUID], since cursor: SyncCursor?) async throws -> SyncPage
  func push(_ entries: [OutboxEntry]) async throws -> [PushResult]
}
```

The production implementation wraps `SupabaseClient`; tests inject an in-memory
`actor FakeSyncRemote: SyncRemote` holding `[UUID: RemoteRow]` per table, capable of
simulating: normal accept, a version-mismatch rejection, a unique-constraint
rejection (dose-log dedup), a 403 (RLS/role-changed), and a thrown `URLError` (offline).
This is the standard ports-and-adapters seam and is the only realistic way to get
deterministic, fast, CI-safe coverage of cursor pagination, conflict handling, and
RLS-rejection handling — none of which are reliably reproducible or fast against a
live Supabase project with real RLS timing.

### Cases that must have tests

1. Push a `Medication` edit against a stale `version` → surfaced conflict, not a
   silent overwrite of the other caregiver's concurrent edit.
2. Two simulated devices insert a `DoseLog` for the same
   `(medication_id, scheduled_at)` → dedup to one visible entry, not two.
3. Pull pagination across multiple pages, including rows sharing an identical
   `updated_at` at a page boundary → no row skipped, no row duplicated.
4. A push rejected with a simulated `403` (role changed while offline) → outbox entry
   moves to "needs review," is not auto-retried, and doesn't block/corrupt processing
   of other pending outbox entries.
5. A server-side soft delete (`deleted_at` set) pulled while a local edit to that same
   row is still queued in the outbox → the queued edit is discarded with a surfaced
   notice, never resurrected as a new insert of a deleted record.
6. **Offline launch**: `currentSession` present locally, `FakeSyncRemote` throws
   `URLError` for every call → the app renders cached `Person`/`Medication` data
   immediately with no spinner/login wall, and neither the cached session nor the
   local SwiftData rows are touched.
7. Migration idempotency (§5): run the local-orphan-adoption walk twice against a
   fresh `FakeSyncRemote` (simulating a kill-and-relaunch mid-migration) → the second
   run produces no duplicate `care_recipients`/`medications` rows.
8. Cross-actor visibility regression test for the §3 sharp edge: a `SyncEngine`
   (`@ModelActor`) write completes, and a `@MainActor`-observed `@Query`/fetch
   reflects it after the documented refresh signal, without requiring an unrelated
   main-context save to "accidentally" pick it up.

---

## Swift type sketches

Design sketches only — signatures and shapes to implement from, not finished code.

```swift
// MARK: - Sync metadata (added fields, sketched as an extension of each existing
// @Model; SwiftData doesn't support real protocol conformance for stored
// properties, so this is a documentation/consistency contract, not a compiled
// protocol every model conforms to.)

/// Fields added to every synced entity (Person/care_recipients, Medication,
/// DoseLog, Visit, VitalReading, EmergencyContact). Same shape, copy-pasted onto
/// each @Model rather than shared via a protocol.
///
///   var groupID: UUID?            // nil until adopted into a group (§5)
///   var remoteUpdatedAt: Date?    // server-set, mirrors Postgres updated_at
///   var version: Int = 0          // server-set, optimistic concurrency
///   var deletedAt: Date?          // tombstone; no hard deletes once synced
///   var isDirty: Bool = false     // local-only, not synced
///   var lastSyncedAt: Date?       // local-only, not synced

// MARK: - Sync cursor (device-wide, stored outside SwiftData)

struct SyncCursor: Sendable, Codable {
    var updatedAt: Date
    var tieBreakID: UUID
}

/// Persisted in UserDefaults (or a single local-only row), keyed by table name.
enum SyncCursorStore {
    static func cursor(for table: String) -> SyncCursor?
    static func save(_ cursor: SyncCursor, for table: String)
}

// MARK: - Outbox

enum OutboxOperation: String, Codable, Sendable { case insert, update, delete }

enum OutboxStatus: String, Codable, Sendable {
    case pending, inFlight, needsReview, failedPermanently
}

/// One queued local write. `payload` is a Sendable snapshot (not the @Model
/// instance) — encoded/decoded independent of any ModelContext.
struct OutboxEntry: Sendable, Codable, Identifiable {
    let id: UUID                 // outbox entry id, distinct from the row's own id
    let table: String
    let rowID: UUID              // == the @Model's own `id`, reused as server PK
    let operation: OutboxOperation
    var payload: Data            // encoded Sendable DTO of the row's current fields
    var expectedVersion: Int?    // for update: the version last seen locally
    var status: OutboxStatus
    var attemptCount: Int
    var createdAt: Date
    var lastAttemptAt: Date?
}

// MARK: - Remote protocol (production impl wraps SupabaseClient; tests inject a fake)

struct SyncPage: Sendable {
    var rows: [Data]             // encoded rows, decoded per-table by the caller
    var nextCursor: SyncCursor?  // nil when this table is fully caught up
}

enum PushResult: Sendable {
    case accepted(newVersion: Int, remoteUpdatedAt: Date)
    case versionConflict(serverRow: Data)
    case duplicateKey(existingRow: Data)      // DoseLog dedup case
    case forbidden                            // RLS rejection — role changed, etc.
    case transportFailure(Error)              // offline/timeout — retry later
}

protocol SyncRemote: Sendable {
    func pull(table: String, groupIDs: [UUID], since cursor: SyncCursor?) async throws -> SyncPage
    func push(_ entry: OutboxEntry) async throws -> PushResult
}

// MARK: - Background sync actor

@ModelActor
actor SyncEngine {
    func pullAll(remote: some SyncRemote, groupIDs: [UUID]) async throws -> [PersistentIdentifier]
    func flushOutbox(remote: some SyncRemote) async throws -> SyncSummary
    func adoptLocalData(intoGroup groupID: UUID, remote: some SyncRemote) async throws
}

struct SyncSummary: Sendable {
    var pushed: Int
    var conflicts: [ConflictSummary]
    var rejected: [OutboxEntry]
}

struct ConflictSummary: Sendable, Identifiable {
    let id: UUID              // rowID in conflict
    let table: String
    let localSnapshot: Data
    let serverSnapshot: Data
}

// MARK: - MainActor-facing service (house style: mirrors Bond's SupabaseService)

@MainActor
@Observable
final class SyncService {
    private let engine: SyncEngine
    private let remote: any SyncRemote

    var isSyncing = false
    var lastSyncedAt: Date?
    var pendingConflicts: [ConflictSummary] = []
    var rejectedChanges: [OutboxEntry] = []

    func syncOnForeground() async { /* pullAll + flushOutbox, update published state */ }
    func resolveConflict(_ conflict: ConflictSummary, keeping resolution: ConflictResolution) async
}

enum ConflictResolution: Sendable {
    case keepLocal
    case keepServer
    case merged(Data)   // caller-constructed merged payload
}

// MARK: - Auth/session gating (topic 1)

@MainActor
@Observable
final class AuthSessionService {
    private let client: SupabaseClient   // configured with emitLocalSessionAsInitialSession: true

    /// Backed by `client.auth.currentSession` — synchronous, never throws, never
    /// touches the network. This is what launch/routing/the emergency card gate on.
    var cachedUserID: UUID? { client.auth.currentSession?.user.id }

    /// True only after a *definitive* server-confirmed revocation
    /// (invalid_grant / refresh token not found) — never set from a transport error.
    private(set) var isDefinitivelySignedOut = false

    func refreshIfPossible() async {
        do {
            _ = try await client.auth.session   // may throw — offline is fine, ignored
        } catch let error as URLError {
            // offline/transport — do nothing to cached session or local data
        } catch {
            if Self.isDefiniteRevocation(error) {
                isDefinitivelySignedOut = true   // route to re-auth; DO NOT wipe SwiftData
            }
            // any other error: treat as transient, do nothing
        }
    }

    private static func isDefiniteRevocation(_ error: Error) -> Bool { /* inspect AuthError.api body */ }
}
```
