import SwiftData
import SwiftUI

struct PeopleView: View {
    // Tombstoned rows stay in the store until the outbox has pushed them, so
    // every list of people has to filter them out.
    @Query(filter: #Predicate<Person> { $0.deletedAt == nil }, sort: \Person.createdAt)
    private var people: [Person]
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    @Environment(GroupService.self) private var groups
    @Environment(AuthService.self) private var auth
    @Environment(CheckInService.self) private var checkIn

    @State private var isAddingPerson = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var searchResults: [SearchHit] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searchDestination: SearchDestination?
    @State private var pendingDeletion: Person?
    @State private var pendingAdoption: Person?

    /// Free tier tracks one person. The second person is the natural upgrade
    /// moment: by then the app has already proved itself on the first one.
    ///
    /// Deliberately counted in *people*, not members (D31). Siblings joining are
    /// not "extra users" to be charged for; a second parent is.
    private var freePersonLimit: Int { 1 }

    /// The count the paywall gate is allowed to see.
    ///
    /// Scoped to the group this device is actually looking at, not to the whole
    /// store. Someone who tracked a parent locally and then joined a sibling's
    /// family through `JoinGroupView` (which never runs `adoptLocalData`) holds
    /// two rows from two different worlds, and counting both consumed their free
    /// slot without them having added a second person in any sense they would
    /// recognise. With no group, everything local is theirs and everything
    /// counts.
    private var billablePersonCount: Int {
        guard groups.activeGroupID != nil else { return people.count }
        return circlePeople.count
    }

    /// The two worlds, kept apart on screen.
    ///
    /// Every list here used to query every non-tombstoned `Person`, so someone
    /// who tracked a parent privately and then accepted a sibling's invitation
    /// saw both sets in one undifferentiated list. That is a data boundary
    /// problem rather than a labelling one: the private row looked shared, and
    /// a caregiver could invite against it or edit it believing the family
    /// would see it. Hiding it would be worse, because a record that vanishes
    /// on the day you join a circle reads as data loss. So both are shown, in
    /// named sections, and moving one across is an explicit act.
    private var circlePeople: [Person] {
        guard let activeGroupID = groups.activeGroupID else { return people }
        return people.filter { $0.groupID == activeGroupID }
    }

    private var localOnlyPeople: [Person] {
        guard groups.activeGroupID != nil else { return [] }
        return people.filter { $0.groupID == nil }
    }

    /// Rows belonging to some *other* group: a circle this device has left, or
    /// one it was removed from before the tombstones arrived. Shown with the
    /// local-only rows rather than silently, because they are equally not part
    /// of what the family can see.
    private var strandedPeople: [Person] {
        guard let activeGroupID = groups.activeGroupID else { return [] }
        return people.filter { $0.groupID != nil && $0.groupID != activeGroupID }
    }

    private var privatePeople: [Person] { localOnlyPeople + strandedPeople }

    /// The payer's own device unlocks straight from RevenueCat with no round
    /// trip; everyone else in the family resolves through the group row, which
    /// is already cached locally and so survives being offline (§9).
    private var isUnlocked: Bool { store.isPro || groups.hasPlus }

    /// True once there is a non-blank query, so an empty search field shows
    /// the normal people list rather than an empty results screen.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    if searchResults.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(searchResults) { hit in
                            // A result that cannot be opened is an index, not
                            // a search. Each hit pushes the screen its record
                            // lives on, for the person it belongs to.
                            Button {
                                searchDestination = SearchDestination(
                                    personID: hit.personID, kind: hit.kind
                                )
                            } label: {
                                SearchHitRow(hit: hit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if privatePeople.isEmpty {
                    // The ordinary case: one world, no headings needed.
                    ForEach(people) { person in
                        personLink(person)
                    }
                    .onDelete { offsets in delete(people, at: offsets) }
                } else {
                    Section {
                        ForEach(circlePeople) { person in
                            personLink(person)
                        }
                        .onDelete { offsets in delete(circlePeople, at: offsets) }
                    } header: {
                        Text(groups.groupName.isEmpty ? "Shared with the family" : groups.groupName)
                    }

                    Section {
                        ForEach(privatePeople) { person in
                            personLink(person)
                                .swipeActions(edge: .leading) {
                                    if person.groupID == nil {
                                        Button {
                                            pendingAdoption = person
                                        } label: {
                                            Label("Share", systemImage: "person.2")
                                        }
                                        .tint(.accentColor)
                                    }
                                }
                        }
                        .onDelete { offsets in delete(privatePeople, at: offsets) }
                    } header: {
                        Text("Only on this phone")
                    } footer: {
                        Text("Nobody else in your care circle can see these. Swipe one to share it with the family, or leave it here.")
                    }
                }
            }
            .navigationTitle("Care")
            // Leads with the kinds nobody guesses are searchable. The old
            // prompt named five of the eight `CareSearch` returns and left out
            // people, allergies and conditions, contacts, and incidents, so a
            // search for "allergy" or "fall" looked unsupported before it ran.
            .searchable(text: $searchText, prompt: "Meds, allergies, people, tasks, contacts, notes")
            .navigationDestination(item: $searchDestination) { destination in
                if let person = people.first(where: { $0.id == destination.personID }) {
                    searchScreen(for: destination.kind, person: person)
                }
            }
            // Debounced (I1: local scan, not per keystroke) so a naive
            // rescan of two years of rows never runs on every typed
            // character (plan82 slice F).
            .onChange(of: searchText) { _, newValue in
                runDebouncedSearch(for: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isUnlocked || billablePersonCount < freePersonLimit {
                            isAddingPerson = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label("Add person", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingPerson) {
                PersonEditorSheet(requiresAttestation: groups.activeGroupID != nil) { draft in
                    let person = Person(
                        name: draft.name,
                        relationship: draft.relationship,
                        birthDate: draft.birthDate,
                        colorIndex: people.count,
                        isSelf: draft.relationship.lowercased() == "me"
                    )
                    person.groupID = groups.activeGroupID
                    if draft.attested { person.surrogateAttestedAt = Date() }
                    context.insert(person)
                    person.recordLocalChange(in: context)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                pendingAdoption.map { "Share \($0.displayLabel) with the family?" } ?? "Share this record?",
                isPresented: Binding(
                    get: { pendingAdoption != nil },
                    set: { if !$0 { pendingAdoption = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Share") {
                    if let person = pendingAdoption { adopt(person) }
                    pendingAdoption = nil
                }
                Button("Cancel", role: .cancel) { pendingAdoption = nil }
            } message: {
                // Named in full, because this is the moment a private record
                // becomes other people's to read, and it does not come back.
                Text(pendingAdoption.map(adoptionScope) ?? "")
            }
            .confirmationDialog(
                pendingDeletion.map { "Remove \($0.displayLabel)?" } ?? "Remove this person?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let person = pendingDeletion { remove(person) }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                // The scope is the point. One swipe used to take the person and
                // everything hanging off them, on every phone in the family,
                // with nothing in between and no way back.
                Text(pendingDeletion.map(deletionScope) ?? "")
            }
        }
    }

    /// Where a search result opens: the screen that holds that kind of record,
    /// for the person it belongs to.
    @ViewBuilder
    private func searchScreen(for kind: SearchHitKind, person: Person) -> some View {
        switch kind {
        case .person, .medication:
            PersonDetailView(person: person)
        case .provider:
            ProvidersView(person: person)
        case .visit:
            VisitsView(person: person)
        case .careEvent:
            CareEventsView(person: person)
        case .task:
            CareTasksView(person: person)
        case .emergencyContact:
            EmergencyContactsView(person: person)
        case .note:
            CareNotesView(person: person)
        case .bill:
            BillsView(person: person)
        }
    }

    private func deletionScope(_ person: Person) -> String {
        let counts = [
            pluralized(person.activeMedications.count, "medication", "medications"),
            pluralized(person.liveVisits.count, "visit", "visits"),
            pluralized(person.liveNotes.count, "note", "notes"),
            pluralized(person.liveVitals.count, "reading", "readings"),
            pluralized(person.liveBills.count, "bill", "bills")
        ].compactMap { $0 }

        // Phrased so the verb never has to agree with the count: "their 1
        // medication go with them" is what the obvious wording produces.
        let tail = counts.isEmpty
            ? "This removes their whole record."
            : "This also removes their \(counts.joined(separator: ", "))."
        return "\(tail) Everyone in your care circle loses them too, and it cannot be undone."
    }

    private func pluralized(_ n: Int, _ singular: String, _ plural: String) -> String? {
        guard n > 0 else { return nil }
        return "\(n) \(n == 1 ? singular : plural)"
    }

    /// "3 of 6 set up", or nothing once there is nothing left to do.
    ///
    /// With two parents tracked, this is the only place that says which record
    /// still has gaps in it. A finished checklist disappears rather than
    /// lingering as a solved progress bar.
    private func setupSummary(for person: Person) -> String? {
        guard !SetupCardPreferences.isHidden(personID: person.id) else { return nil }
        // Counted over the steps still being asked about, so this line agrees
        // with the card on Today rather than continuing to count rows the user
        // has waved away.
        let steps = SetupChecklist.visible(
            SetupChecklist.steps(
                for: person,
                remindersEnabled: DoseReminderPreferences.isEnabled(personID: person.id),
                hasSharedWithFamily: groups.hasSharedWithFamily,
                hasCheckIn: checkIn.settings(for: person)?.enabled == true
            ),
            dismissed: SetupStepPreferences.dismissed(personID: person.id)
        )
        guard !SetupChecklist.isFinished(steps) else { return nil }
        return "\(SetupChecklist.completed(steps)) of \(steps.count) set up"
    }

    /// Asks first. Every other swipe-to-delete in the app removes one row; this
    /// one removes the person that every other row hangs off, so it is the one
    /// place the gesture on its own is not enough.
    private func delete(_ list: [Person], at offsets: IndexSet) {
        guard let index = offsets.first, list.indices.contains(index) else { return }
        pendingDeletion = list[index]
    }

    @ViewBuilder
    private func personLink(_ person: Person) -> some View {
        NavigationLink {
            PersonDetailView(person: person)
        } label: {
            PersonRow(person: person, setupSummary: setupSummary(for: person))
        }
    }

    /// Moves one private record into the circle. Deliberately per person, and
    /// deliberately not run by `JoinGroupView`: accepting an invitation must
    /// never upload the rest of what is on someone's phone.
    private func adopt(_ person: Person) {
        guard let groupID = groups.activeGroupID else { return }
        let personID = person.id
        Task { await SyncCoordinator.shared.adoptPerson(id: personID, into: groupID) }
    }

    private func adoptionScope(_ person: Person) -> String {
        let counts = [
            pluralized(person.activeMedications.count, "medication", "medications"),
            pluralized(person.liveVisits.count, "visit", "visits"),
            pluralized(person.liveNotes.count, "note", "notes"),
            pluralized(person.liveBills.count, "bill", "bills")
        ].compactMap { $0 }

        let detail = counts.isEmpty
            ? "Their whole record is uploaded"
            : "Their record is uploaded, including \(counts.joined(separator: ", "))"
        let circle = groups.groupName.isEmpty ? "your care circle" : groups.groupName
        return "\(detail), and everyone in \(circle) can read it from then on. There is no way to make it private again."
    }

    private func remove(_ person: Person) {
        // A tombstone, not a hard delete: the row has to outlive the tap for
        // the outbox to have anything to push, and only the push makes the
        // delete reach the rest of the family. `markSynced` clears it out
        // afterwards, and their medications, visits and the rest go with it
        // through the cascade rule on the other devices.
        DoseReminderPreferences.clear(personID: person.id)
        person.tombstone(in: context)
        try? context.save()
        Task { await DoseReminderScheduler.refresh(in: context) }
    }

    /// Cancels any in-flight search, then waits out a short debounce before
    /// running `CareSearch` so it fetches once per query rather than once
    /// per keystroke.
    private func runDebouncedSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = CareSearch.search(query: query, people: people)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }
}

/// What a tapped search result pushes. Identified by person and kind rather
/// than by the record itself, because `SearchHit` is a value built from the
/// store and holds no reference back to the row it came from.
private struct SearchDestination: Hashable {
    let personID: UUID
    let kind: SearchHitKind
}

private struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hit.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.body.weight(.medium))
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(hit.personName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct PersonRow: View {
    let person: Person
    let setupSummary: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(person.color.opacity(0.18))
                Text(person.initials)
                    .font(.headline)
                    .foregroundStyle(person.color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let setupSummary {
                    Label(setupSummary, systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// What is outstanding for this person, not how many rows they have.
    ///
    /// This used to read "Mother · 4 medications", which is an inventory count:
    /// the one screen in the app that shows two people at once said nothing
    /// about either of them. A caregiver could stand on this list with a dose
    /// two hours overdue on the second row and see no sign of it.
    ///
    /// Read from `TodayDigest`, the same type the Today tab renders, so the two
    /// screens cannot disagree about what "2 due" means.
    private var subtitle: String {
        let status = TodayDigest.build(for: [person]).first?.statusLine ?? ""
        if person.relationship.isEmpty { return status }
        return status.isEmpty ? person.relationship : "\(person.relationship) · \(status)"
    }
}

struct PersonEditorSheet: View {
    struct Draft {
        var name: String
        var relationship: String
        var birthDate: Date?
        var attested: Bool
    }

    /// True once the app is a shared family record rather than one person's
    /// private notes. Adding someone else's health data to a record other people
    /// will read is a surrogate decision, and D28 says do not simulate a consent
    /// that never happened: ask the caregiver to say plainly that it is theirs.
    var requiresAttestation: Bool = false
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -75, to: Date()) ?? Date()
    @State private var attested = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (!requiresAttestation || attested)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Relationship (optional)", text: $relationship)
                }

                Section {
                    Toggle("Date of birth", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Born", selection: $birthDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Used on the emergency card.")
                }

                if requiresAttestation {
                    Section {
                        Toggle(isOn: $attested) {
                            Text("They know I'm keeping this, or I'm the one who makes their health decisions.")
                                .font(.subheadline)
                        }
                    } footer: {
                        // The app never assesses capacity (D29). It asks a
                        // question and records the answer; deciding whether
                        // someone can consent is a clinical judgment an indie
                        // consumer app has no business making.
                        Text("Every helper in your care circle will be able to see what you enter for this person.")
                    }
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Draft(
                            name: name.trimmingCharacters(in: .whitespaces),
                            relationship: relationship.trimmingCharacters(in: .whitespaces),
                            birthDate: hasBirthDate ? birthDate : nil,
                            attested: attested
                        ))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    PeopleView()
        .modelContainer(SampleData.previewContainer())
        .environment(StoreService.shared)
        .environment(GroupService.shared)
        .environment(AuthService.shared)
        .environment(CheckInService.shared)
        .environment(AppNavigator())
}
