import Foundation

/// What this app can do for one person, and how much of it they have actually
/// set up.
///
/// The app shipped with every one of these behind an identically-styled grey
/// list row, and the first thing a real user said about it was that it was not
/// clear what the app could do. Discoverability is a product problem, so the
/// catalog is a value here rather than a layout detail scattered through the
/// views: the hub grid, the setup checklist and the Today quick actions all
/// read the same list, and a feature added in one place cannot go missing from
/// the other two.
///
/// Every string produced here is a statement of fact about what is recorded.
/// Nothing in this file may assess a person's health or imply the app knows
/// something a clinician would know (I6).
enum CareFeature: String, CaseIterable, Identifiable, Sendable {
    case medications
    case tasks
    case vitals
    case visits
    case providers
    case incidents
    case timeline
    case healthDetails
    case contacts
    case notes
    case bills
    case checkIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medications: return "Medications"
        case .tasks: return "Tasks"
        case .vitals: return "Vitals"
        case .visits: return "Visits"
        case .providers: return "Providers"
        case .incidents: return "Symptoms"
        case .timeline: return "Timeline"
        case .healthDetails: return "Health details"
        case .contacts: return "Contacts"
        case .notes: return "Notes"
        case .bills: return "Bills"
        case .checkIn: return "Daily check-in"
        }
    }

    var symbol: String {
        switch self {
        case .medications: return "pills.fill"
        case .tasks: return "checklist"
        case .vitals: return "heart.text.square.fill"
        case .visits: return "stethoscope"
        case .providers: return "list.bullet.clipboard.fill"
        case .incidents: return "note.text"
        case .timeline: return "clock.arrow.circlepath"
        case .healthDetails: return "cross.case.fill"
        case .contacts: return "phone.fill"
        case .notes: return "doc.text.fill"
        case .bills: return "dollarsign.circle.fill"
        case .checkIn: return "hand.wave.fill"
        }
    }

    /// One line saying what the feature is *for*. This is the part that was
    /// missing: a row reading "3 logged" tells someone who already knows what
    /// visits are that they have three, and tells everyone else nothing.
    var blurb: String {
        switch self {
        case .medications: return "Doses, times and refills"
        case .tasks: return "Shared to-dos for the family"
        case .vitals: return "Blood pressure, weight, glucose"
        case .visits: return "Notes from appointments"
        case .providers: return "Doctors and pharmacies"
        case .incidents: return "Falls, symptoms, bad days"
        case .timeline: return "Everything, in order"
        case .healthDetails: return "Allergies, conditions, blood type"
        case .contacts: return "Who to call first"
        case .notes: return "Anything else worth writing down"
        case .bills: return "What's due, and who paid it"
        case .checkIn: return "A daily tap that says they're OK"
        }
    }

    /// The short label used on the Today tab's action row and in its Medical
    /// menu.
    ///
    /// Verb-first inside the menu on purpose: "Symptoms" describes a filing
    /// cabinet, "Log a symptom" describes something you can do right now, and
    /// the latter is what makes a feature look like a feature. The chips in the
    /// open row are nouns instead, because sitting side by side they read as a
    /// set of places rather than as a list of chores.
    var quickActionTitle: String {
        switch self {
        case .medications: return "Meds"
        case .tasks: return "Tasks"
        case .vitals: return "Log vitals"
        case .visits: return "Visits"
        case .providers: return "Doctors"
        case .incidents: return "Log a symptom"
        case .timeline: return "History"
        case .healthDetails: return "Allergies"
        case .contacts: return "Contacts"
        case .notes: return "Notes"
        case .bills: return "Bills"
        case .checkIn: return "Check-in"
        }
    }

    /// The colour index into `AppTheme.featureColors`. Kept here so a feature's
    /// colour is the same on the hub tile, the Today chip and the checklist row.
    var colorIndex: Int {
        switch self {
        case .medications: return 0
        case .tasks: return 1
        case .vitals: return 2
        case .visits: return 3
        case .providers: return 4
        case .incidents: return 5
        case .timeline: return 6
        case .healthDetails: return 7
        case .contacts: return 8
        case .checkIn: return 9
        case .notes: return 10
        case .bills: return 11
        }
    }

    /// Order for the hub grid: what a caregiver reaches for daily comes first,
    /// reference material last.
    static let hubOrder: [CareFeature] = [
        .medications, .tasks, .bills, .vitals,
        .incidents, .visits, .providers, .healthDetails,
        .contacts, .notes, .checkIn, .timeline
    ]
}

// MARK: - Today's action row

/// One entry in the Today tab's action row: either a feature you tap straight
/// into, or a heading that opens a short menu of related ones.
///
/// Grouped after the first real user read the flat row: seven equally weighted
/// chips, three of them scrolled off the right edge and their labels colliding,
/// is a pile rather than a menu. What a caregiver touches on an ordinary day
/// stays in the open; the medical record they consult occasionally sits one tap
/// behind a word that says what it is.
enum QuickAction: Identifiable, Hashable, Sendable {
    case feature(CareFeature)
    /// Vitals, symptoms, doctors, allergies, history: the medical record, as
    /// opposed to today's chores.
    case medical

    /// The row, in the order a caregiver reaches for it. Read only by the Today
    /// tab; the hub grid still shows every feature flat, because that screen's
    /// job is to show the whole range at once.
    /// Six, and six is the ceiling: seven chips is what pushed three of them
    /// off the right edge and started this. Bills earns an open slot because it
    /// is a weekly errand; visits moved into the Medical menu, where the rest of
    /// the medical record already lives and where a write-up nobody does daily
    /// belongs.
    static let todayRow: [QuickAction] = [
        .feature(.medications),
        .feature(.tasks),
        .feature(.bills),
        .medical,
        .feature(.notes),
        .feature(.contacts)
    ]

    var id: String {
        switch self {
        case .feature(let feature): return feature.rawValue
        case .medical: return "medical"
        }
    }

    var title: String {
        switch self {
        case .feature(let feature): return feature.quickActionTitle
        case .medical: return "Medical"
        }
    }

    var symbol: String {
        switch self {
        case .feature(let feature): return feature.symbol
        case .medical: return "waveform.path.ecg"
        }
    }

    var colorIndex: Int {
        switch self {
        case .feature(let feature): return feature.colorIndex
        // Vitals' red. The menu is where vitals now lives, so the colour it
        // used to carry follows it rather than being retired.
        case .medical: return 2
        }
    }

    /// What the menu opens, in order. Empty for a chip that goes straight
    /// somewhere, which is what the Today tab uses to decide between a button
    /// and a menu.
    var members: [CareFeature] {
        switch self {
        case .feature: return []
        case .medical: return [.visits, .vitals, .incidents, .providers, .healthDetails, .timeline]
        }
    }
}

/// Counts and one-line states for a person's record.
///
/// Pure reads over the local store, exactly like `ScheduleEngine`. Nothing here
/// touches the network, so the hub renders instantly and identically offline
/// (I1).
enum CareOverview {

    /// What a hub tile shows under its title: how much is in there, or an
    /// invitation to put the first thing in.
    @MainActor
    static func detail(for feature: CareFeature, person: Person, now: Date = Date()) -> String {
        switch feature {
        case .medications:
            let count = person.activeMedications.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 medication" : "\(count) medications"

        case .tasks:
            let open = person.openTasks
            guard !open.isEmpty else { return "Nothing to do" }
            let due = TaskPlanner.dueNow(open, now: now).count
            guard due > 0 else { return "\(open.count) open" }
            return "\(open.count) open · \(due) due"

        case .vitals:
            let count = person.liveVitals.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 reading" : "\(count) readings"

        case .visits:
            let count = person.liveVisits.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 visit" : "\(count) visits"

        case .providers:
            let count = person.liveProviders.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 saved" : "\(count) saved"

        case .incidents:
            let count = person.liveCareEvents.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 entry" : "\(count) entries"

        case .timeline:
            return "View history"

        case .healthDetails:
            let parts = [
                pluralized(person.allergies.count, "allergy", "allergies"),
                pluralized(person.conditions.count, "condition", "conditions"),
                person.bloodType.isEmpty ? nil : "blood type"
            ].compactMap { $0 }
            return parts.isEmpty ? "None yet" : parts.joined(separator: ", ")

        case .contacts:
            let count = person.liveContacts.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 contact" : "\(count) contacts"

        case .notes:
            let count = person.liveNotes.count
            guard count > 0 else { return "None yet" }
            return count == 1 ? "1 note" : "\(count) notes"

        case .bills:
            // "None yet" for a tile nothing has been put in, matching every
            // other tile. "Nothing due" is a different fact and belongs to a
            // list that has bills in it, all of them paid.
            let bills = person.liveBills
            guard !bills.isEmpty else { return "None yet" }
            return BillPlanner.summaryLine(bills, now: now)

        case .checkIn:
            return "Set it up"
        }
    }

    /// True when the feature holds nothing at all, which is what a tile uses to
    /// decide whether to read as a record or as an invitation.
    @MainActor
    static func isEmpty(_ feature: CareFeature, person: Person) -> Bool {
        switch feature {
        case .medications: return person.activeMedications.isEmpty
        case .tasks: return person.openTasks.isEmpty
        case .vitals: return person.liveVitals.isEmpty
        case .visits: return person.liveVisits.isEmpty
        case .providers: return person.liveProviders.isEmpty
        case .incidents: return person.liveCareEvents.isEmpty
        case .healthDetails:
            return person.allergies.isEmpty && person.conditions.isEmpty && person.bloodType.isEmpty
        case .contacts: return person.liveContacts.isEmpty
        case .notes: return person.liveNotes.isEmpty
        case .bills: return person.liveBills.isEmpty
        case .timeline, .checkIn: return false
        }
    }

    private static func pluralized(_ n: Int, _ singular: String, _ plural: String) -> String? {
        guard n > 0 else { return nil }
        return "\(n) \(n == 1 ? singular : plural)"
    }
}

// MARK: - Setup checklist

/// One thing worth doing once, and whether it has been done.
struct SetupStep: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case addMedication
        case doseReminders
        case healthDetails
        case emergencyContact
        case inviteFamily
        case checkIn
    }

    let kind: Kind
    let title: String
    /// Why it is worth doing. The reason is the whole point of the row; without
    /// it this is a chore list.
    let detail: String
    let symbol: String
    let isDone: Bool

    var id: String { kind.rawValue }
}

/// The "you have set up 3 of 6" list.
///
/// Deliberately a checklist of *setup*, not of care. It never nags about a
/// missed dose and it never implies anything about how someone is doing: the
/// only claim it makes is about what this app has been told.
enum SetupChecklist {

    /// - Parameters:
    ///   - remindersEnabled: read from `DoseReminderPreferences` by the caller,
    ///     which keeps this function free of `UserDefaults` and testable.
    ///   - hasSharedWithFamily: somebody other than this device's owner is in
    ///     the circle, or an invitation is outstanding. Deliberately not "is in
    ///     a group": creating a circle during onboarding satisfies that
    ///     instantly, which ticked this step for an owner who was still the
    ///     only member and told them family sharing was done.
    ///   - hasCheckIn: a daily check-in is configured for this person.
    @MainActor
    static func steps(
        for person: Person,
        remindersEnabled: Bool,
        hasSharedWithFamily: Bool,
        hasCheckIn: Bool
    ) -> [SetupStep] {
        [
            SetupStep(
                kind: .addMedication,
                title: "Add a medication",
                detail: "Times, strength and what it's for",
                symbol: "pills.fill",
                isDone: !person.activeMedications.isEmpty
            ),
            SetupStep(
                kind: .doseReminders,
                title: "Turn on dose reminders",
                detail: "This phone buzzes at each dose time",
                symbol: "bell.badge.fill",
                isDone: remindersEnabled
            ),
            SetupStep(
                kind: .healthDetails,
                title: "Add allergies and conditions",
                detail: "They print on the emergency card",
                symbol: "cross.case.fill",
                isDone: !person.allergies.isEmpty || !person.conditions.isEmpty
            ),
            SetupStep(
                kind: .emergencyContact,
                title: "Add an emergency contact",
                detail: "Who to call first, one tap away",
                symbol: "phone.fill",
                isDone: !person.liveContacts.isEmpty
            ),
            SetupStep(
                kind: .inviteFamily,
                title: "Invite the family",
                detail: "Siblings see the same list, free",
                symbol: "person.2.fill",
                isDone: hasSharedWithFamily
            ),
            SetupStep(
                kind: .checkIn,
                title: "Set up a daily check-in",
                detail: "One tap from them, so you know",
                symbol: "hand.wave.fill",
                isDone: hasCheckIn
            )
        ]
    }

    static func completed(_ steps: [SetupStep]) -> Int {
        steps.filter(\.isDone).count
    }

    /// The card hides itself once everything is done, rather than sitting there
    /// as a permanent green tick nobody needs.
    static func isFinished(_ steps: [SetupStep]) -> Bool {
        !steps.isEmpty && steps.allSatisfy(\.isDone)
    }

    /// The steps still worth showing: everything the user has not waved away.
    ///
    /// Dismissing is per step rather than per card because the reasons are per
    /// step. "I am the only one looking after him, stop asking me to invite a
    /// sibling" is a sensible thing to say about one row and a terrible reason
    /// to lose the other five.
    static func visible(_ steps: [SetupStep], dismissed: Set<SetupStep.Kind>) -> [SetupStep] {
        steps.filter { !dismissed.contains($0.kind) }
    }
}

/// Which setup steps a person has waved away, per care recipient.
///
/// Stored per (person, step) rather than as one flag so that dismissing the
/// invite-a-sibling row does not also silence "add an emergency contact".
/// `SetupCardPreferences` above still exists for the whole-card Hide, which is
/// the "not now, any of it" answer.
enum SetupStepPreferences {
    private static let prefix = "setup-step-dismissed."

    private static func key(_ personID: UUID) -> String {
        prefix + personID.uuidString
    }

    static func dismissed(personID: UUID, defaults: UserDefaults = .standard) -> Set<SetupStep.Kind> {
        let raw = defaults.stringArray(forKey: key(personID)) ?? []
        return Set(raw.compactMap(SetupStep.Kind.init(rawValue:)))
    }

    static func dismiss(_ kind: SetupStep.Kind, personID: UUID, defaults: UserDefaults = .standard) {
        var current = dismissed(personID: personID, defaults: defaults)
        current.insert(kind)
        defaults.set(current.map(\.rawValue).sorted(), forKey: key(personID))
    }

    static func restore(_ kind: SetupStep.Kind, personID: UUID, defaults: UserDefaults = .standard) {
        var current = dismissed(personID: personID, defaults: defaults)
        current.remove(kind)
        defaults.set(current.map(\.rawValue).sorted(), forKey: key(personID))
    }

    /// Used by "Set up again" in Settings, which has to be able to undo every
    /// dismissal or it is not a way back into setup.
    static func restoreAll(personID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(personID))
    }
}

/// Whether someone has told the setup card to go away, per person.
///
/// Dismissible on purpose. A caregiver who is never going to invite a sibling
/// should be able to make the row asking them to stop existing; a checklist
/// that cannot be dismissed is the nag this app has no business being.
enum SetupCardPreferences {
    private static let prefix = "setup-card-hidden."

    private static func key(_ personID: UUID) -> String {
        prefix + personID.uuidString
    }

    static func isHidden(personID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(personID))
    }

    static func setHidden(_ hidden: Bool, personID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(hidden, forKey: key(personID))
    }

    static func clear(personID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(personID))
    }
}
