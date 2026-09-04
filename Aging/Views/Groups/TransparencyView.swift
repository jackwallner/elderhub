import SwiftData
import SwiftUI

/// "Who can see me", shown to a subject *before* any of their data syncs, and
/// reachable afterwards in one tap from their home screen rather than buried in
/// Settings (D27).
///
/// The reason this is first-class: the person joining did not choose this app.
/// Someone else installed it and read them a code. Telling them plainly who is
/// in the group, what each person can see, and that they can walk away is the
/// difference between a family tool and something their children put on them.
struct TransparencyView: View {
    let isOnboarding: Bool
    var onAccepted: (() -> Void)?

    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var isLeaving = false
    @State private var isRetrying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who can see you")
                        .font(.title.bold())
                    Text("You have joined \(groups.groupName.isEmpty ? "a care circle" : groups.groupName).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                memberList

                // Exhaustive, deliberately. This is the page someone reads
                // before any of their data syncs, so a category left off it is
                // a consent they were not asked for. Every feature that stores
                // something against a person is named here; if a new one is
                // added to `CareFeature`, it belongs in this list too.
                section(
                    title: "What they can see",
                    lines: [
                        "Your medications, and when a dose was marked taken or skipped",
                        "Your allergies, conditions and emergency contacts",
                        "Doctor visits, and the doctors and pharmacies saved for you",
                        "Any readings entered for you, and any symptoms or falls logged",
                        "Shared to-dos about you, and who they are assigned to",
                        "Free-form notes the family writes about you",
                        "Bills the family records paying on your behalf",
                        "Whether you pressed your check-in button today"
                    ],
                    symbol: "eye"
                )

                section(
                    title: "What they cannot see",
                    lines: [
                        "Where you are. This app has no location and never asks for it",
                        "Anything from the rest of your phone",
                        "Your Apple account, or anything in your Health app"
                    ],
                    symbol: "eye.slash"
                )

                section(
                    title: "What you can do",
                    lines: [
                        "Mark your own doses and press your own check-in button",
                        "See this page any time from your home screen",
                        "Leave the group whenever you want. Your family is told when you do"
                    ],
                    symbol: "hand.raised"
                )

                Text("This app helps a family keep track of medications. It is not a medical device, it does not give medical advice, and it cannot tell whether you are unwell or call anyone for help.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isOnboarding {
                    // Two buttons while the list is missing, and the retry is
                    // the prominent one.
                    //
                    // "I understand" used to be the only control on a screen
                    // that had just admitted it could not name a single person
                    // who can see this record, which is consent to a disclosure
                    // whose contents are unknown. It is not removed, because
                    // this is the recipient's own screen and a phone with no
                    // signal must never be a room with no door (I3): it becomes
                    // a plain secondary action that says what is being agreed
                    // to.
                    if groups.hasCachedMemberList {
                        Button {
                            groups.markTransparencyAccepted()
                            onAccepted?()
                        } label: {
                            Text("I understand")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("transparency.accept")
                    } else {
                        Button {
                            Task {
                                isRetrying = true
                                await groups.refresh()
                                await groups.loadMembers()
                                isRetrying = false
                            }
                        } label: {
                            Text(isRetrying ? "Checking…" : "Try again")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRetrying)
                        .accessibilityIdentifier("transparency.retry")

                        Button {
                            groups.markTransparencyAccepted()
                            onAccepted?()
                        } label: {
                            Text("Continue without the list")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("transparency.accept")
                    }
                } else {
                    Button(role: .destructive) {
                        isLeaving = true
                    } label: {
                        Text("Leave this group")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .navigationTitle(isOnboarding ? "" : "Who Can See Me")
        .navigationBarTitleDisplayMode(.inline)
        .task { await groups.loadMembers() }
        .sheet(isPresented: $isLeaving) {
            LeaveGroupSheet { dismiss() }
        }
    }

    /// The list, or an honest account of why it is not here.
    ///
    /// It used to render `groups.members` unconditionally, and that list lived
    /// only in memory: a cold launch with no signal drew an empty box, so the
    /// screen asked someone to accept being watched without naming a single
    /// watcher. The names are cached now, and the remaining gap (a first launch
    /// that has never reached the server) says so instead of showing nothing.
    @ViewBuilder
    private var memberList: some View {
        if groups.hasCachedMemberList {
            cachedMemberList
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Can't show the list yet", systemImage: "wifi.slash")
                    .font(.body.weight(.medium))
                Text("This phone has not been able to reach your family's circle, so it cannot name who is in it. Nothing of yours has been shared yet. Try again once you have a signal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var cachedMemberList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups.members) { member in
                HStack(spacing: 12) {
                    Image(systemName: member.role.isStaff ? "person.badge.shield.checkmark" : "person")
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.resolvedName)
                            .font(.body.weight(.medium))
                        Text(member.role.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func section(title: String, lines: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(line)
                }
                .font(.body)
            }
        }
    }
}

/// Leaving, gated behind re-typing a word (D27). The friction is there so it is
/// not tapped by accident, not to talk anyone out of it: the door stays
/// unlocked, and the safety net is that the family is told immediately.
struct LeaveGroupSheet: View {
    let onLeft: () -> Void

    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let phrase = "LEAVE"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your family will be told straight away that you left. They keep the medication list they built; you stop sharing anything new with them.")
                } header: {
                    Text("Leaving \(groups.groupName)")
                }

                Section {
                    TextField("Type \(phrase)", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await leave() }
                    } label: {
                        Text("Leave the group")
                    }
                    .disabled(typed.uppercased() != phrase || isWorking)
                }
            }
            .navigationTitle("Leave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func leave() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await groups.leaveGroup()
            dismiss()
            onLeft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
