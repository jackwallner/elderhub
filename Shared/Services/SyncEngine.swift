import Foundation
import OSLog
import SwiftData

/// Two-way sync between the local SwiftData store and Postgres.
///
/// The store is the source of truth for *reading*. Sync writes into it and
/// never sits in front of it, so every screen renders from local data whether
/// or not the network is there. That ordering is the whole reason the emergency
/// card works in a hospital basement.
///
/// A `@ModelActor` because `ModelContext` is not `Sendable` and must not be
/// touched from more than one isolation domain. Everything crossing in or out
/// of this actor is a plain `Sendable` DTO or a `PersistentIdentifier`, never a
/// `@Model` instance.
@ModelActor
actor SyncEngine {
    private var log: Logger { Logger(subsystem: "com.jackwallner.aging", category: "sync") }

    private static let pageSize = 200
    private static let maxAttempts = 6

    /// Result of one full cycle, for the UI to report without needing details.
    struct Outcome: Sendable, Equatable {
        var pulled = 0
        var pushed = 0
        var conflicts = 0
        var needsReview = 0
        var wasOffline = false
        /// The first thing that went wrong, already phrased for a person. Nil
        /// means the cycle actually completed, which is the only condition
        /// under which anything may claim the app is synced.
        var failure: String?

        var isComplete: Bool { failure == nil }
    }

    // MARK: - Entry point

    func sync(remote: any SyncRemote, groupID: UUID) async -> Outcome {
        var outcome = Outcome()

        // Before anything is asked for, because it decides what to ask for.
        repairParentlessRowsIfNeeded()

        // Pull and push are two independent halves, not a sequence. They used
        // to share one `do`, so a single failing table threw out of the pull
        // and the push was never attempted at all: a dose logged at a bedside
        // sat in the outbox forever because some unrelated table was having a
        // bad day. A queued write has to leave the phone regardless.
        let pull = await pullAll(remote: remote)
        outcome.pulled = pull.applied
        record(pull.failure, into: &outcome)

        do {
            let pushResult = try await pushOutbox(remote: remote, groupID: groupID)
            outcome.pushed = pushResult.pushed
            outcome.needsReview = pushResult.needsReview
            // A queue where every entry was refused is not a completed cycle,
            // however calmly `pushOutbox` returned from it.
            if outcome.failure == nil { outcome.failure = pushResult.failure }
        } catch {
            record(error, into: &outcome)
        }

        outcome.conflicts = conflictCount()
        return outcome
    }

    /// Folds a failure into the outcome, keeping the first one. Logging here
    /// rather than at each call site so no failure path can forget to.
    private func record(_ error: Error?, into outcome: inout Outcome) {
        guard let error else { return }
        if let syncError = error as? SyncError {
            if case .offline = syncError { outcome.wasOffline = true }
            log.notice("Sync stopped: \(String(describing: syncError))")
        } else {
            log.error("Sync failed: \(error.localizedDescription)")
        }
        if outcome.failure == nil { outcome.failure = Self.describe(error) }
    }

    private static func describe(_ error: Error) -> String {
        guard let syncError = error as? SyncError else { return error.localizedDescription }
        switch syncError {
        case .offline: return "No connection."
        case .rejected(let message), .server(let message):
            return message.isEmpty ? "The server refused the change." : message
        }
    }

    // MARK: - Pull

    private struct PullResult {
        var applied = 0
        var failure: Error?
    }

    private func pullAll(remote: any SyncRemote) async -> PullResult {
        var result = PullResult()
        // The tables that finished this cycle with nothing left waiting. It is
        // what tells a child with no parent apart from a child whose parent is
        // never coming: see `parentState`.
        var settledTables: Set<SyncEntity> = []
        // Parents before children, so a medication never arrives before the
        // person it belongs to.
        for entity in SyncEntity.pullOrder {
            do {
                let outcome = try await pull(entity: entity, remote: remote,
                                             settledTables: settledTables)
                result.applied += outcome.applied
                if outcome.isComplete { settledTables.insert(entity) }
            } catch {
                // Caught per entity, deliberately. One table the server is
                // refusing today must not stop the other ten from arriving,
                // and must not take the push down with it. The failure is
                // still carried out so nothing reports a healthy sync.
                if result.failure == nil { result.failure = error }
                log.error("Pull failed for \(entity.rawValue): \(String(describing: error))")
            }
        }
        try? modelContext.save()
        return result
    }

    /// What one table's pull did, rather than only how much of it landed.
    private struct EntityPull {
        var applied = 0
        /// Reached the end of the table with nothing deferred. Only then is a
        /// missing parent proof that the parent does not exist.
        var isComplete = false
    }

    private func pull(
        entity: SyncEntity, remote: any SyncRemote, settledTables: Set<SyncEntity>
    ) async throws -> EntityPull {
        var applied = 0
        var page = cursorPage(for: entity)

        // Keep asking until a short page proves we reached the end. A full page
        // never means "done", even if the next one turns out empty.
        while true {
            let batch: [any SyncDTO]
            switch entity {
            case .person:
                batch = try await remote.pull(PersonDTO.self, after: page, limit: Self.pageSize)
            case .medication:
                batch = try await remote.pull(MedicationDTO.self, after: page, limit: Self.pageSize)
            case .doseLog:
                batch = try await remote.pull(DoseLogDTO.self, after: page, limit: Self.pageSize)
            case .visit:
                batch = try await remote.pull(VisitDTO.self, after: page, limit: Self.pageSize)
            case .vital:
                batch = try await remote.pull(VitalDTO.self, after: page, limit: Self.pageSize)
            case .emergencyContact:
                batch = try await remote.pull(EmergencyContactDTO.self, after: page, limit: Self.pageSize)
            case .provider:
                batch = try await remote.pull(ProviderDTO.self, after: page, limit: Self.pageSize)
            case .careEvent:
                batch = try await remote.pull(CareEventDTO.self, after: page, limit: Self.pageSize)
            case .careTask:
                batch = try await remote.pull(CareTaskDTO.self, after: page, limit: Self.pageSize)
            case .note:
                batch = try await remote.pull(CareNoteDTO.self, after: page, limit: Self.pageSize)
            case .bill:
                batch = try await remote.pull(BillDTO.self, after: page, limit: Self.pageSize)
            case .checkIn:
                batch = try await remote.pull(CheckInDTO.self, after: page, limit: Self.pageSize)
            case .checkInSettings:
                batch = try await remote.pull(CheckInSettingsDTO.self, after: page, limit: Self.pageSize)
            }

            if batch.isEmpty { break }

            // The last row actually written, which is as far as the cursor may
            // move. A deferred row is not skipped: the page stops there and the
            // next cycle asks for it again, because the cursor is a high-water
            // mark and anything it passes is never offered to this device
            // twice.
            var settled: (any SyncDTO)?
            var deferred = false
            for dto in batch {
                switch apply(dto, settledTables: settledTables) {
                case .applied:
                    settled = dto
                    applied += 1
                case .discarded:
                    // The cursor may pass it: it was not written and it is not
                    // going to be. Holding the page here would stop this table
                    // forever over one row nothing can ever attach.
                    settled = dto
                case .deferred:
                    deferred = true
                }
                if deferred { break }
            }

            if let last = settled, let updatedAt = last.updated_at {
                page = SyncPage(updatedAt: updatedAt, id: last.id)
                // Advanced only from the server's own `updated_at`. Using the
                // device clock here would let a phone that is a few minutes
                // fast write a cursor into the future and stop seeing its
                // family's changes, silently and permanently.
                setCursor(entity: entity, page: page)
            }

            if deferred { return EntityPull(applied: applied, isComplete: false) }
            if batch.count < Self.pageSize { break }
        }

        return EntityPull(applied: applied, isComplete: true)
    }

    // MARK: - Applying a pulled row

    /// What happened to one pulled row.
    private enum ApplyOutcome {
        /// Written.
        case applied
        /// Not written, and never will be: its parent does not exist. The
        /// cursor is free to pass it.
        case discarded
        /// Not written *yet*. The page stops here and the next cycle asks for
        /// it again.
        case deferred
    }

    /// Writes one pulled row, or says why it did not.
    @discardableResult
    private func apply(_ dto: any SyncDTO, settledTables: Set<SyncEntity>) -> ApplyOutcome {
        switch parentState(of: dto, settledTables: settledTables) {
        case .present: break
        case .notYet: return .deferred
        case .gone: return .discarded
        }
        switch dto {
        case let dto as PersonDTO: applyPerson(dto)
        case let dto as MedicationDTO: applyMedication(dto)
        case let dto as DoseLogDTO: applyDoseLog(dto)
        case let dto as VisitDTO: applyVisit(dto)
        case let dto as VitalDTO: applyVital(dto)
        case let dto as EmergencyContactDTO: applyContact(dto)
        case let dto as ProviderDTO: applyProvider(dto)
        case let dto as CareEventDTO: applyCareEvent(dto)
        case let dto as CareTaskDTO: applyCareTask(dto)
        case let dto as CareNoteDTO: applyCareNote(dto)
        case let dto as BillDTO: applyBill(dto)
        case let dto as CheckInDTO: applyCheckIn(dto)
        case let dto as CheckInSettingsDTO: applyCheckInSettings(dto)
        default: break
        }
        return .applied
    }

    /// Where the row this one hangs off has got to.
    private enum ParentState {
        /// On the phone, or this row has no parent to speak of.
        case present
        /// Not here, and the table that would carry it has not finished
        /// arriving. Wait.
        case notYet
        /// Not here, and the table that would carry it *has* finished. The
        /// parent does not exist, so neither should this.
        case gone
    }

    /// Whether this row can be written yet, and if not, whether waiting helps.
    ///
    /// A child stored without its person is invisible: it belongs to no record,
    /// no screen lists it, and nothing later puts it right. Two builds shipped
    /// writing exactly that, so a phone whose person pull had failed filled up
    /// with visits and tasks attached to nobody while its cursor moved past
    /// them for good.
    ///
    /// The second half is the one that is easy to get wrong. Deleting a person
    /// *tombstones* them, and a tombstone creates nothing locally, while their
    /// medications and visits stay live rows on the server: nothing cascades a
    /// tombstone down there. So "the parent is not on this phone" is two
    /// different situations, and only one of them is worth waiting for.
    /// `settledTables` tells them apart: `pullOrder` fetches people before
    /// anything that hangs off one, so once `.person` has reached the end of
    /// the table with nothing deferred, a person who is still missing is a
    /// person who was deleted, and their leftover children are discarded rather
    /// than waited on. Without that, one deleted parent stops its children's
    /// table for good.
    ///
    /// Three cases never wait. A tombstone for a row this device never had is
    /// already a no-op. A row already held is applied whatever its parent looks
    /// like, so a phone carrying orphans from an older build is not stalled by
    /// its own history, and `bindPerson` repairs it in passing. And a person,
    /// a check-in and a check-in setting have no parent row to be missing.
    private func parentState(
        of dto: any SyncDTO, settledTables: Set<SyncEntity>
    ) -> ParentState {
        guard dto.deleted_at == nil, !hasLocalRow(dto) else { return .present }

        let parent: (entity: SyncEntity, exists: Bool)
        switch dto {
        case let dto as MedicationDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as DoseLogDTO: parent = (.medication, hasMedication(dto.medication_id))
        case let dto as VisitDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as VitalDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as EmergencyContactDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as ProviderDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as CareEventDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as CareTaskDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as CareNoteDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        case let dto as BillDTO: parent = (.person, hasPerson(dto.care_recipient_id))
        // A person has no parent, and the two check-in types carry `personID`
        // as a plain column rather than a relationship, so neither can be
        // orphaned by arriving early.
        default: return .present
        }

        if parent.exists { return .present }
        return settledTables.contains(parent.entity) ? .gone : .notYet
    }

    private func hasPerson(_ id: UUID) -> Bool {
        fetchOne(Person.self, #Predicate { $0.id == id }) != nil
    }

    private func hasMedication(_ id: UUID) -> Bool {
        fetchOne(Medication.self, #Predicate { $0.id == id }) != nil
    }

    private func hasLocalRow(_ dto: any SyncDTO) -> Bool {
        let id = dto.id
        switch dto {
        case is MedicationDTO: return fetchOne(Medication.self, #Predicate { $0.id == id }) != nil
        case is DoseLogDTO: return fetchOne(DoseLog.self, #Predicate { $0.id == id }) != nil
        case is VisitDTO: return fetchOne(Visit.self, #Predicate { $0.id == id }) != nil
        case is VitalDTO: return fetchOne(VitalReading.self, #Predicate { $0.id == id }) != nil
        case is EmergencyContactDTO: return fetchOne(EmergencyContact.self, #Predicate { $0.id == id }) != nil
        case is ProviderDTO: return fetchOne(Provider.self, #Predicate { $0.id == id }) != nil
        case is CareEventDTO: return fetchOne(CareEvent.self, #Predicate { $0.id == id }) != nil
        case is CareTaskDTO: return fetchOne(CareTask.self, #Predicate { $0.id == id }) != nil
        case is CareNoteDTO: return fetchOne(CareNote.self, #Predicate { $0.id == id }) != nil
        case is BillDTO: return fetchOne(Bill.self, #Predicate { $0.id == id }) != nil
        default: return false
        }
    }

    // MARK: - Binding a child to its parent

    /// Attaches a pulled row to the person it belongs to, unless it is attached
    /// already.
    ///
    /// Called on every apply, not only on the insert that creates the row, and
    /// that is the whole point. Builds 26 and 27 bound a parent on insert only,
    /// so a child that arrived before its person was written with no person and
    /// stayed that way: `person.liveVisits` and its siblings cannot reach a
    /// parentless row, so no screen lists it, the emergency card does not print
    /// it, and nothing later puts it right. `parentState` stops new ones being
    /// made; this repairs the ones already on the phone when they come round
    /// again.
    private func bindPerson(_ row: some PersonScoped, to recipientID: UUID) {
        guard row.person == nil else { return }
        row.person = fetchOne(Person.self, #Predicate { $0.id == recipientID })
    }

    /// The same rule one level down: a dose log hangs off a medication.
    private func bindMedication(_ log: DoseLog, to medicationID: UUID) {
        guard log.medication == nil else { return }
        log.medication = fetchOne(Medication.self, #Predicate { $0.id == medicationID })
    }

    // MARK: - Repairing a store filled by an older build

    /// Key for the one-time rewind. Version-named rather than generic, because
    /// a future repair is a different question and must not be answered by this
    /// one having already run.
    private static let parentlessRepairKey = "sync.repair.parentlessRows.v1"

    /// Offers the rows an older build orphaned one more chance to arrive.
    ///
    /// The pull loop catches per entity, so a `care_recipients` page that
    /// failed to decode never stopped `visits` from landing. A phone that
    /// joined a circle in that window wrote children attached to nobody *and*
    /// moved its cursor past them, and a cursor is a high-water mark: those
    /// rows are never offered again. Migration 0021 and `PostgrestCoding` stop
    /// the decode failing; neither goes back for what was already lost.
    ///
    /// Nothing is deleted. A parentless row may be the only copy of something
    /// somebody typed, and rewinding the cursor is enough on its own: the
    /// server sends the rows again and `bindPerson` attaches them this time.
    /// Local edits are still protected, because the re-pull goes through the
    /// same conflict rules as any other.
    ///
    /// Runs once per install, and does nothing at all on a store that has no
    /// parentless row, which is every store that never hit the bug.
    private func repairParentlessRowsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.parentlessRepairKey) else { return }

        // Marked done only once the work is done, in both directions. Setting
        // it first would spend the one attempt on a launch that was killed
        // before the rewind landed, and this is the only attempt there is.
        guard hasParentlessRow() else {
            defaults.set(true, forKey: Self.parentlessRepairKey)
            return
        }
        for entity in SyncEntity.allCases {
            setCursor(entity: entity, page: nil)
        }
        try? modelContext.save()
        defaults.set(true, forKey: Self.parentlessRepairKey)
        log.notice("Rewound every pull cursor: this store holds rows with no parent.")
    }

    private func hasParentlessRow() -> Bool {
        func anyParentless<T: PersistentModel & PersonScoped>(_ type: T.Type) -> Bool {
            let rows = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
            return rows.contains { $0.person == nil }
        }
        let doseLogs = (try? modelContext.fetch(FetchDescriptor<DoseLog>())) ?? []
        return anyParentless(Medication.self)
            || anyParentless(Visit.self)
            || anyParentless(VitalReading.self)
            || anyParentless(EmergencyContact.self)
            || anyParentless(Provider.self)
            || anyParentless(CareEvent.self)
            || anyParentless(CareTask.self)
            || anyParentless(CareNote.self)
            || anyParentless(Bill.self)
            || doseLogs.contains { $0.medication == nil }
    }

    /// The conflict rule for records where two people can plausibly disagree.
    ///
    /// Last-writer-wins is not acceptable for a drug dosage or an allergy list.
    /// If this device has unsent changes and the server has newer ones, we keep
    /// the local copy, leave it dirty, and flag it, so a human decides. Silently
    /// discarding either side is the one outcome that is never acceptable here.
    private func isRealConflict(localDirty: Bool, localUpdated: Date, serverUpdated: Date?) -> Bool {
        guard let serverUpdated else { return false }
        return localDirty && serverUpdated > localUpdated
    }

    /// The conflict rule for records where the later write is simply the right
    /// answer: a visit note, a vital reading, a provider's phone number.
    ///
    /// Last-writer-wins is only last-writer-wins if the two writes are actually
    /// compared. These entities used to take the pulled row unconditionally,
    /// which is pull-clobbers-local, not LWW: because a cycle pulls before it
    /// pushes, a visit note typed a minute ago was discarded the moment any
    /// older row for that id came down the wire. There is still no conflict
    /// flag here, by design, only a comparison.
    private func shouldKeepLocal(localDirty: Bool, localUpdated: Date, serverUpdated: Date?) -> Bool {
        guard localDirty else { return false }
        // An unsent local edit with nothing to compare against is the only
        // write we know about, so it stands and the outbox pushes it.
        guard let serverUpdated else { return true }
        return localUpdated > serverUpdated
    }

    private func applyPerson(_ dto: PersonDTO) {
        let id = dto.id
        let existing = fetchOne(Person.self, #Predicate { $0.id == id })

        if let existing {
            if isRealConflict(localDirty: existing.isDirty,
                              localUpdated: existing.updatedAt,
                              serverUpdated: dto.updated_at) {
                flagConflict(
                    entity: .person,
                    id: dto.id,
                    local: existing.displayLabel,
                    remote: dto.name
                )
                return
            }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
        } else {
            guard dto.deleted_at == nil else { return }
            let person = Person(name: dto.name, relationship: dto.relationship)
            person.id = dto.id
            write(dto, into: person)
            modelContext.insert(person)
        }
    }

    private func write(_ dto: PersonDTO, into person: Person) {
        person.name = dto.name
        person.relationship = dto.relationship
        person.birthDate = dto.birth_date
        person.bloodType = dto.blood_type
        person.colorIndex = dto.color_index
        person.allergies = dto.allergies
        person.conditions = dto.conditions
        person.notes = dto.notes
        person.surrogateAttestedAt = dto.surrogate_attested_at
        person.linkedUserID = dto.linked_user_id
        person.groupID = dto.group_id
        person.updatedAt = dto.updated_at ?? Date()
        person.isDirty = false
    }

    private func applyMedication(_ dto: MedicationDTO) {
        let id = dto.id
        let existing = fetchOne(Medication.self, #Predicate { $0.id == id })

        if let existing {
            if isRealConflict(localDirty: existing.isDirty,
                              localUpdated: existing.updatedAt,
                              serverUpdated: dto.updated_at) {
                flagConflict(
                    entity: .medication,
                    id: dto.id,
                    local: Self.describe(existing),
                    remote: Self.describe(dto)
                )
                return
            }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
            bindPerson(existing, to: dto.care_recipient_id)
        } else {
            guard dto.deleted_at == nil else { return }
            let medication = Medication(name: dto.name)
            medication.id = dto.id
            write(dto, into: medication)
            modelContext.insert(medication)
            bindPerson(medication, to: dto.care_recipient_id)
        }
    }

    private func write(_ dto: MedicationDTO, into medication: Medication) {
        medication.name = dto.name
        medication.strength = dto.strength
        medication.formRaw = dto.form
        medication.purpose = dto.purpose
        medication.prescriber = dto.prescriber
        medication.pharmacy = dto.pharmacy
        medication.providerID = dto.provider_id
        medication.pharmacyID = dto.pharmacy_id
        medication.instructions = dto.instructions
        medication.scheduleMinutes = dto.schedule_minutes
        medication.weekdays = dto.weekdays
        medication.isAsNeeded = dto.is_as_needed
        medication.isActive = dto.is_active
        medication.startDate = dto.start_date
        medication.endDate = dto.end_date
        medication.tracksRefills = dto.tracks_refills
        medication.quantityRemaining = dto.quantity_remaining
        medication.unitsPerDose = dto.units_per_dose
        medication.refillThresholdDays = dto.refill_threshold_days
        medication.lastFilledAt = dto.last_filled_at
        medication.groupID = dto.group_id
        medication.updatedAt = dto.updated_at ?? Date()
        medication.isDirty = false
    }

    /// A dose log is an event, not a state. Two devices logging the same dose is
    /// a duplicate to collapse, not a conflict to resolve, and both sides now
    /// agree on what "the same dose" means: `DoseLog.deterministicID` derives
    /// the primary key from (medication, scheduled time), so the two devices
    /// produce one id, the upsert is the no-op the design always promised, and
    /// the server's unique index on (medication_id, scheduled_at) is never
    /// reached. There is deliberately no conflict flag here, only the same LWW
    /// comparison the other event-shaped entities use.
    private func applyDoseLog(_ dto: DoseLogDTO) {
        let id = dto.id
        if let existing = fetchOne(DoseLog.self, #Predicate { $0.id == id }) {
            if shouldKeepLocal(localDirty: existing.isDirty,
                               localUpdated: existing.updatedAt,
                               serverUpdated: dto.updated_at) { return }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            existing.statusRaw = dto.status
            existing.note = dto.note
            existing.recordedBy = dto.recorded_by_name
            existing.groupID = dto.group_id
            existing.updatedAt = dto.updated_at ?? Date()
            existing.isDirty = false
            bindMedication(existing, to: dto.medication_id)
        } else {
            guard dto.deleted_at == nil else { return }
            let log = DoseLog(scheduledAt: dto.scheduled_at)
            log.id = dto.id
            log.recordedAt = dto.recorded_at
            log.statusRaw = dto.status
            log.recordedBy = dto.recorded_by_name
            log.note = dto.note
            log.groupID = dto.group_id
            log.updatedAt = dto.updated_at ?? Date()
            log.isDirty = false
            modelContext.insert(log)
            bindMedication(log, to: dto.medication_id)
        }
    }

    private func applyVisit(_ dto: VisitDTO) {
        let id = dto.id
        let existing = fetchOne(Visit.self, #Predicate { $0.id == id })
        if let existing, shouldKeepLocal(localDirty: existing.isDirty,
                                         localUpdated: existing.updatedAt,
                                         serverUpdated: dto.updated_at) { return }
        if let existing, dto.deleted_at != nil {
            modelContext.delete(existing)
            return
        }
        guard dto.deleted_at == nil else { return }
        let visit = existing ?? {
            let new = Visit(date: dto.date)
            new.id = dto.id
            modelContext.insert(new)
            return new
        }()
        bindPerson(visit, to: dto.care_recipient_id)
        visit.date = dto.date
        visit.provider = dto.provider
        visit.providerID = dto.provider_id
        visit.specialty = dto.specialty
        visit.reason = dto.reason
        visit.notes = dto.notes
        visit.followUp = dto.follow_up
        visit.nextAppointment = dto.next_appointment
        visit.groupID = dto.group_id
        visit.updatedAt = dto.updated_at ?? Date()
        visit.isDirty = false
    }

    private func applyVital(_ dto: VitalDTO) {
        let id = dto.id
        let existing = fetchOne(VitalReading.self, #Predicate { $0.id == id })
        if let existing, shouldKeepLocal(localDirty: existing.isDirty,
                                         localUpdated: existing.updatedAt,
                                         serverUpdated: dto.updated_at) { return }
        if let existing, dto.deleted_at != nil {
            modelContext.delete(existing)
            return
        }
        guard dto.deleted_at == nil else { return }
        let reading = existing ?? {
            let new = VitalReading(kind: .bloodPressure, primaryValue: 0)
            new.id = dto.id
            modelContext.insert(new)
            return new
        }()
        bindPerson(reading, to: dto.care_recipient_id)
        reading.kindRaw = dto.kind
        reading.primaryValue = dto.primary_value
        reading.secondaryValue = dto.secondary_value
        reading.recordedAt = dto.recorded_at
        reading.note = dto.note
        reading.groupID = dto.group_id
        reading.updatedAt = dto.updated_at ?? Date()
        reading.isDirty = false
    }

    private func applyContact(_ dto: EmergencyContactDTO) {
        let id = dto.id
        let existing = fetchOne(EmergencyContact.self, #Predicate { $0.id == id })
        if let existing, shouldKeepLocal(localDirty: existing.isDirty,
                                         localUpdated: existing.updatedAt,
                                         serverUpdated: dto.updated_at) { return }
        if let existing, dto.deleted_at != nil {
            modelContext.delete(existing)
            return
        }
        guard dto.deleted_at == nil else { return }
        let contact = existing ?? {
            let new = EmergencyContact(name: dto.name)
            new.id = dto.id
            modelContext.insert(new)
            return new
        }()
        bindPerson(contact, to: dto.care_recipient_id)
        contact.name = dto.name
        contact.relationship = dto.relationship
        contact.phone = dto.phone
        contact.isPrimary = dto.is_primary
        contact.groupID = dto.group_id
        contact.updatedAt = dto.updated_at ?? Date()
        contact.isDirty = false
    }

    /// Same shape as `applyContact`, and for the same reason: a provider is a
    /// contact card, not a value two family members plausibly fight over, so
    /// there is no conflict flag here, just the later of the two writes winning.
    private func applyProvider(_ dto: ProviderDTO) {
        let id = dto.id
        let existing = fetchOne(Provider.self, #Predicate { $0.id == id })
        if let existing, shouldKeepLocal(localDirty: existing.isDirty,
                                         localUpdated: existing.updatedAt,
                                         serverUpdated: dto.updated_at) { return }
        if let existing, dto.deleted_at != nil {
            modelContext.delete(existing)
            return
        }
        guard dto.deleted_at == nil else { return }
        let provider = existing ?? {
            let new = Provider(name: dto.name)
            new.id = dto.id
            modelContext.insert(new)
            return new
        }()
        bindPerson(provider, to: dto.care_recipient_id)
        provider.name = dto.name
        provider.specialty = dto.specialty
        provider.phone = dto.phone
        provider.address = dto.address
        provider.portalURL = dto.portal_url
        provider.notes = dto.notes
        provider.isPharmacy = dto.is_pharmacy
        provider.groupID = dto.group_id
        provider.updatedAt = dto.updated_at ?? Date()
        provider.isDirty = false
    }

    /// Same shape as `applyVital`: an incident log entry is not a value two
    /// family members plausibly fight over, so there is no conflict flag
    /// here, just the later of the two writes winning.
    private func applyCareEvent(_ dto: CareEventDTO) {
        let id = dto.id
        let existing = fetchOne(CareEvent.self, #Predicate { $0.id == id })
        if let existing, shouldKeepLocal(localDirty: existing.isDirty,
                                         localUpdated: existing.updatedAt,
                                         serverUpdated: dto.updated_at) { return }
        if let existing, dto.deleted_at != nil {
            modelContext.delete(existing)
            return
        }
        guard dto.deleted_at == nil else { return }
        let event = existing ?? {
            let new = CareEvent(kind: .other, occurredAt: dto.occurred_at)
            new.id = dto.id
            modelContext.insert(new)
            return new
        }()
        bindPerson(event, to: dto.care_recipient_id)
        event.kindRaw = dto.kind
        event.occurredAt = dto.occurred_at
        event.severity = dto.severity
        event.note = dto.note
        event.recordedBy = dto.recorded_by_name
        event.groupID = dto.group_id
        event.updatedAt = dto.updated_at ?? Date()
        event.isDirty = false
    }

    /// The one entity with a merge rule of its own (`CareTaskMerge`). Two
    /// siblings ticking off the same errand is the likeliest collision in the
    /// app and is agreement rather than conflict, while two people editing the
    /// same task's text in different directions is a real disagreement and goes
    /// to a human. Neither case is served by the flat pull-wins used for
    /// providers and care events.
    private func applyCareTask(_ dto: CareTaskDTO) {
        let id = dto.id
        let existing = fetchOne(CareTask.self, #Predicate { $0.id == id })

        if let existing {
            switch CareTaskMerge.resolve(
                localDirty: existing.isDirty,
                localUpdated: existing.updatedAt,
                localCompletedAt: existing.completedAt,
                serverUpdated: dto.updated_at,
                serverCompletedAt: dto.completed_at
            ) {
            case .keepLocal:
                return
            case .conflict:
                flagConflict(
                    entity: .careTask,
                    id: dto.id,
                    local: Self.describe(existing),
                    remote: Self.describe(dto)
                )
                return
            case .takeServer:
                break
            }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
            bindPerson(existing, to: dto.care_recipient_id)
        } else {
            guard dto.deleted_at == nil else { return }
            let task = CareTask(title: dto.title)
            task.id = dto.id
            write(dto, into: task)
            modelContext.insert(task)
            bindPerson(task, to: dto.care_recipient_id)
        }
    }

    private func write(_ dto: CareTaskDTO, into task: CareTask) {
        task.title = dto.title
        task.notes = dto.notes
        task.dueAt = dto.due_at
        task.priorityRaw = dto.priority
        task.recurrenceRaw = dto.recurrence
        task.assigneeUserID = dto.assignee_user_id
        task.assigneeName = dto.assignee_name
        task.completedAt = dto.completed_at
        task.completedByName = dto.completed_by_name
        task.createdByName = dto.created_by_name
        task.groupID = dto.group_id
        task.updatedAt = dto.updated_at ?? Date()
        task.isDirty = false
    }

    /// Free text two people can plausibly disagree about, so this flags rather
    /// than merges. A note is one field end to end: silently taking the server
    /// copy does not lose a detail, it loses the whole thing someone typed.
    private func applyCareNote(_ dto: CareNoteDTO) {
        let id = dto.id
        let existing = fetchOne(CareNote.self, #Predicate { $0.id == id })

        if let existing {
            if isRealConflict(localDirty: existing.isDirty,
                              localUpdated: existing.updatedAt,
                              serverUpdated: dto.updated_at) {
                flagConflict(
                    entity: .note,
                    id: dto.id,
                    local: Self.describe(existing.body),
                    remote: Self.describe(dto.body)
                )
                return
            }
            if shouldKeepLocal(localDirty: existing.isDirty,
                               localUpdated: existing.updatedAt,
                               serverUpdated: dto.updated_at) { return }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
            bindPerson(existing, to: dto.care_recipient_id)
        } else {
            guard dto.deleted_at == nil else { return }
            let note = CareNote()
            note.id = dto.id
            write(dto, into: note)
            modelContext.insert(note)
            bindPerson(note, to: dto.care_recipient_id)
        }
    }

    private func write(_ dto: CareNoteDTO, into note: CareNote) {
        note.title = dto.title
        note.body = dto.body
        note.isPinned = dto.is_pinned
        note.createdByName = dto.created_by_name
        note.groupID = dto.group_id
        note.updatedAt = dto.updated_at ?? Date()
        note.isDirty = false
    }

    /// Two people can plausibly disagree about a bill's amount or due date, so
    /// this flags rather than merges, exactly like a note or a visit.
    ///
    /// `paid_at` is deliberately not merged specially. Two siblings marking the
    /// same bill paid looks like the agreement case `CareTaskMerge` handles, but
    /// it is not: a bill paid twice is a real thing that happens, and the app
    /// must not quietly decide that two payment records are one. The row that
    /// arrives is applied; if both edited it, a human is asked.
    private func applyBill(_ dto: BillDTO) {
        let id = dto.id
        let existing = fetchOne(Bill.self, #Predicate { $0.id == id })

        if let existing {
            if isRealConflict(localDirty: existing.isDirty,
                              localUpdated: existing.updatedAt,
                              serverUpdated: dto.updated_at) {
                flagConflict(
                    entity: .bill,
                    id: dto.id,
                    local: Self.describe(existing),
                    remote: Self.describe(dto)
                )
                return
            }
            if shouldKeepLocal(localDirty: existing.isDirty,
                               localUpdated: existing.updatedAt,
                               serverUpdated: dto.updated_at) { return }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
            bindPerson(existing, to: dto.care_recipient_id)
        } else {
            guard dto.deleted_at == nil else { return }
            let bill = Bill(payee: dto.payee)
            bill.id = dto.id
            write(dto, into: bill)
            modelContext.insert(bill)
            bindPerson(bill, to: dto.care_recipient_id)
        }
    }

    private func write(_ dto: BillDTO, into bill: Bill) {
        bill.payee = dto.payee
        bill.amount = dto.amount
        bill.notes = dto.notes
        bill.categoryRaw = dto.category
        bill.recurrenceRaw = dto.recurrence
        bill.dueAt = dto.due_at
        bill.isAutoPay = dto.is_auto_pay
        bill.paidAt = dto.paid_at
        bill.paidByName = dto.paid_by_name
        bill.createdByName = dto.created_by_name
        bill.groupID = dto.group_id
        bill.updatedAt = dto.updated_at ?? Date()
        bill.isDirty = false
    }

    private func applyCheckIn(_ dto: CheckInDTO) {
        let id = dto.id
        if fetchOne(CheckInRecord.self, #Predicate { $0.id == id }) != nil { return }
        let record = CheckInRecord(
            id: dto.id,
            groupID: dto.group_id,
            personID: dto.care_recipient_id,
            source: CheckInSource(rawValue: dto.source) ?? .selfPressed,
            pressedByName: dto.pressed_by_name,
            pressedAt: dto.pressed_at
        )
        record.isDirty = false
        record.updatedAt = dto.updated_at ?? Date()
        modelContext.insert(record)
    }

    /// Settings are a state, not an event, so last-writer-wins is correct here
    /// in a way it is not for a dosage. The only realistic conflict is two
    /// caregivers nudging the same window on the same afternoon.
    private func applyCheckInSettings(_ dto: CheckInSettingsDTO) {
        let id = dto.care_recipient_id
        let existing = fetchOne(CheckInSettings.self, #Predicate { $0.personID == id })

        let settings = existing ?? {
            let new = CheckInSettings(personID: dto.care_recipient_id, groupID: dto.group_id)
            modelContext.insert(new)
            return new
        }()

        if isRealConflict(localDirty: settings.isDirty,
                          localUpdated: settings.updatedAt,
                          serverUpdated: dto.updated_at) {
            return
        }

        settings.groupID = dto.group_id
        settings.enabled = dto.enabled
        settings.windowStartMinute = dto.window_start_minute
        settings.windowEndMinute = dto.window_end_minute
        settings.graceMinutes = dto.grace_minutes
        settings.timeZoneIdentifier = dto.timezone
        settings.updatedAt = dto.updated_at ?? Date()
        settings.isDirty = false
    }

    // MARK: - Push

    struct PushResult: Sendable {
        var pushed = 0
        var needsReview = 0
        /// The first entry-level rejection. `pushOutbox` swallows these by
        /// design, because one bad row must not stop the rest of the queue, but
        /// swallowing them silently is how a cycle where nothing was accepted
        /// still reported itself as a successful sync.
        var failure: String?
    }

    private func pushOutbox(remote: any SyncRemote, groupID: UUID) async throws -> PushResult {
        var result = PushResult()
        let now = Date()
        let entries = (try? modelContext.fetch(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.statusRaw != "needsReview" && $0.notBefore <= now },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []

        // Coalesce. Several queued edits to the same medication collapse into
        // one upsert because only the final state reaches the server anyway.
        // Dose logs and check-ins never collapse: each is a separate thing that
        // happened, and merging them would erase a dose from the record.
        var seen = Set<String>()
        var work: [OutboxEntry] = []
        for entry in entries {
            let key = "\(entry.entityTypeRaw):\(entry.entityID)"
            if entry.entityType.isCoalescable {
                if seen.contains(key) {
                    modelContext.delete(entry)
                    continue
                }
                seen.insert(key)
            }
            work.append(entry)
        }

        for entry in work {
            do {
                try await push(entry: entry, remote: remote, groupID: groupID)
                markSynced(entry)
                modelContext.delete(entry)
                result.pushed += 1
            } catch let error as SyncError {
                switch error {
                case .offline:
                    // Leave it queued exactly as it is and stop: the rest will
                    // fail the same way and hammering a dead network wastes
                    // battery on a phone that may be someone's only one.
                    try? modelContext.save()
                    throw error
                case .rejected(let message), .server(let message):
                    entry.attempts += 1
                    entry.lastError = message
                    if result.failure == nil { result.failure = Self.describe(error) }
                    if case .rejected = error {
                        // Almost always a role that changed while this device
                        // was offline: a demoted caregiver's queued medication
                        // edits are no longer permitted. Retrying forever would
                        // never succeed and would hide the reason, so a person
                        // is told instead.
                        entry.status = .needsReview
                        result.needsReview += 1
                    } else if entry.attempts >= Self.maxAttempts {
                        entry.status = .needsReview
                        result.needsReview += 1
                    } else {
                        entry.status = .retrying
                        entry.notBefore = Date().addingTimeInterval(
                            pow(2, Double(entry.attempts)) * 5
                        )
                    }
                }
            }
        }

        try? modelContext.save()
        return result
    }

    private func push(entry: OutboxEntry, remote: any SyncRemote, groupID: UUID) async throws {
        let id = entry.entityID
        switch entry.entityType {
        case .person:
            guard let person = fetchOne(Person.self, #Predicate { $0.id == id }) else { return }
            try await remote.push([PersonDTO(
                id: person.id, group_id: groupID, linked_user_id: person.linkedUserID,
                name: person.name, relationship: person.relationship,
                birth_date: person.birthDate, blood_type: person.bloodType,
                color_index: person.colorIndex, allergies: person.allergies,
                conditions: person.conditions, notes: person.notes,
                surrogate_attested_at: person.surrogateAttestedAt,
                last_check_in_at: nil, created_by_name: nil,
                updated_at: nil, deleted_at: person.deletedAt
            )])

        case .medication:
            guard let med = fetchOne(Medication.self, #Predicate { $0.id == id }),
                  let recipientID = med.person?.id else { return }
            try await remote.push([MedicationDTO(
                id: med.id, group_id: groupID, care_recipient_id: recipientID,
                name: med.name, strength: med.strength, form: med.formRaw,
                purpose: med.purpose, prescriber: med.prescriber, pharmacy: med.pharmacy,
                provider_id: med.providerID, pharmacy_id: med.pharmacyID,
                instructions: med.instructions, schedule_minutes: med.scheduleMinutes,
                weekdays: med.weekdays, is_as_needed: med.isAsNeeded,
                is_active: med.isActive, start_date: med.startDate, end_date: med.endDate,
                tracks_refills: med.tracksRefills,
                quantity_remaining: med.quantityRemaining, units_per_dose: med.unitsPerDose,
                refill_threshold_days: med.refillThresholdDays, last_filled_at: med.lastFilledAt,
                updated_by_name: nil, updated_at: nil, deleted_at: med.deletedAt
            )])

        case .doseLog:
            guard let log = fetchOne(DoseLog.self, #Predicate { $0.id == id }),
                  let medicationID = log.medication?.id else { return }
            try await remote.push([DoseLogDTO(
                id: log.id, group_id: groupID, medication_id: medicationID,
                scheduled_at: log.scheduledAt, recorded_at: log.recordedAt,
                status: log.statusRaw, recorded_by_name: log.recordedBy,
                note: log.note, updated_at: nil, deleted_at: log.deletedAt
            )])

        case .visit:
            guard let visit = fetchOne(Visit.self, #Predicate { $0.id == id }),
                  let recipientID = visit.person?.id else { return }
            try await remote.push([VisitDTO(
                id: visit.id, group_id: groupID, care_recipient_id: recipientID,
                date: visit.date, provider: visit.provider, provider_id: visit.providerID,
                specialty: visit.specialty,
                reason: visit.reason, notes: visit.notes, follow_up: visit.followUp,
                next_appointment: visit.nextAppointment,
                updated_at: nil, deleted_at: visit.deletedAt
            )])

        case .vital:
            guard let vital = fetchOne(VitalReading.self, #Predicate { $0.id == id }),
                  let recipientID = vital.person?.id else { return }
            try await remote.push([VitalDTO(
                id: vital.id, group_id: groupID, care_recipient_id: recipientID,
                kind: vital.kindRaw, primary_value: vital.primaryValue,
                secondary_value: vital.secondaryValue, recorded_at: vital.recordedAt,
                note: vital.note, updated_at: nil, deleted_at: vital.deletedAt
            )])

        case .emergencyContact:
            guard let contact = fetchOne(EmergencyContact.self, #Predicate { $0.id == id }),
                  let recipientID = contact.person?.id else { return }
            try await remote.push([EmergencyContactDTO(
                id: contact.id, group_id: groupID, care_recipient_id: recipientID,
                name: contact.name, relationship: contact.relationship,
                phone: contact.phone, is_primary: contact.isPrimary,
                updated_at: nil, deleted_at: contact.deletedAt
            )])

        case .provider:
            guard let provider = fetchOne(Provider.self, #Predicate { $0.id == id }),
                  let recipientID = provider.person?.id else { return }
            try await remote.push([ProviderDTO(
                id: provider.id, group_id: groupID, care_recipient_id: recipientID,
                name: provider.name, specialty: provider.specialty, phone: provider.phone,
                address: provider.address, portal_url: provider.portalURL, notes: provider.notes,
                is_pharmacy: provider.isPharmacy,
                updated_at: nil, deleted_at: provider.deletedAt
            )])

        case .careEvent:
            guard let event = fetchOne(CareEvent.self, #Predicate { $0.id == id }),
                  let recipientID = event.person?.id else { return }
            try await remote.push([CareEventDTO(
                id: event.id, group_id: groupID, care_recipient_id: recipientID,
                kind: event.kindRaw, occurred_at: event.occurredAt, severity: event.severity,
                note: event.note, recorded_by_name: event.recordedBy,
                updated_at: nil, deleted_at: event.deletedAt
            )])

        case .careTask:
            guard let task = fetchOne(CareTask.self, #Predicate { $0.id == id }),
                  let recipientID = task.person?.id else { return }
            try await remote.push([CareTaskDTO(
                id: task.id, group_id: groupID, care_recipient_id: recipientID,
                title: task.title, notes: task.notes, due_at: task.dueAt,
                priority: task.priorityRaw, recurrence: task.recurrenceRaw,
                assignee_user_id: task.assigneeUserID, assignee_name: task.assigneeName,
                completed_at: task.completedAt, completed_by_name: task.completedByName,
                created_by_name: task.createdByName,
                updated_at: nil, deleted_at: task.deletedAt
            )])

        case .note:
            guard let note = fetchOne(CareNote.self, #Predicate { $0.id == id }),
                  let recipientID = note.person?.id else { return }
            try await remote.push([CareNoteDTO(
                id: note.id, group_id: groupID, care_recipient_id: recipientID,
                title: note.title, body: note.body, is_pinned: note.isPinned,
                created_by_name: note.createdByName,
                updated_at: nil, deleted_at: note.deletedAt
            )])

        case .bill:
            guard let bill = fetchOne(Bill.self, #Predicate { $0.id == id }),
                  let recipientID = bill.person?.id else { return }
            try await remote.push([BillDTO(
                id: bill.id, group_id: groupID, care_recipient_id: recipientID,
                payee: bill.payee, amount: bill.amount, notes: bill.notes,
                category: bill.categoryRaw, recurrence: bill.recurrenceRaw,
                due_at: bill.dueAt, is_auto_pay: bill.isAutoPay,
                paid_at: bill.paidAt, paid_by_name: bill.paidByName,
                created_by_name: bill.createdByName,
                updated_at: nil, deleted_at: bill.deletedAt
            )])

        case .checkIn:
            guard let record = fetchOne(CheckInRecord.self, #Predicate { $0.id == id }) else { return }
            try await remote.push([CheckInDTO(
                id: record.id, group_id: groupID, care_recipient_id: record.personID,
                source: record.sourceRaw, pressed_by: nil,
                pressed_by_name: record.pressedByName, pressed_at: record.pressedAt,
                note: record.note, updated_at: nil
            )])

        case .checkInSettings:
            // Keyed on the recipient: the outbox entry's `entityID` is the
            // person, not a row id of its own.
            guard let settings = fetchOne(CheckInSettings.self, #Predicate { $0.personID == id }),
                  let settingsGroupID = settings.groupID else { return }
            try await remote.push([CheckInSettingsDTO(
                care_recipient_id: settings.personID, group_id: settingsGroupID,
                enabled: settings.enabled,
                window_start_minute: settings.windowStartMinute,
                window_end_minute: settings.windowEndMinute,
                grace_minutes: settings.graceMinutes,
                timezone: settings.timeZoneIdentifier,
                updated_at: nil
            )])
        }
    }

    private func markSynced(_ entry: OutboxEntry) {
        let id = entry.entityID
        switch entry.entityType {
        case .person: settle(fetchOne(Person.self, #Predicate { $0.id == id }))
        case .medication: settle(fetchOne(Medication.self, #Predicate { $0.id == id }))
        case .doseLog: settle(fetchOne(DoseLog.self, #Predicate { $0.id == id }))
        case .visit: settle(fetchOne(Visit.self, #Predicate { $0.id == id }))
        case .vital: settle(fetchOne(VitalReading.self, #Predicate { $0.id == id }))
        case .emergencyContact: settle(fetchOne(EmergencyContact.self, #Predicate { $0.id == id }))
        case .provider: settle(fetchOne(Provider.self, #Predicate { $0.id == id }))
        case .careEvent: settle(fetchOne(CareEvent.self, #Predicate { $0.id == id }))
        case .careTask: settle(fetchOne(CareTask.self, #Predicate { $0.id == id }))
        case .note: settle(fetchOne(CareNote.self, #Predicate { $0.id == id }))
        case .bill: settle(fetchOne(Bill.self, #Predicate { $0.id == id }))
        case .checkIn: fetchOne(CheckInRecord.self, #Predicate { $0.id == id })?.isDirty = false
        case .checkInSettings:
            fetchOne(CheckInSettings.self, #Predicate { $0.personID == id })?.isDirty = false
        }
    }

    /// Clears the dirty flag, and clears the row itself out once a tombstone
    /// has reached the server. Local deletes keep the row alive only so the
    /// push has something to read (`SyncableRecord.tombstone`); holding it any
    /// longer would grow the store forever with rows nothing renders.
    private func settle<T: PersistentModel & SyncableRecord>(_ record: T?) {
        guard let record else { return }
        record.isDirty = false
        if record.deletedAt != nil { modelContext.delete(record) }
    }

    // MARK: - Queueing

    /// Called by the UI layer after any local change.
    func enqueue(entity: SyncEntity, id: UUID, groupID: UUID?) {
        modelContext.insert(OutboxEntry(entityType: entity, entityID: id, groupID: groupID))
        try? modelContext.save()
    }

    /// Adoption of a local-only install: stamp the group onto every existing row
    /// and queue it. No dedicated server RPC, because the client UUIDs are
    /// already the server primary keys, so this is just the ordinary write path
    /// and inherits its idempotency and its resumability for free.
    func adoptLocalData(into groupID: UUID) {
        // Every syncable table, not just the three the medication list is built
        // from. A visit or an emergency contact left behind here is invisibly
        // local forever: nothing later marks it dirty, so it never reaches the
        // sibling who just joined.
        func adopt<T: PersistentModel & SyncableRecord>(_ type: T.Type) {
            let rows = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
            for row in rows {
                if row.groupID == nil {
                    row.groupID = groupID
                    row.isDirty = true
                }
                modelContext.insert(
                    OutboxEntry(entityType: T.syncEntity, entityID: row.id, groupID: groupID)
                )
            }
        }

        adopt(Person.self)
        adopt(Provider.self)
        adopt(Medication.self)
        adopt(DoseLog.self)
        adopt(Visit.self)
        adopt(VitalReading.self)
        adopt(EmergencyContact.self)
        adopt(CareEvent.self)
        adopt(CareTask.self)
        adopt(CareNote.self)
        adopt(Bill.self)

        try? modelContext.save()
    }

    /// Adopts **one** recipient and everything hanging off them into a group,
    /// leaving every other local-only row exactly where it was.
    ///
    /// `adoptLocalData` sweeps the whole store, which is right for "I just made
    /// a circle out of what is already on this phone" and wrong for the case
    /// this exists for: someone who tracked a parent privately and then joined
    /// a sibling's circle for a different parent. Uploading everything on their
    /// phone into someone else's family, because they accepted an invitation,
    /// is not a migration, it is a disclosure they never agreed to. So the join
    /// path adopts nothing, the two worlds are shown apart, and moving one
    /// person across is a deliberate act with this behind it.
    func adoptPerson(id personID: UUID, into groupID: UUID) {
        guard let person = fetchOne(Person.self, #Predicate { $0.id == personID }) else { return }

        func stamp<T: PersistentModel & SyncableRecord>(_ row: T) {
            if row.groupID == nil {
                row.groupID = groupID
                row.isDirty = true
            }
            modelContext.insert(
                OutboxEntry(entityType: T.syncEntity, entityID: row.id, groupID: groupID)
            )
        }

        stamp(person)
        for provider in person.providers { stamp(provider) }
        for medication in person.medications {
            stamp(medication)
            // Dose logs hang off the medication, not off the person, so a
            // sweep by `person` alone leaves the whole history behind.
            for dose in medication.doses { stamp(dose) }
        }
        for visit in person.visits { stamp(visit) }
        for vital in person.vitals { stamp(vital) }
        for contact in person.contacts { stamp(contact) }
        for event in person.careEvents { stamp(event) }
        for task in person.tasks { stamp(task) }
        for note in person.savedNotes { stamp(note) }
        for bill in person.bills { stamp(bill) }

        try? modelContext.save()
    }

    // MARK: - Conflicts

    func conflictCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.statusRaw == "needsReview" }
        ))) ?? 0
    }

    /// One flagged record, described well enough for a person to recognise it
    /// without opening anything. Crosses the actor boundary as a plain value,
    /// like every other thing that leaves this actor.
    struct ConflictSummary: Identifiable, Sendable, Equatable {
        var id: UUID
        var entity: SyncEntity
        var personName: String
        /// What the record is: the medication's name, the visit's reason.
        var title: String
        /// The local copy's own timestamp, which is the edit being held.
        var localUpdatedAt: Date
        /// The two versions in dispute, captured when the conflict was flagged
        /// (`OutboxEntry.localSummary`). Either may be empty for an entry
        /// written by an older build, or for a record with no useful one-line
        /// form, and the screen renders less rather than nothing.
        var localSummary: String = ""
        var remoteSummary: String = ""

        /// Whether either side was captured. An entry flagged by an older
        /// build has neither, and the screen falls back to what it always
        /// showed rather than printing two empty boxes.
        var hasVersions: Bool { !localSummary.isEmpty || !remoteSummary.isEmpty }

        var kindLabel: String {
            switch entity {
            case .person: return "Person"
            case .medication: return "Medication"
            case .doseLog: return "Dose"
            case .visit: return "Visit"
            case .vital: return "Reading"
            case .emergencyContact: return "Contact"
            case .provider: return "Provider"
            case .careEvent: return "Entry"
            case .careTask: return "Task"
            case .note: return "Note"
            case .bill: return "Bill"
            case .checkIn: return "Check-in"
            case .checkInSettings: return "Check-in settings"
            }
        }
    }

    /// Everything waiting on a human decision.
    ///
    /// The count was surfaced in Settings long before this existed, which meant
    /// the app could tell someone that a health record needed attention and
    /// then offer them no way to find it. A number with no destination is worse
    /// than silence: it is a worry with nothing to do about it.
    func conflicts() -> [ConflictSummary] {
        let entries = (try? modelContext.fetch(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.statusRaw == "needsReview" },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []

        return entries.compactMap { entry in
            let id = entry.entityID
            switch entry.entityType {
            case .medication:
                guard let row = fetchOne(Medication.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.displayName, person: row.person, updatedAt: row.updatedAt)
            case .person:
                guard let row = fetchOne(Person.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.displayLabel, person: row, updatedAt: row.updatedAt)
            case .visit:
                guard let row = fetchOne(Visit.self, #Predicate { $0.id == id }) else { return nil }
                let name = row.reason.isEmpty ? row.resolvedProviderName : row.reason
                return summary(entry, title: name.isEmpty ? "Visit" : name, person: row.person, updatedAt: row.updatedAt)
            case .vital:
                guard let row = fetchOne(VitalReading.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: "\(row.kind.label) \(row.displayValue)", person: row.person, updatedAt: row.updatedAt)
            case .emergencyContact:
                guard let row = fetchOne(EmergencyContact.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.name, person: row.person, updatedAt: row.updatedAt)
            case .provider:
                guard let row = fetchOne(Provider.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.name, person: row.person, updatedAt: row.updatedAt)
            case .careEvent:
                guard let row = fetchOne(CareEvent.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.kind.label, person: row.person, updatedAt: row.updatedAt)
            case .careTask:
                guard let row = fetchOne(CareTask.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.title, person: row.person, updatedAt: row.updatedAt)
            case .note:
                guard let row = fetchOne(CareNote.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.displayTitle, person: row.person, updatedAt: row.updatedAt)
            case .bill:
                guard let row = fetchOne(Bill.self, #Predicate { $0.id == id }) else { return nil }
                return summary(entry, title: row.payee, person: row.person, updatedAt: row.updatedAt)
            case .doseLog, .checkIn, .checkInSettings:
                // None of these three can reach `needsReview`: doses and
                // check-ins are events that collapse rather than conflict, and
                // settings are last-writer-wins. Listed for exhaustiveness.
                return nil
            }
        }
    }

    private func summary(
        _ entry: OutboxEntry,
        title: String,
        person: Person?,
        updatedAt: Date
    ) -> ConflictSummary {
        ConflictSummary(
            id: entry.entityID,
            entity: entry.entityType,
            personName: person?.displayLabel ?? "",
            title: title.isEmpty ? entry.entityType.rawValue : title,
            localUpdatedAt: updatedAt,
            localSummary: entry.localSummary,
            remoteSummary: entry.remoteSummary
        )
    }

    /// Send this device's version. The local row is already the one on screen
    /// and already dirty, so this only puts the queued write back in the queue.
    func resolveKeepingLocal(id: UUID) {
        guard let entry = outboxEntry(for: id) else { return }
        entry.status = .pending
        entry.attempts = 0
        entry.notBefore = Date()
        entry.lastError = ""
        try? modelContext.save()
    }

    /// Take the family's version instead.
    ///
    /// The server's copy is not held anywhere locally (the conflict rule keeps
    /// the local one and refuses to overwrite it), so this cannot simply swap
    /// two values in memory. It drops the queued write, marks the row clean so
    /// nothing re-sends it, and rewinds that table's pull cursor to just before
    /// this row's timestamp so the next sync fetches the server copy and writes
    /// it in through the ordinary path. Rewinding re-applies a handful of rows
    /// that were already applied, which is free: every apply is an upsert.
    func resolveTakingRemote(id: UUID) {
        guard let entry = outboxEntry(for: id) else { return }
        let entity = entry.entityType

        var localUpdatedAt: Date?
        switch entity {
        case .person: localUpdatedAt = clearDirty(fetchOne(Person.self, #Predicate { $0.id == id }))
        case .medication: localUpdatedAt = clearDirty(fetchOne(Medication.self, #Predicate { $0.id == id }))
        case .visit: localUpdatedAt = clearDirty(fetchOne(Visit.self, #Predicate { $0.id == id }))
        case .vital: localUpdatedAt = clearDirty(fetchOne(VitalReading.self, #Predicate { $0.id == id }))
        case .emergencyContact: localUpdatedAt = clearDirty(fetchOne(EmergencyContact.self, #Predicate { $0.id == id }))
        case .provider: localUpdatedAt = clearDirty(fetchOne(Provider.self, #Predicate { $0.id == id }))
        case .careEvent: localUpdatedAt = clearDirty(fetchOne(CareEvent.self, #Predicate { $0.id == id }))
        case .careTask: localUpdatedAt = clearDirty(fetchOne(CareTask.self, #Predicate { $0.id == id }))
        case .note: localUpdatedAt = clearDirty(fetchOne(CareNote.self, #Predicate { $0.id == id }))
        case .bill: localUpdatedAt = clearDirty(fetchOne(Bill.self, #Predicate { $0.id == id }))
        case .doseLog, .checkIn, .checkInSettings: localUpdatedAt = nil
        }

        modelContext.delete(entry)

        // A second before the local edit, so the row is certain to be inside
        // the window the next pull asks for.
        if let localUpdatedAt {
            setCursor(entity: entity, page: SyncPage(updatedAt: localUpdatedAt.addingTimeInterval(-1), id: id))
        }
        try? modelContext.save()
    }

    private func clearDirty<T: PersistentModel & SyncableRecord>(_ record: T?) -> Date? {
        guard let record else { return nil }
        record.isDirty = false
        return record.updatedAt
    }

    private func outboxEntry(for entityID: UUID) -> OutboxEntry? {
        (try? modelContext.fetch(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.entityID == entityID && $0.statusRaw == "needsReview" }
        )))?.first
    }

    /// Flags the row and, crucially, keeps both readings of it.
    ///
    /// `local` and `remote` are captured here because this is the only moment
    /// they both exist on the device: the pull keeps the local row and drops
    /// the incoming one, so a screen asking about this later has nothing to
    /// show. Empty strings are accepted (a record type with no useful one-line
    /// version, or an older entry) and the screen simply says less.
    private func flagConflict(
        entity: SyncEntity,
        id: UUID,
        local: String = "",
        remote: String = ""
    ) {
        let existing = (try? modelContext.fetch(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.entityID == id }
        ))) ?? []
        let entry = existing.first ?? {
            let new = OutboxEntry(entityType: entity, entityID: id, groupID: nil)
            modelContext.insert(new)
            return new
        }()
        entry.status = .needsReview
        entry.lastError = "Someone else changed this while you were offline."
        // Never overwritten with nothing: a second pull of the same row must
        // not erase the description the first one managed to capture.
        if !local.isEmpty { entry.localSummary = local }
        if !remote.isEmpty { entry.remoteSummary = remote }
    }

    // MARK: Conflict descriptions

    /// One line describing a medication, from whichever side. Strength and
    /// schedule, because those are what two people disagree about and what the
    /// choice actually costs if it goes the wrong way.
    private static func describe(_ medication: Medication) -> String {
        var parts = [medication.displayName]
        if medication.isAsNeeded {
            parts.append("as needed")
        } else if !medication.scheduleLabel.isEmpty {
            parts.append(medication.scheduleLabel)
        }
        if !medication.instructions.isEmpty { parts.append(medication.instructions) }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ dto: MedicationDTO) -> String {
        let name = dto.strength.isEmpty ? dto.name : "\(dto.name) \(dto.strength)"
        var parts = [name]
        if dto.is_as_needed {
            parts.append("as needed")
        } else if !dto.schedule_minutes.isEmpty {
            let times = dto.schedule_minutes.sorted()
                .map { ScheduleEngine.timeLabel(forMinutes: $0) }
                .joined(separator: ", ")
            let days = ScheduleEngine.weekdayLabel(for: dto.weekdays)
            parts.append(days.isEmpty ? times : "\(days) · \(times)")
        }
        if !dto.instructions.isEmpty { parts.append(dto.instructions) }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ task: CareTask) -> String {
        var parts = [task.title.isEmpty ? "Untitled task" : task.title]
        if let dueAt = task.dueAt {
            parts.append("due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
        }
        if !task.assigneeName.isEmpty { parts.append(task.assigneeName) }
        if task.completedAt != nil { parts.append("done") }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ dto: CareTaskDTO) -> String {
        var parts = [dto.title.isEmpty ? "Untitled task" : dto.title]
        if let dueAt = dto.due_at {
            parts.append("due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
        }
        if !dto.assignee_name.isEmpty { parts.append(dto.assignee_name) }
        if dto.completed_at != nil { parts.append("done") }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ bill: Bill) -> String {
        var parts = [bill.payee.isEmpty ? "Untitled bill" : bill.payee, bill.amountLabel]
        if let dueAt = bill.dueAt {
            parts.append("due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
        }
        if bill.paidAt != nil { parts.append("paid") }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ dto: BillDTO) -> String {
        let amount = dto.amount.formatted(
            .currency(code: Locale.current.currency?.identifier ?? "USD")
        )
        var parts = [dto.payee.isEmpty ? "Untitled bill" : dto.payee, amount]
        if let dueAt = dto.due_at {
            parts.append("due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
        }
        if dto.paid_at != nil { parts.append("paid") }
        return parts.joined(separator: " · ")
    }

    /// A note is one field end to end, so the field itself is the description.
    /// Trimmed, because the whole point is a line somebody can compare at a
    /// glance rather than two walls of text.
    private static func describe(_ body: String) -> String {
        let flat = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > 140 else { return flat }
        return String(flat.prefix(140)) + "…"
    }

    // MARK: - Cursors

    func cursorPage(for entity: SyncEntity) -> SyncPage? {
        guard let cursor = cursor(for: entity),
              let updatedAt = cursor.lastUpdatedAt,
              let id = cursor.lastID else { return nil }
        return SyncPage(updatedAt: updatedAt, id: id)
    }

    func setCursor(entity: SyncEntity, page: SyncPage?) {
        let record = cursor(for: entity) ?? {
            let new = SyncCursor(entityType: entity)
            modelContext.insert(new)
            return new
        }()
        record.lastUpdatedAt = page?.updatedAt
        record.lastID = page?.id
        record.lastSyncedAt = Date()
    }

    private func cursor(for entity: SyncEntity) -> SyncCursor? {
        let raw = entity.rawValue
        return (try? modelContext.fetch(FetchDescriptor<SyncCursor>(
            predicate: #Predicate { $0.entityTypeRaw == raw }
        )))?.first
    }

    // MARK: - Helpers

    private func fetchOne<T: PersistentModel>(
        _ type: T.Type,
        _ predicate: Predicate<T>
    ) -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
