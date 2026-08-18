import Foundation
import SwiftData

// MARK: - Person

/// Someone whose care is tracked. The app is multi-person from the first screen:
/// a user typically has "Mom", "Dad", and themselves.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    /// Free text so users can write "Mom", "Dad", "Me", "Aunt Rose".
    var relationship: String = ""
    var birthDate: Date?
    var bloodType: String = ""
    /// Index into `AppTheme.personColors`, so each person reads as one color everywhere.
    var colorIndex: Int = 0
    var isSelf: Bool = false
    /// Set when this person has their own account and can press their own
    /// check-in button. Nil for someone tracked without a phone.
    var linkedUserID: UUID?
    var allergies: [String] = []
    var conditions: [String] = []
    var notes: String = ""
    var createdAt: Date = Date()
    /// Set when a caregiver added someone who will never use the app themselves
    /// and said plainly that the decision was theirs to make (D28). Recorded
    /// because it is a surrogate decision, not the recipient's own consent.
    var surrogateAttestedAt: Date?

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \Medication.person)
    var medications: [Medication] = []

    @Relationship(deleteRule: .cascade, inverse: \Visit.person)
    var visits: [Visit] = []

    @Relationship(deleteRule: .cascade, inverse: \VitalReading.person)
    var vitals: [VitalReading] = []

    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.person)
    var contacts: [EmergencyContact] = []

    @Relationship(deleteRule: .cascade, inverse: \Provider.person)
    var providers: [Provider] = []

    @Relationship(deleteRule: .cascade, inverse: \CareEvent.person)
    var careEvents: [CareEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \CareTask.person)
    var tasks: [CareTask] = []

    /// Not `notes`: that name is already taken above by the person's own
    /// one-line note, which predates this and is a different thing.
    @Relationship(deleteRule: .cascade, inverse: \CareNote.person)
    var savedNotes: [CareNote] = []

    @Relationship(deleteRule: .cascade, inverse: \Bill.person)
    var bills: [Bill] = []

    init(
        name: String,
        relationship: String = "",
        birthDate: Date? = nil,
        colorIndex: Int = 0,
        isSelf: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.relationship = relationship
        self.birthDate = birthDate
        self.colorIndex = colorIndex
        self.isSelf = isSelf
        self.createdAt = Date()
    }

    // MARK: Live rows
    // A tombstoned row stays in the local store until the outbox has pushed it
    // (see `SyncableRecord.tombstone`), so every read path goes through one of
    // these rather than the raw relationship. Reading the relationship directly
    // shows the family a medication that was deleted minutes ago.

    var liveMedications: [Medication] {
        medications.filter { $0.deletedAt == nil }
    }

    var liveVisits: [Visit] {
        visits.filter { $0.deletedAt == nil }
    }

    var liveVitals: [VitalReading] {
        vitals.filter { $0.deletedAt == nil }
    }

    var liveContacts: [EmergencyContact] {
        contacts.filter { $0.deletedAt == nil }
    }

    var liveProviders: [Provider] {
        providers.filter { $0.deletedAt == nil }
    }

    var liveCareEvents: [CareEvent] {
        careEvents.filter { $0.deletedAt == nil }
    }

    var liveTasks: [CareTask] {
        tasks.filter { $0.deletedAt == nil }
    }

    var openTasks: [CareTask] {
        liveTasks.filter { !$0.isDone }
    }

    var liveNotes: [CareNote] {
        CareNote.sorted(savedNotes.filter { $0.deletedAt == nil })
    }

    var liveBills: [Bill] {
        bills.filter { $0.deletedAt == nil }
    }

    var openBills: [Bill] {
        liveBills.filter { !$0.isPaid }
    }

    var activeMedications: [Medication] {
        liveMedications.filter(\.isActive).sorted { $0.name < $1.name }
    }

    /// The name they were entered under, everywhere.
    ///
    /// This used to return the relationship whenever one was set, which meant a
    /// record entered as "Eleanor" was titled "Mom" on Today and on the person
    /// hub while the Care row and the emergency card said "Eleanor". Two labels
    /// for one row is not a naming preference in an app someone opens in an ER:
    /// the reader cannot tell whether they are looking at the record they
    /// meant to open. It also produced "Me's care record" on the solo path.
    /// The relationship is still shown, as the subtitle it always was.
    var displayLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return relationship.isEmpty ? "This person" : relationship
    }

    var age: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }
}

// MARK: - Medication

enum MedicationForm: String, CaseIterable, Identifiable, Sendable {
    case tablet, capsule, liquid, injection, inhaler, patch, cream, drops, other

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    /// "10 mg", "500 mcg" — kept as text because labels vary wildly.
    var strength: String = ""
    var formRaw: String = MedicationForm.tablet.rawValue
    /// What it is for, in plain language. Shown on the emergency card.
    var purpose: String = ""
    var prescriber: String = ""
    var pharmacy: String = ""
    /// "Take with food", "Do not crush".
    var instructions: String = ""
    /// Scheduled times as minutes from midnight, so the schedule survives time-zone changes.
    var scheduleMinutes: [Int] = []
    /// Weekday numbers (1 = Sunday, matching `Calendar`). Empty means every day.
    var weekdays: [Int] = []
    var isAsNeeded: Bool = false
    var isActive: Bool = true
    var startDate: Date = Date()
    var endDate: Date?
    var labelPhoto: Data?
    var createdAt: Date = Date()

    // MARK: Refills
    /// Whether this medication counts its supply at all.
    ///
    /// A flag of its own, because `quantityRemaining == 0` used to carry both
    /// meanings and the collision broke the feature at the only moment it
    /// mattered. Taking the last dose clamped the count to zero, zero read as
    /// "not tracked", and so the medication that had just run out dropped out
    /// of Running low, showed the refill toggle as off in its editor, and could
    /// not have the dose undone. Empty is now a state this app can represent
    /// (migration 0016).
    var tracksRefills: Bool = false
    /// On hand, in whatever unit `unitsPerDose` counts. Meaningless unless
    /// `tracksRefills`; zero while tracking means the supply is out.
    var quantityRemaining: Double = 0
    /// A dose is not always one tablet: half a tablet, two capsules, one dose
    /// of liquid.
    var unitsPerDose: Double = 1
    /// Days of supply left before we warn that a refill is due.
    var refillThresholdDays: Int = 7
    var lastFilledAt: Date?

    // MARK: Providers
    /// Links to a `Provider` row (plan82 slice C). Nil on every record entered
    /// before providers existed and on any new one where the user just typed a
    /// name instead. The free-text `prescriber` above is never cleared: there
    /// is no safe backfill, so old records keep displaying what they always
    /// displayed.
    var providerID: UUID?
    /// Same idea, pointed at a `Provider` with `isPharmacy == true`.
    var pharmacyID: UUID?

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.medication)
    var doses: [DoseLog] = []

    init(
        name: String,
        strength: String = "",
        form: MedicationForm = .tablet,
        purpose: String = "",
        person: Person? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.strength = strength
        self.formRaw = form.rawValue
        self.purpose = purpose
        self.person = person
        self.startDate = Date()
        self.createdAt = Date()
    }

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .other }
        set { formRaw = newValue.rawValue }
    }

    /// Same reasoning as `Person.liveMedications`: a tombstoned dose log sticks
    /// around until it has been pushed, and a deleted dose must not still count
    /// as the day's dose.
    var liveDoses: [DoseLog] {
        doses.filter { $0.deletedAt == nil }
    }

    /// "Lisinopril 10 mg" — the line that goes on a printed list.
    var displayName: String {
        strength.isEmpty ? name : "\(name) \(strength)"
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive, !isAsNeeded else { return false }
        if date < calendar.startOfDay(for: startDate) { return false }
        if let endDate, date > endDate { return false }
        guard !weekdays.isEmpty else { return true }
        return weekdays.contains(calendar.component(.weekday, from: date))
    }

    /// Concrete dose times for a given day, in order.
    func doseTimes(on date: Date, calendar: Calendar = .current) -> [Date] {
        guard isScheduled(on: date, calendar: calendar) else { return [] }
        let startOfDay = calendar.startOfDay(for: date)
        return scheduleMinutes.sorted().compactMap {
            calendar.date(byAdding: .minute, value: $0, to: startOfDay)
        }
    }

    /// Average scheduled doses per day. Accounts for `weekdays`: a
    /// once-a-week medication does not spend a full day's worth of doses
    /// each day.
    private var dosesPerDay: Double {
        guard !scheduleMinutes.isEmpty else { return 0 }
        let timesPerDay = Double(scheduleMinutes.count)
        guard !weekdays.isEmpty else { return timesPerDay }
        return timesPerDay * Double(weekdays.count) / 7
    }

    /// How many days the current supply lasts at the scheduled dose rate.
    /// `nil` when refills are not tracked, when the medication is as-needed, or
    /// when there is no timed schedule to divide by. Zero, not nil, once a
    /// tracked medication is empty: that is the answer the caregiver needs.
    var daysRemaining: Double? {
        guard !isAsNeeded, tracksRefills, unitsPerDose > 0 else { return nil }
        let perDay = dosesPerDay
        guard perDay > 0 else { return nil }
        return max(0, quantityRemaining) / unitsPerDose / perDay
    }

    /// Tracked and nothing left. The state the old sentinel could not express.
    var isOutOfStock: Bool {
        tracksRefills && quantityRemaining <= 0
    }

    /// Subtracts one dose's worth of units from what's on hand, when refills
    /// are tracked. Call this only where a dose is logged for the first time
    /// on this device (`status == .taken`); a dose that arrives through sync
    /// already happened on the device that logged it, so decrementing again
    /// here would double-count a value that has already synced.
    func decrementForDoseTaken() {
        guard tracksRefills else { return }
        quantityRemaining = max(0, quantityRemaining - unitsPerDose)
    }

    /// Puts a dose back on hand when an already-logged `taken` is corrected to
    /// something else on this device, so a mistap does not permanently lose
    /// count. Same first-time-on-this-device rule as `decrementForDoseTaken`.
    ///
    /// This works at zero now. It used to refuse there, because zero meant
    /// "not tracked" and restoring would have switched tracking on for a
    /// medication that never had it. With `tracksRefills` carrying that fact,
    /// undoing the dose that emptied the bottle puts the tablet back.
    func restoreForDoseUntaken() {
        guard tracksRefills else { return }
        quantityRemaining = max(0, quantityRemaining) + unitsPerDose
    }

    /// The prescriber's name: the linked `Provider` if `providerID` resolves
    /// to one still on `person`, otherwise the legacy free-text `prescriber`.
    var resolvedPrescriberName: String {
        resolvedProvider(providerID)?.name ?? prescriber
    }

    /// Empty when there is no linked provider, or the linked provider has no
    /// phone on file. Never falls back to anything, because there is no phone
    /// number hiding in the legacy string to fall back to.
    var resolvedPrescriberPhone: String {
        resolvedProvider(providerID)?.phone ?? ""
    }

    var resolvedPharmacyName: String {
        resolvedProvider(pharmacyID)?.name ?? pharmacy
    }

    var resolvedPharmacyPhone: String {
        resolvedProvider(pharmacyID)?.phone ?? ""
    }

    private func resolvedProvider(_ id: UUID?) -> Provider? {
        guard let id else { return nil }
        return person?.providers.first { $0.id == id && $0.deletedAt == nil }
    }
}

// MARK: - Dose log

enum DoseStatus: String, CaseIterable, Sendable {
    case taken, skipped, missed

    var label: String {
        switch self {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .missed: return "Missed"
        }
    }
}

/// A record that a dose was dealt with. `recordedBy` matters here in a way it does not
/// in a single-user med app: an adult child marking a dose on a parent's behalf needs
/// the log to say who did it.
@Model
final class DoseLog {
    var id: UUID = UUID()
    var scheduledAt: Date = Date()
    var recordedAt: Date = Date()
    var statusRaw: String = DoseStatus.taken.rawValue
    var recordedBy: String = ""
    var note: String = ""

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var medication: Medication?

    init(
        scheduledAt: Date,
        status: DoseStatus = .taken,
        recordedBy: String = "",
        medication: Medication? = nil
    ) {
        self.id = medication.map { Self.deterministicID(medicationID: $0.id, scheduledAt: scheduledAt) }
            ?? UUID()
        self.scheduledAt = scheduledAt
        self.recordedAt = Date()
        self.statusRaw = status.rawValue
        self.recordedBy = recordedBy
        self.medication = medication
    }

    /// The one id in the app that is derived rather than random.
    ///
    /// Two family members marking the same 8am pill as taken is the likeliest
    /// concurrent action here, and D21 promises it collapses silently. With
    /// random ids it did the opposite: two rows, a `23505` against the server's
    /// `(medication_id, scheduled_at)` dedupe index, and a stuck outbox entry no
    /// user action could clear. Deriving the key from the same pair the index
    /// uses makes the second device's write an ordinary idempotent upsert, and
    /// collapses the duplicate locally too.
    ///
    /// Bucketed to the minute because that is the precision the schedule itself
    /// has: `Medication.doseTimes` builds slots on exact minute boundaries and
    /// `ScheduleEngine.slots` matches logs back to them at `.minute` granularity.
    /// Anything finer would let two devices that agree on the slot still disagree
    /// on the id, which is the bug this exists to close.
    static func deterministicID(medicationID: UUID, scheduledAt: Date) -> UUID {
        let minute = Int((scheduledAt.timeIntervalSince1970 / 60).rounded(.down))
        return DeterministicID.v5(
            namespace: doseLogNamespace,
            name: "\(medicationID.uuidString.lowercased()):\(minute)"
        )
    }

    /// Fixed for the life of the app. Changing it would re-key every dose log
    /// and split a family's history in two.
    private static let doseLogNamespace = UUID(uuidString: "6f1d5b3e-6a5e-4a2c-9f0b-2f7a1c9d4e88")!

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Visit

/// A doctor visit and what was actually said, which is the thing families forget
/// between appointments.
@Model
final class Visit {
    var id: UUID = UUID()
    var date: Date = Date()
    var provider: String = ""
    var specialty: String = ""
    var reason: String = ""
    var notes: String = ""
    var followUp: String = ""
    var nextAppointment: Date?
    var createdAt: Date = Date()

    // MARK: Providers
    /// Links to a `Provider` row (plan82 slice C). The free-text `provider`
    /// above is never cleared: old visits keep displaying what they always
    /// displayed.
    var providerID: UUID?

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        date: Date = Date(),
        provider: String = "",
        specialty: String = "",
        reason: String = "",
        person: Person? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.provider = provider
        self.specialty = specialty
        self.reason = reason
        self.person = person
        self.createdAt = Date()
    }

    /// The linked `Provider`'s name if `providerID` still resolves to one on
    /// `person`, otherwise the legacy free-text `provider`.
    var resolvedProviderName: String {
        guard let providerID,
              let match = person?.providers.first(where: { $0.id == providerID && $0.deletedAt == nil })
        else { return provider }
        return match.name
    }
}

// MARK: - Vitals

enum VitalKind: String, CaseIterable, Identifiable, Sendable {
    case bloodPressure, weight, glucose, heartRate, temperature, oxygen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bloodPressure: return "Blood Pressure"
        case .weight: return "Weight"
        case .glucose: return "Glucose"
        case .heartRate: return "Heart Rate"
        case .temperature: return "Temperature"
        case .oxygen: return "Oxygen"
        }
    }

    var unit: String {
        switch self {
        case .bloodPressure: return "mmHg"
        case .weight: return "lb"
        case .glucose: return "mg/dL"
        case .heartRate: return "bpm"
        case .temperature: return "°F"
        case .oxygen: return "%"
        }
    }

    /// Blood pressure is the only reading that needs a second number.
    var isPaired: Bool { self == .bloodPressure }

    var symbol: String {
        switch self {
        case .bloodPressure: return "heart.text.square"
        case .weight: return "scalemass"
        case .glucose: return "drop"
        case .heartRate: return "waveform.path.ecg"
        case .temperature: return "thermometer"
        case .oxygen: return "lungs"
        }
    }
}

@Model
final class VitalReading {
    var id: UUID = UUID()
    var kindRaw: String = VitalKind.bloodPressure.rawValue
    var primaryValue: Double = 0
    /// Diastolic, for blood pressure. Unused otherwise.
    var secondaryValue: Double?
    var recordedAt: Date = Date()
    var note: String = ""

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        kind: VitalKind,
        primaryValue: Double,
        secondaryValue: Double? = nil,
        recordedAt: Date = Date(),
        person: Person? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.recordedAt = recordedAt
        self.person = person
    }

    var kind: VitalKind {
        get { VitalKind(rawValue: kindRaw) ?? .bloodPressure }
        set { kindRaw = newValue.rawValue }
    }

    var displayValue: String {
        if kind.isPaired, let secondaryValue {
            return "\(Int(primaryValue))/\(Int(secondaryValue))"
        }
        if primaryValue == primaryValue.rounded() {
            return String(Int(primaryValue))
        }
        return String(format: "%.1f", primaryValue)
    }
}

// MARK: - Emergency contact

@Model
final class EmergencyContact {
    var id: UUID = UUID()
    var name: String = ""
    var relationship: String = ""
    var phone: String = ""
    var isPrimary: Bool = false

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        name: String,
        relationship: String = "",
        phone: String = "",
        isPrimary: Bool = false,
        person: Person? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.isPrimary = isPrimary
        self.person = person
    }
}

// MARK: - Provider

/// One row per doctor, specialist, dentist, pharmacy or therapist (plan82
/// slice C). Before this, `prescriber`, `pharmacy` and `Visit.provider` were
/// loose strings retyped on every record; this is the shape a paper list
/// actually has, with a phone number that goes on the emergency card.
@Model
final class Provider {
    var id: UUID = UUID()
    var name: String = ""
    var specialty: String = ""
    var phone: String = ""
    var address: String = ""
    /// A bookmark to the patient portal, nothing more. Never a username or
    /// password: that is the password vault, and it is refused (Appendix B).
    var portalURL: String = ""
    var notes: String = ""
    var isPharmacy: Bool = false

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        name: String,
        specialty: String = "",
        phone: String = "",
        address: String = "",
        portalURL: String = "",
        notes: String = "",
        isPharmacy: Bool = false,
        person: Person? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.specialty = specialty
        self.phone = phone
        self.address = address
        self.portalURL = portalURL
        self.notes = notes
        self.isPharmacy = isPharmacy
        self.person = person
    }

    /// Detaches this provider from every medication and visit that points at
    /// it, then tombstones it. A provider is a shortcut to a phone number; the
    /// medication or visit it was attached to is real data and must survive
    /// the provider going away (plan82 slice C).
    ///
    /// The detached medications and visits are queued too, not just marked
    /// dirty: a sibling's phone still holding the old `providerID` would
    /// otherwise keep resolving a provider this device deleted.
    @MainActor
    func detachAndTombstone(in context: ModelContext) {
        let providerID = id
        if let person {
            for medication in person.liveMedications {
                var touched = false
                if medication.providerID == providerID { medication.providerID = nil; touched = true }
                if medication.pharmacyID == providerID { medication.pharmacyID = nil; touched = true }
                if touched { medication.recordLocalChange(in: context) }
            }
            for visit in person.liveVisits where visit.providerID == providerID {
                visit.providerID = nil
                visit.recordLocalChange(in: context)
            }
        }
        tombstone(in: context)
    }
}

// MARK: - Care event

/// Falls, ER visits, hospital stays, symptoms, mood, appetite, sleep and pain
/// (plan82 slice D): one typed note entity instead of eight. A logged fall
/// notifies nobody automatically; it appears in the group's shared record like
/// every other row (I6).
enum CareEventKind: String, CaseIterable, Identifiable, Sendable {
    case fall, erVisit, hospitalStay, symptom, mood, appetite, sleep, pain, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fall: return "Fall"
        case .erVisit: return "ER Visit"
        case .hospitalStay: return "Hospital Stay"
        case .symptom: return "Symptom"
        case .mood: return "Mood"
        case .appetite: return "Appetite"
        case .sleep: return "Sleep"
        case .pain: return "Pain"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .fall: return "figure.fall"
        case .erVisit: return "cross.case"
        case .hospitalStay: return "bed.double"
        case .symptom: return "stethoscope"
        case .mood: return "face.smiling"
        case .appetite: return "fork.knife"
        case .sleep: return "moon.zzz"
        case .pain: return "bandage"
        case .other: return "note.text"
        }
    }
}

@Model
final class CareEvent {
    var id: UUID = UUID()
    var kindRaw: String = CareEventKind.symptom.rawValue
    var occurredAt: Date = Date()
    /// 0 means unset, not that severity was recorded as zero. Never charted,
    /// never trended: a number a human typed, nothing inferred from it.
    var severity: Int = 0
    var note: String = ""
    /// Matters more here than anywhere else in the app: "Sarah logged a fall
    /// on Tuesday" is the sentence the family needs. Populated the same way
    /// `DoseLog.recordedBy` is.
    var recordedBy: String = ""

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        kind: CareEventKind,
        occurredAt: Date = Date(),
        severity: Int = 0,
        note: String = "",
        recordedBy: String = "",
        person: Person? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.occurredAt = occurredAt
        self.severity = severity
        self.note = note
        self.recordedBy = recordedBy
        self.person = person
    }

    var kind: CareEventKind {
        get { CareEventKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// Groups events by calendar month in the given time zone, newest month
    /// first, newest event first within a month. Pulled out of the view so
    /// the device-time-zone behavior is testable without SwiftUI.
    static func groupedByMonth(
        _ events: [CareEvent],
        calendar: Calendar = .current
    ) -> [(month: Date, events: [CareEvent])] {
        let grouped = Dictionary(grouping: events) { event in
            calendar.date(from: calendar.dateComponents([.year, .month], from: event.occurredAt))
                ?? event.occurredAt
        }
        return grouped.keys.sorted(by: >).map { month in
            (month: month, events: grouped[month]!.sorted { $0.occurredAt > $1.occurredAt })
        }
    }
}

// MARK: - Care task

/// Named `CareTaskPriority` rather than `TaskPriority` because that name is
/// already taken by Swift concurrency, and shadowing it here would make every
/// `Task(priority:)` in the app ambiguous.
enum CareTaskPriority: String, CaseIterable, Identifiable, Sendable {
    case low, normal, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    /// Ascending, so a plain sort puts the high-priority row first.
    var sortWeight: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

/// How often a task comes round.
///
/// `quarterly` and `halfYearly` are here because most of what a family actually
/// repeats sits between a month and a year: reorder hearing aids, book the
/// audiologist, review the repeat prescription, change the water filter. With
/// only monthly and yearly on offer the choice was between dismissing a
/// reminder five times and missing it once, and both of those teach people to
/// stop trusting the list. The periods deliberately match `BillRecurrence`,
/// which had them from the start.
///
/// Adding cases is safe: `recurrenceRaw` is a string in a column that already
/// exists, so nothing here needs a migration, and an older client reading a
/// value it does not know falls back to `never` rather than crashing.
enum CareTaskRecurrence: String, CaseIterable, Identifiable, Sendable {
    /// Spelled `never` rather than `none` so it never collides with
    /// `Optional.none` in a picker tagged with an optional.
    case never, daily, weekly, monthly, quarterly, halfYearly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Doesn't repeat"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .quarterly: return "Every 3 months"
        case .halfYearly: return "Every 6 months"
        case .yearly: return "Every year"
        }
    }

    /// Short form for a list row, where the title and the due date already have
    /// the line's attention. Lowercasing `label` produced "every 3 months",
    /// which is longer than the task title it was sitting under.
    var shortLabel: String {
        switch self {
        case .never: return "one-off"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .halfYearly: return "twice a year"
        case .yearly: return "yearly"
        }
    }

    /// The `DateComponents` step used to find the next occurrence. Calendar
    /// arithmetic, not a fixed number of seconds, so a monthly refill lands on
    /// the same day of the month and a daily task survives a DST change.
    var step: DateComponents? {
        switch self {
        case .never: return nil
        case .daily: return DateComponents(day: 1)
        case .weekly: return DateComponents(day: 7)
        case .monthly: return DateComponents(month: 1)
        case .quarterly: return DateComponents(month: 3)
        case .halfYearly: return DateComponents(month: 6)
        case .yearly: return DateComponents(year: 1)
        }
    }
}

/// A shared to-do against one care recipient: refill a prescription, book the
/// audiologist, pay the long-term-care premium, replace hearing-aid batteries.
///
/// This is the one entity that exists because the family is a group rather than
/// a person. "Who is doing this, and did anyone do it yet" is the question a
/// spreadsheet answers badly and a text thread answers worse, and it is the
/// reason `assigneeName` and `completedByName` are carried the same way
/// `DoseLog.recordedBy` is.
///
/// I6: a task is a note a human wrote and a human ticks off. Nothing here
/// escalates, notifies the family automatically, or infers anything from a task
/// going overdue.
@Model
final class CareTask {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// Optional on purpose. Most of what a caregiver writes down is "at some
    /// point", and forcing a date on it turns the list into a wall of things
    /// that are technically late.
    var dueAt: Date?
    var priorityRaw: String = CareTaskPriority.normal.rawValue
    var recurrenceRaw: String = CareTaskRecurrence.never.rawValue
    /// Set when the assignee was picked from the loaded member list. Nil when
    /// the name was typed, which is the offline case and has to keep working.
    var assigneeUserID: UUID?
    var assigneeName: String = ""
    var completedAt: Date?
    var completedByName: String = ""
    var createdByName: String = ""
    var createdAt: Date = Date()

    // MARK: Sync
    // Client-generated UUIDs above are also the server primary keys, which is
    // what makes every push, every retry and the one-time adoption of a
    // local-only install idempotent through `on conflict (id) do update`.
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        title: String,
        notes: String = "",
        dueAt: Date? = nil,
        priority: CareTaskPriority = .normal,
        recurrence: CareTaskRecurrence = .never,
        assigneeName: String = "",
        createdByName: String = "",
        person: Person? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.priorityRaw = priority.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.assigneeName = assigneeName
        self.createdByName = createdByName
        self.person = person
        self.createdAt = Date()
    }

    var priority: CareTaskPriority {
        get { CareTaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var recurrence: CareTaskRecurrence {
        get { CareTaskRecurrence(rawValue: recurrenceRaw) ?? .never }
        set { recurrenceRaw = newValue.rawValue }
    }

    var isDone: Bool { completedAt != nil }

    /// Ticks the task off and, for a repeating one, queues the next occurrence
    /// as a **new row** rather than moving the due date on this one.
    ///
    /// The completed row is the history the family came for ("did anyone pay
    /// the premium in March?"), and mutating it in place would erase exactly
    /// that. Returns the follow-up so a caller can scroll to it; nil when the
    /// task does not repeat.
    @MainActor
    @discardableResult
    func markComplete(by name: String, at date: Date = Date(), in context: ModelContext) -> CareTask? {
        completedAt = date
        completedByName = name
        recordLocalChange(in: context)

        guard recurrence != .never else { return nil }
        guard let nextDue = TaskPlanner.nextDueDate(
            after: dueAt ?? date,
            recurrence: recurrence,
            notBefore: date
        ) else { return nil }

        let followUp = CareTask(
            title: title,
            notes: notes,
            dueAt: nextDue,
            priority: priority,
            recurrence: recurrence,
            assigneeName: assigneeName,
            createdByName: createdByName,
            person: person
        )
        followUp.assigneeUserID = assigneeUserID
        followUp.groupID = groupID
        context.insert(followUp)
        followUp.recordLocalChange(in: context)
        return followUp
    }

    /// Reopens a task ticked off by mistake. Deliberately does not chase down
    /// and remove the follow-up occurrence it spawned: deleting a row the
    /// family may already have edited to undo a mistap is the more surprising
    /// of the two behaviors.
    @MainActor
    func markIncomplete(in context: ModelContext) {
        completedAt = nil
        completedByName = ""
        recordLocalChange(in: context)
    }
}

// MARK: - Care note

/// A free-form note kept against one person: whatever this family needs to have
/// written down that no other screen has a field for.
///
/// Deliberately unstructured, and deliberately not named after any one use. The
/// app cannot anticipate what a family needs to remember about a parent (the
/// gate code, the insurance policy number, which pharmacy line to press 2 on,
/// what the neurologist said to ask next time), and every attempt to guess adds
/// a field most people leave empty.
///
/// Two things this is not. It is not a credential vault: the body syncs to the
/// family exactly like a visit note does, with the same protection as the rest
/// of the record and no separate encryption, so nothing in the UI invites
/// passwords into it. And it is not part of the emergency card or the exported
/// one-pager, because a free-text field nobody has reviewed is the wrong thing
/// to hand a stranger in an ER.
@Model
final class CareNote {
    var id: UUID = UUID()
    /// What the note is, in a couple of words. Optional: a note with a body and
    /// no title is a perfectly ordinary thing to write, and the row falls back
    /// to the first line of the body.
    var title: String = ""
    var body: String = ""
    /// Pinned notes sort to the top of the list. The one affordance here that
    /// is not just "type something", because the whole point of a pile of notes
    /// is that two of them matter more than the other twenty.
    var isPinned: Bool = false
    var createdByName: String = ""
    var createdAt: Date = Date()

    // MARK: Sync
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        title: String = "",
        body: String = "",
        isPinned: Bool = false,
        createdByName: String = "",
        person: Person? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.isPinned = isPinned
        self.createdByName = createdByName
        self.person = person
        self.createdAt = Date()
    }

    /// The title, or the first line of the body when there is no title. A row
    /// that renders as a blank line is a note the family cannot find again.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "Untitled note" : firstLine
    }

    /// Empty when the body says nothing the title did not already say, so a
    /// one-line note does not render the same words twice.
    var previewBody: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == displayTitle ? "" : trimmed
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pinned first, then most recently edited. Sorting by edit rather than by
    /// creation is what makes the note someone touched this morning the one at
    /// the top when the family opens the screen.
    static func sorted(_ notes: [CareNote]) -> [CareNote] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

// MARK: - Bill

/// What kind of expense this is. Coarse on purpose: the point is to be able to
/// glance at a list and see what it is made of, not to do accounting.
enum BillCategory: String, CaseIterable, Identifiable, Sendable {
    case care, housing, utilities, insurance, medical, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .care: return "Care"
        case .housing: return "Housing"
        case .utilities: return "Utilities"
        case .insurance: return "Insurance"
        case .medical: return "Medical"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .care: return "figure.2.arms.open"
        case .housing: return "house"
        case .utilities: return "bolt"
        case .insurance: return "shield"
        case .medical: return "cross.case"
        case .other: return "square.grid.2x2"
        }
    }
}

/// How often a bill comes round.
///
/// Its own type rather than `CareTaskRecurrence` because the useful periods are
/// different: bills are quarterly and half-yearly far more often than they are
/// daily, and a daily bill is not a thing.
enum BillRecurrence: String, CaseIterable, Identifiable, Sendable {
    /// Spelled `never` rather than `none` so it never collides with
    /// `Optional.none` in a picker tagged with an optional.
    case never, weekly, monthly, quarterly, halfYearly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "One-off"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .quarterly: return "Every 3 months"
        case .halfYearly: return "Every 6 months"
        case .yearly: return "Every year"
        }
    }

    /// Short form for a list row, where the payee and the amount already have
    /// the line's attention.
    var shortLabel: String {
        switch self {
        case .never: return "one-off"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .halfYearly: return "twice a year"
        case .yearly: return "yearly"
        }
    }

    /// Calendar arithmetic, not a fixed number of seconds, so a monthly bill
    /// lands on the same day of the month and nothing drifts across a DST
    /// change. Same reasoning as `CareTaskRecurrence.step`.
    var step: DateComponents? {
        switch self {
        case .never: return nil
        case .weekly: return DateComponents(day: 7)
        case .monthly: return DateComponents(month: 1)
        case .quarterly: return DateComponents(month: 3)
        case .halfYearly: return DateComponents(month: 6)
        case .yearly: return DateComponents(year: 1)
        }
    }
}

/// A bill the family is looking after for one person: the care home invoice,
/// the electricity, the Medicare supplement, the property tax.
///
/// This exists because the alternative was a note, and a note cannot answer the
/// two questions a family actually asks: what is due, and did anyone pay it.
/// Modelled on `CareTask` deliberately, right down to marking one paid creating
/// a **new row** for the next period rather than moving the date on this one,
/// because "did we pay the March invoice" is the question the history is for.
///
/// Two boundaries, both structural rather than stylistic:
///
/// - **Not a credential store.** No field here is typed as an account number, a
///   login or a card, the editor says so at the point of entry, and the body
///   syncs as ordinary text under the same RLS as everything else. This is the
///   same rule `CareNote` carries (architecture §14) and it matters more here,
///   because a screen that says "Bills" is exactly where a family would
///   otherwise put the online banking password.
/// - **Not a payment mechanism.** Nothing here pays anything, tells anyone to
///   pay anything, or talks to a bank. `paidAt` is a record that a human says
///   they paid it, in the same way `DoseLog` is a record that a human says a
///   tablet was swallowed.
@Model
final class Bill {
    var id: UUID = UUID()
    /// Who gets paid. The identity of the row, so it is the one required field.
    var payee: String = ""
    /// Stored as a `Double` in a single currency, which is the device's. Bills
    /// are not converted, summed across currencies, or rounded for display
    /// anywhere that matters.
    var amount: Double = 0
    /// Free text, and deliberately not "account number". What belongs here is
    /// "the invoice covers the room, not the meals".
    var notes: String = ""
    var categoryRaw: String = BillCategory.other.rawValue
    var recurrenceRaw: String = BillRecurrence.monthly.rawValue
    /// Nil for a bill nobody has put a date on yet, the same way a task can be
    /// a "at some point" job. A bill with no date never reads as overdue.
    var dueAt: Date?
    /// Someone else already handles this one, so it is worth having on the list
    /// but is not a job. Autopay bills are never bucketed as overdue.
    var isAutoPay: Bool = false
    /// Set when a human says it was paid. Nil is the open state.
    var paidAt: Date?
    var paidByName: String = ""
    var createdByName: String = ""
    var createdAt: Date = Date()

    // MARK: Sync
    /// Nil until this row has been adopted into a family group.
    var groupID: UUID?
    /// Server-authoritative. Only the sync engine writes this.
    var updatedAt: Date = Date()
    /// Tombstone. Rows are never hard-deleted, so a delete on one device
    /// reaches the others instead of silently reappearing on the next pull.
    var deletedAt: Date?
    /// Has local work the server has not accepted yet.
    var isDirty: Bool = true

    var person: Person?

    init(
        payee: String,
        amount: Double = 0,
        notes: String = "",
        category: BillCategory = .other,
        recurrence: BillRecurrence = .monthly,
        dueAt: Date? = nil,
        isAutoPay: Bool = false,
        createdByName: String = "",
        person: Person? = nil
    ) {
        self.id = UUID()
        self.payee = payee
        self.amount = amount
        self.notes = notes
        self.categoryRaw = category.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.dueAt = dueAt
        self.isAutoPay = isAutoPay
        self.createdByName = createdByName
        self.person = person
        self.createdAt = Date()
    }

    var category: BillCategory {
        get { BillCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var recurrence: BillRecurrence {
        get { BillRecurrence(rawValue: recurrenceRaw) ?? .never }
        set { recurrenceRaw = newValue.rawValue }
    }

    var isPaid: Bool { paidAt != nil }

    /// The device's currency, formatted. Zero is shown as an amount rather than
    /// hidden: "we do not know what this one costs yet" is a normal state for a
    /// bill somebody has just written down.
    var amountLabel: String {
        amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    /// Marks it paid and, for a repeating bill, queues the next period as a
    /// **new row** rather than moving this one's date on.
    ///
    /// Exactly `CareTask.markComplete`'s reasoning: the paid row is the history
    /// the family came for, and mutating it in place would erase it. Returns
    /// the follow-up so a caller can point at it; nil when the bill is one-off.
    @MainActor
    @discardableResult
    func markPaid(by name: String, at date: Date = Date(), in context: ModelContext) -> Bill? {
        paidAt = date
        paidByName = name
        recordLocalChange(in: context)

        guard recurrence != .never else { return nil }
        guard let nextDue = BillPlanner.nextDueDate(
            after: dueAt ?? date,
            recurrence: recurrence,
            notBefore: date
        ) else { return nil }

        let followUp = Bill(
            payee: payee,
            amount: amount,
            notes: notes,
            category: category,
            recurrence: recurrence,
            dueAt: nextDue,
            isAutoPay: isAutoPay,
            createdByName: createdByName,
            person: person
        )
        context.insert(followUp)
        followUp.recordLocalChange(in: context)
        return followUp
    }

    /// Puts a bill back to unpaid. The recurring follow-up that marking it paid
    /// created is not cleaned up here: it may already have been edited or paid
    /// on another phone, and quietly deleting a sibling's row to undo your own
    /// mistap is worse than leaving a duplicate the family can see and remove.
    @MainActor
    func markUnpaid(in context: ModelContext) {
        paidAt = nil
        paidByName = ""
        recordLocalChange(in: context)
    }
}
