import SwiftData
import SwiftUI

/// The family: who is in it, what each of them may do, and how to add someone.
///
/// Every control on this screen is a mirror of an RLS policy, never the
/// enforcement itself (I4). Hiding "Change role" from a caregiver is a courtesy;
/// `change_role` refuses them regardless, and a scripted client gets the same
/// answer as this screen does.
struct FamilyView: View {
    // Tombstoned rows stay in the store until the outbox has pushed them, so
    // every list of people has to filter them out.
    @Query(filter: #Predicate<Person> { $0.deletedAt == nil }, sort: \Person.createdAt)
    private var people: [Person]

    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.modelContext) private var context

    @State private var isInviting = false
    @State private var isJoining = false
    @State private var isRenaming = false
    @State private var isConfirmingSharing = false
    @State private var newName = ""
    @State private var errorMessage: String?
    @State private var memberUnderEdit: GroupMember?

    /// People this circle can actually see. See `PeopleView` for why the two
    /// worlds are kept apart rather than merged or hidden.
    private var circlePeople: [Person] {
        guard let activeGroupID = groups.activeGroupID else { return people }
        return people.filter { $0.groupID == activeGroupID }
    }

    var body: some View {
        NavigationStack {
            List {
                if groups.activeGroupID == nil {
                    noGroupSection
                } else {
                    membersSection
                    if groups.role.isStaff {
                        inviteSection
                        if !groups.pendingInvites.isEmpty { pendingInvitesSection }
                    }
                    settingsSection
                }
            }
            .navigationTitle("Sharing")
            .toolbar {
                // `role` defaults to `.owner` for a device with no group at all,
                // so the group has to be checked too or Rename shows on the
                // "you are not sharing with anyone" screen.
                if groups.activeGroupID != nil && groups.role == .owner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Rename") {
                            newName = groups.groupName
                            isRenaming = true
                        }
                    }
                }
            }
            .refreshable {
                await groups.refresh()
                await groups.loadMembers()
                await sync.syncNow()
            }
            .task {
                await groups.refresh()
                await groups.loadMembers()
                await groups.loadPendingInvites()
                openInviteIfRequested()
                openJoinIfRequested()
            }
            // Someone sent here by the setup checklist arrives with the invite
            // sheet already open when there is a group to invite into, and on
            // the "start a family group" section when there is not.
            .onChange(of: navigator.wantsInvite) { _, _ in
                openInviteIfRequested()
            }
            .onChange(of: navigator.wantsJoin) { _, _ in
                openJoinIfRequested()
            }
            .sheet(isPresented: $isInviting) {
                // Only rows the circle actually holds. A subject invite links
                // an account to a recipient row on the server, so offering a
                // local-only person here produced an invitation that could
                // never resolve, and offered it as if the record were shared.
                InviteSheet(people: circlePeople)
            }
            .sheet(isPresented: $isJoining) {
                NavigationStack {
                    JoinGroupView(
                        isOnboarding: false,
                        initialCode: navigator.pendingInviteCode
                    ) { role in
                        navigator.pendingInviteCode = ""
                        UserDefaults.standard.removeObject(forKey: "pendingInviteCode")
                        if role != .subject {
                            Task { await sync.syncNow() }
                        }
                    }
                }
            }
            .sheet(isPresented: $isConfirmingSharing) {
                SharingConsentSheet(people: people) {
                    attestPeopleAndCreateGroup()
                }
            }
            .sheet(item: $memberUnderEdit) { member in
                MemberSheet(member: member, people: circlePeople)
            }
            .alert("Group name", isPresented: $isRenaming) {
                TextField("Family", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task {
                        do { try await groups.rename(to: newName) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private func openInviteIfRequested() {
        guard navigator.wantsInvite else { return }
        navigator.wantsInvite = false
        guard groups.activeGroupID != nil, groups.role.isStaff else { return }
        isInviting = true
    }

    private func openJoinIfRequested() {
        guard navigator.wantsJoin else { return }
        navigator.wantsJoin = false
        isJoining = true
    }

    private var noGroupSection: some View {
        Section {
            if auth.isSignedIn {
                Text("You are not sharing with anyone yet.")
                    .foregroundStyle(.secondary)
                Button("Start a care circle") {
                    if people.contains(where: { !$0.isSelf && $0.surrogateAttestedAt == nil }) {
                        isConfirmingSharing = true
                    } else {
                        Task { await createGroup() }
                    }
                }
                Button("I have an invitation") { isJoining = true }
            } else {
                // Existing local-only installs land here. The whole tracker keeps
                // working; sharing is the thing being offered, not a wall (I3).
                Text("Everything you have entered is on this phone. Sign in to back it up and share it with family.")
                    .foregroundStyle(.secondary)
                NavigationLink("Sign in") {
                    SignInView(purpose: .createFamily) {
                        Task { await createGroup() }
                    }
                }
                // Offered signed-out as well, because someone who was sent a
                // code has to join a circle rather than start one, and the
                // sign-in it needs is now inside the join sheet.
                Button("I have an invitation") { isJoining = true }
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text("Care records work with no account and no signal. Sharing needs an account.")
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(groups.members) { member in
                Button {
                    guard groups.role == .owner, !member.isSelf else { return }
                    memberUnderEdit = member
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.resolvedName)
                                .font(.body.weight(.medium))
                            Text(memberSubtitle(member))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if groups.role == .owner, !member.isSelf {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(groups.groupName.isEmpty ? "Care circle" : groups.groupName)
        } footer: {
            Text(circlePeople.count > 1
                 ? "Helpers can see and update everyone under Care unless you narrow it. A person invited to their own record sees only themselves."
                 : "Helpers can see and update every person under Care. A person invited to their own record sees only themselves.")
        }
    }

    /// The role, plus who this member can actually see when that is not
    /// everyone. Said on the row rather than only inside the sheet, because
    /// "who can read Dad's records" is a question an owner should be able to
    /// answer by looking at the list.
    private func memberSubtitle(_ member: GroupMember) -> String {
        guard member.accessScope == .listed else { return member.role.label }
        let names = circlePeople
            .filter { member.visibleRecipientIDs.contains($0.id) }
            .map(\.displayLabel)
        guard !names.isEmpty else { return "\(member.role.label) · no one yet" }
        return "\(member.role.label) · \(names.joined(separator: ", ")) only"
    }

    private var inviteSection: some View {
        Section {
            Button {
                isInviting = true
            } label: {
                Label("Invite someone", systemImage: "person.badge.plus")
            }
        } footer: {
            Text(groups.role == .owner
                 ? "Enter an email address, or share a link or code. Invitations last 48 hours."
                 : "Invite by email, link, or code. Helpers cannot invite organizers.")
        }
    }

    private var pendingInvitesSection: some View {
        Section("Pending invitations") {
            ForEach(groups.pendingInvites) { invite in
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invite.email ?? "Code \(invite.code)")
                            .font(.body.weight(.medium))
                        Text(inviteDetail(invite))
                            .font(.subheadline)
                            .foregroundStyle(invite.isExpired ? .red : .secondary)
                    }

                    HStack(spacing: 18) {
                        // Sending a dead code is worse than sending nothing:
                        // whoever gets it is told to type it in and is met with
                        // "that code did not work", and now distrusts the next
                        // one. An expired row can only be cleared away.
                        if !invite.isExpired {
                            if let email = invite.email,
                               let url = InviteMessage.emailURL(
                                   address: email,
                                   code: invite.code,
                                   role: invite.role,
                                   personName: personName(for: invite)
                               ) {
                                Link("Email again", destination: url)
                            }

                            ShareLink(item: InviteMessage.text(
                                code: invite.code,
                                role: invite.role,
                                personName: personName(for: invite)
                            )) {
                                Text("Share")
                            }
                        }

                        Button(invite.isExpired ? "Remove" : "Revoke", role: .destructive) {
                            Task { await revoke(invite) }
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var settingsSection: some View {
        Section {
            if groups.role == .subject {
                NavigationLink {
                    TransparencyView(isOnboarding: false)
                } label: {
                    Label("Who can see me", systemImage: "eye")
                }
            }

            NavigationLink {
                LeaveOrDeleteView()
            } label: {
                Label(
                    groups.role == .owner && groups.members.count <= 1
                        ? "Delete this group"
                        : "Leave this group",
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
                .foregroundStyle(.red)
            }
        }
    }

    private func createGroup() async {
        do {
            let name = people.first.map { person -> String in
                person.isSelf ? "My care circle" : "\(person.name)'s care circle"
            } ?? "Care circle"
            let groupID = try await groups.createGroup(named: name)
            await sync.adoptLocalData(into: groupID)
            await groups.loadMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attestPeopleAndCreateGroup() {
        for person in people where !person.isSelf && person.surrogateAttestedAt == nil {
            person.surrogateAttestedAt = Date()
            person.recordLocalChange(in: context)
        }
        try? context.save()
        isConfirmingSharing = false
        Task { await createGroup() }
    }

    private func personName(for invite: PendingInvite) -> String? {
        guard let recipientID = invite.recipientID else { return nil }
        return people.first(where: { $0.id == recipientID })?.displayLabel
    }

    private func inviteDetail(_ invite: PendingInvite) -> String {
        let recipient = personName(for: invite).map { " for \($0)" } ?? ""
        if invite.isExpired { return "Expired, \(invite.role.label.lowercased())\(recipient)" }
        return "\(invite.role.label)\(recipient), expires \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func revoke(_ invite: PendingInvite) async {
        do {
            try await groups.revokeInviteCode(invite.code)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SharingConsentSheet: View {
    let people: [Person]
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasPermission = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Starting a care circle uploads the saved records for \(people.map(\.displayLabel).joined(separator: ", ")) so invited family can use the same information.")
                    Text("Every helper you invite can see and update every person in this care circle. A person invited to their own record sees only themselves.")
                } header: {
                    Text("Before you share")
                }

                Section {
                    Toggle("I have permission to keep and share this care information.", isOn: $hasPermission)
                }

                Section {
                    Button("Start care circle") {
                        onConfirm()
                    }
                    .disabled(!hasPermission)
                }
            }
            .navigationTitle("Share care records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - One member

/// Role changes and removal, owner only.
private struct MemberSheet: View {
    let member: GroupMember
    /// The circle's people, so the access list can name them. Passed in rather
    /// than queried again here so this sheet and the list behind it are looking
    /// at exactly the same set.
    let people: [Person]

    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingTransfer = false
    @State private var pendingRole: GroupRole?
    @State private var scope: MemberAccessScope = .all
    @State private var granted: Set<UUID> = []
    @State private var isSavingAccess = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach([GroupRole.caregiver, GroupRole.subject], id: \.self) { option in
                        Button {
                            // Asked, like the two actions below it in this same
                            // sheet. Demoting a caregiver to subject takes the
                            // rest of the family off their phone (the client
                            // purges what they had already pulled, and RLS
                            // stops the rest), and it did that on a single tap
                            // on a list row while "Make organizer" and "Remove
                            // from the group" both stopped to ask. The person
                            // who finds out is not the one tapping.
                            guard option != member.role else { return }
                            pendingRole = option
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                    Text(describe(option))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if member.role == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Role")
                }

                accessSection

                Section {
                    Button("Make organizer") { isConfirmingTransfer = true }
                } footer: {
                    Text("There is one organizer. Handing it over makes you a caregiver.")
                }

                Section {
                    Button("Remove from the group", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(member.resolvedName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                scope = member.accessScope
                granted = member.visibleRecipientIDs
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove \(member.resolvedName)?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task { await remove() }
                }
            } message: {
                Text("They lose access straight away. Anything they entered stays in the family record.")
            }
            .confirmationDialog(
                pendingRole.map { "Change \(member.resolvedName) to \($0.label)?" } ?? "Change role?",
                isPresented: Binding(
                    get: { pendingRole != nil },
                    set: { if !$0 { pendingRole = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Change") {
                    guard let option = pendingRole else { return }
                    pendingRole = nil
                    Task { await change(to: option) }
                }
                Button("Cancel", role: .cancel) { pendingRole = nil }
            } message: {
                Text(pendingRole == .subject
                     ? "They will see only their own list on their own phone, and everyone else's records come off it."
                     : "They will see and be able to edit everyone in the family.")
            }
            .confirmationDialog(
                "Make \(member.resolvedName) the organizer?",
                isPresented: $isConfirmingTransfer,
                titleVisibility: .visible
            ) {
                Button("Hand over") {
                    Task { await transfer() }
                }
            } message: {
                Text("You become a caregiver and can no longer change roles or billing.")
            }
        }
    }

    private func describe(_ role: GroupRole) -> String {
        switch role {
        case .owner: return "Everything, including roles and billing."
        case .caregiver: return "Sees and edits everyone in the family."
        case .subject: return "Sees only their own list, and marks their own doses."
        }
    }

    /// Who this member can read.
    ///
    /// Only shown when there is more than one person to divide up, and only for
    /// a caregiver: an owner is never restrictable (the RPC refuses, so a
    /// control here would be a button that fails), and a subject is scoped by
    /// the record they are linked to rather than by this table.
    ///
    /// Default is everyone, and it stays everyone until someone deliberately
    /// changes it. Narrowing is the exception, for the neighbour who helps with
    /// Mom and has no reason to be reading Dad's bills or notes.
    @ViewBuilder
    private var accessSection: some View {
        if member.canBeRestricted, people.count > 1 {
            Section {
                Picker("Can see", selection: $scope) {
                    Text("Everyone").tag(MemberAccessScope.all)
                    Text("Only some").tag(MemberAccessScope.listed)
                }
                .pickerStyle(.segmented)
                .onChange(of: scope) { _, newValue in
                    // Starting from everyone ticked is the honest default: this
                    // control narrows a permission they already have, so
                    // opening it with nothing selected would misrepresent what
                    // they can see right now.
                    if newValue == .listed, granted.isEmpty {
                        granted = Set(people.map(\.id))
                    }
                    Task { await saveAccess() }
                }

                if scope == .listed {
                    ForEach(people) { person in
                        accessRow(for: person)
                    }
                }
            } header: {
                Text("Can see")
            } footer: {
                Text(accessFooter)
            }
        }
    }

    private func accessRow(for person: Person) -> some View {
        Button {
            if granted.contains(person.id) {
                granted.remove(person.id)
            } else {
                granted.insert(person.id)
            }
            Task { await saveAccess() }
        } label: {
            HStack {
                Text(person.displayLabel)
                Spacer()
                if granted.contains(person.id) {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSavingAccess)
    }

    private var accessFooter: String {
        scope == .all
            ? "\(member.resolvedName) can see and update everyone in this circle."
            : "\(member.resolvedName) can only open the people ticked here. The database refuses them everything else, and their app clears what it already downloaded the next time it reaches the server."
    }

    private func saveAccess() async {
        isSavingAccess = true
        defer { isSavingAccess = false }
        do {
            try await groups.setAccess(for: member.id, scope: scope, recipientIDs: granted)
        } catch {
            errorMessage = error.localizedDescription
            // Put the controls back to what the server still believes, so the
            // screen never shows a restriction that was not applied.
            scope = member.accessScope
            granted = member.visibleRecipientIDs
        }
    }

    private func change(to role: GroupRole) async {
        guard role != member.role else { return }
        do {
            try await groups.changeRole(of: member.id, to: role)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() async {
        do {
            try await groups.removeMember(member.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transfer() async {
        do {
            try await groups.transferOwnership(to: member.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Leaving

private struct LeaveOrDeleteView: View {
    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var isLeaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var isLastOwner: Bool {
        groups.role == .owner && groups.members.filter { $0.role == .owner }.count <= 1
    }

    private var isOnlyMember: Bool { groups.members.count <= 1 }

    var body: some View {
        List {
            if isLastOwner && !isOnlyMember {
                Section {
                    Text("You are the only organizer. Make someone else the organizer first, then you can leave.")
                        .foregroundStyle(.secondary)
                }
            } else if isOnlyMember && groups.role == .owner {
                Section {
                    Button("Delete this group", role: .destructive) { isDeleting = true }
                } footer: {
                    Text("Nobody else is in it, so the shared copy of the record goes with it. What is on this phone stays on this phone.")
                }
            } else {
                Section {
                    Button("Leave this group", role: .destructive) { isLeaving = true }
                } footer: {
                    Text("The others keep the record. You stop seeing it on this phone.")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Leave")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isLeaving) {
            LeaveGroupSheet { dismiss() }
        }
        .confirmationDialog("Delete this group?", isPresented: $isDeleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await groups.deleteGroup()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
