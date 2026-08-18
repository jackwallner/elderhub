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
                MemberSheet(member: member)
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
                            Text(member.role.label)
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
            Text("Helpers can see and update every person under Care. A person invited to their own record sees only themselves.")
        }
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

    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingTransfer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach([GroupRole.caregiver, GroupRole.subject], id: \.self) { option in
                        Button {
                            Task { await change(to: option) }
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
