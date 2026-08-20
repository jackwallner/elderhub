import Foundation

// MARK: - Search hit kind

enum SearchHitKind: String, CaseIterable, Identifiable, Sendable {
    case person
    case medication
    case provider
    case visit
    case careEvent
    case task
    case emergencyContact
    case note
    case bill

    var id: String { rawValue }

    var label: String {
        switch self {
        case .person: return "Person"
        case .medication: return "Medication"
        case .provider: return "Provider"
        case .visit: return "Visit"
        case .careEvent: return "Incident"
        case .task: return "Task"
        case .emergencyContact: return "Contact"
        case .note: return "Note"
        case .bill: return "Bill"
        }
    }

    var symbol: String {
        switch self {
        case .person: return "person"
        case .medication: return "pills"
        case .provider: return "stethoscope"
        case .visit: return "calendar"
        case .careEvent: return "note.text"
        case .task: return "checklist"
        case .emergencyContact: return "phone"
        case .note: return "doc.text"
        case .bill: return "dollarsign.circle"
        }
    }
}

// MARK: - Search hit

/// One search result (plan82 slice F). `personID`/`personName` ride along on
/// every hit because the search is across everyone in the family by default,
/// and "was that Mom or Dad?" is exactly the question a multi-person app has
/// to answer on the results screen, not one tap later.
struct SearchHit: Identifiable, Hashable, Sendable {
    let personID: UUID
    let personName: String
    let kind: SearchHitKind
    let title: String
    let snippet: String
    let matchedField: String
    let date: Date
    /// Index of `matchedField` within that entity's priority-ordered field
    /// list. Lower is higher priority (name beats notes). Drives ranking;
    /// not shown in the UI.
    let fieldPriority: Int

    /// Derived rather than stored, the same reasoning as `TimelineEntry.id`:
    /// nothing here needs a new identity of its own.
    var id: String {
        "\(personID.uuidString)|\(kind.rawValue)|\(title)|\(matchedField)|\(date.timeIntervalSince1970)"
    }
}

// MARK: - Search

/// Pure, offline search over already-fetched `Person` rows and their
/// relationships (plan82 slice F, invariant I1). No `ModelContext`, no
/// fetching, no network: callers own the querying, this only ranks what they
/// hand it. Testable without a store, the same way `ScheduleEngine` and
/// `TimelineBuilder` are.
///
/// Type "hearing" and this is meant to surface the audiologist, the
/// hearing-aid medication note, the visit where it came up, and the incident
/// log entry, in one pass across every person in the family.
enum CareSearch {

    /// One noisy field (a person with forty medications) should not crowd
    /// out visits, providers and incidents from the results list.
    static let defaultLimitPerKind = 5

    @MainActor
    static func search(
        query: String,
        people: [Person],
        limitPerKind: Int = defaultLimitPerKind
    ) -> [SearchHit] {
        let tokens = tokenize(query)
        // An empty query is a blank search field, not "show me everything";
        // returning nothing here is what keeps the results list from
        // flashing the entire family record before the user has typed.
        guard !tokens.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for person in people where person.deletedAt == nil {
            hits += medicationHits(person: person, tokens: tokens)
            hits += providerHits(person: person, tokens: tokens)
            hits += visitHits(person: person, tokens: tokens)
            hits += careEventHits(person: person, tokens: tokens)
            hits += taskHits(person: person, tokens: tokens)
            hits += personHits(person: person, tokens: tokens)
            hits += contactHits(person: person, tokens: tokens)
            hits += noteHits(person: person, tokens: tokens)
            hits += billHits(person: person, tokens: tokens)
        }

        hits.sort { lhs, rhs in
            if lhs.fieldPriority != rhs.fieldPriority { return lhs.fieldPriority < rhs.fieldPriority }
            return lhs.date > rhs.date
        }

        var counts: [SearchHitKind: Int] = [:]
        var capped: [SearchHit] = []
        for hit in hits {
            let count = counts[hit.kind, default: 0]
            guard count < limitPerKind else { continue }
            counts[hit.kind] = count + 1
            capped.append(hit)
        }
        return capped
    }

    // MARK: Per-entity matching

    private static func medicationHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveMedications
            .compactMap { medication in
                makeHit(
                    person: person,
                    kind: .medication,
                    title: medication.displayName,
                    date: medication.startDate,
                    fields: [
                        ("name", medication.name),
                        ("purpose", medication.purpose),
                        ("prescriber", medication.resolvedPrescriberName),
                        ("pharmacy", medication.resolvedPharmacyName),
                        ("instructions", medication.instructions)
                    ],
                    tokens: tokens
                )
            }
    }

    private static func providerHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveProviders
            .compactMap { provider in
                makeHit(
                    person: person,
                    kind: .provider,
                    title: provider.name,
                    date: provider.updatedAt,
                    fields: [
                        ("name", provider.name),
                        ("specialty", provider.specialty),
                        ("notes", provider.notes)
                    ],
                    tokens: tokens
                )
            }
    }

    private static func visitHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveVisits
            .compactMap { visit in
                makeHit(
                    person: person,
                    kind: .visit,
                    title: visitTitle(visit),
                    date: visit.date,
                    fields: [
                        ("provider", visit.resolvedProviderName),
                        ("reason", visit.reason),
                        ("notes", visit.notes),
                        ("follow-up", visit.followUp)
                    ],
                    tokens: tokens
                )
            }
    }

    private static func careEventHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveCareEvents
            .compactMap { event in
                makeHit(
                    person: person,
                    kind: .careEvent,
                    title: event.kind.label,
                    date: event.occurredAt,
                    fields: [("note", event.note)],
                    tokens: tokens
                )
            }
    }

    /// Includes tasks already ticked off. "Did anyone ever call the pharmacy
    /// about the refill" is a question about the past, and a search that only
    /// looked at open work could not answer it.
    private static func taskHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveTasks
            .compactMap { task in
                makeHit(
                    person: person,
                    kind: .task,
                    title: task.title,
                    date: task.dueAt ?? task.createdAt,
                    fields: [
                        ("title", task.title),
                        ("assignee", task.assigneeName),
                        ("notes", task.notes)
                    ],
                    tokens: tokens
                )
            }
    }

    /// The whole point of a free-form pile: a family that wrote the gate code
    /// down eight months ago finds it by typing "gate", not by remembering
    /// which note they put it in.
    private static func noteHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveNotes
            .compactMap { note in
                makeHit(
                    person: person,
                    kind: .note,
                    title: note.displayTitle,
                    date: note.updatedAt,
                    fields: [
                        ("title", note.title),
                        ("note", note.body)
                    ],
                    tokens: tokens
                )
            }
    }

    private static func billHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveBills
            .compactMap { bill in
                makeHit(
                    person: person,
                    kind: .bill,
                    title: bill.payee.isEmpty ? "Untitled bill" : bill.payee,
                    date: bill.dueAt ?? bill.updatedAt,
                    fields: [
                        ("payee", bill.payee),
                        ("kind", bill.category.label),
                        ("note", bill.notes)
                    ],
                    tokens: tokens
                )
            }
    }

    private static func personHits(person: Person, tokens: [String]) -> [SearchHit] {
        let hit = makeHit(
            person: person,
            kind: .person,
            title: person.name,
            date: person.createdAt,
            fields: [
                ("conditions", person.conditions.joined(separator: ", ")),
                ("allergies", person.allergies.joined(separator: ", ")),
                ("notes", person.notes)
            ],
            tokens: tokens
        )
        return hit.map { [$0] } ?? []
    }

    private static func contactHits(person: Person, tokens: [String]) -> [SearchHit] {
        person.liveContacts
            .compactMap { contact in
                makeHit(
                    person: person,
                    kind: .emergencyContact,
                    title: contact.name,
                    date: contact.updatedAt,
                    fields: [("name", contact.name)],
                    tokens: tokens
                )
            }
    }

    // MARK: Matching primitives

    /// `fields` must already be in priority order (name beats notes). All
    /// `tokens` must match somewhere in the record, in any field; the index
    /// of the first field that contains a token becomes the hit's rank and
    /// supplies `matchedField`/`snippet`.
    private static func makeHit(
        person: Person,
        kind: SearchHitKind,
        title: String,
        date: Date,
        fields: [(name: String, text: String)],
        tokens: [String]
    ) -> SearchHit? {
        let folded = fields.map { (name: $0.name, text: $0.text, folded: fold($0.text)) }
        guard tokens.allSatisfy({ token in folded.contains { $0.folded.contains(token) } }) else {
            return nil
        }
        let matchIndex = folded.firstIndex { field in tokens.contains { field.folded.contains($0) } } ?? 0
        let matched = folded[matchIndex]
        return SearchHit(
            personID: person.id,
            personName: person.name,
            kind: kind,
            title: title,
            snippet: matched.text,
            matchedField: matched.name,
            date: date,
            fieldPriority: matchIndex
        )
    }

    /// Named for which side of now it sits on, so a result for something still
    /// to come is not read as something already been to.
    private static func visitTitle(_ visit: Visit) -> String {
        let noun = visit.isUpcoming() ? "Appointment" : "Visit"
        let name = visit.resolvedProviderName
        return name.isEmpty ? noun : "\(noun): \(name)"
    }

    private static func tokenize(_ query: String) -> [String] {
        query
            .components(separatedBy: .whitespacesAndNewlines)
            .map(fold)
            .filter { !$0.isEmpty }
    }

    /// Case- and diacritic-insensitive, locale-agnostic (`locale: nil`) so
    /// the same query matches the same way regardless of device region.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
