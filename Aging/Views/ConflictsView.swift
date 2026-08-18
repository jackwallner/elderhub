import SwiftUI

/// The records two people changed at once, and the choice between them.
///
/// Settings has counted these since sync shipped ("1 change needs a look") with
/// nowhere to go and nothing to do, which is the worst version of this feature:
/// the app tells someone a health record needs attention and then declines to
/// say which one. The conflict rule itself is right and is not changed here.
/// Last-writer-wins is not acceptable for a drug dosage, so the engine keeps
/// both sides and asks. This screen is the asking.
struct ConflictsView: View {
    @Environment(SyncCoordinator.self) private var sync

    @State private var conflicts: [SyncEngine.ConflictSummary] = []
    @State private var isLoaded = false
    @State private var working: UUID?

    var body: some View {
        List {
            if conflicts.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(
                            isLoaded ? "Nothing to review" : "Checking",
                            systemImage: isLoaded ? "checkmark.circle" : "clock"
                        )
                    } description: {
                        if isLoaded {
                            Text("Every change on this phone has reached the rest of your care circle.")
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(conflicts) { conflict in
                        row(conflict)
                    }
                } header: {
                    Text(conflicts.count == 1 ? "1 change" : "\(conflicts.count) changes")
                } footer: {
                    // Says plainly what has and has not happened, because the
                    // worry this screen answers is "have I lost something".
                    Text("Somebody else edited these while this phone was offline. Nothing has been thrown away: your version is still here and is what you are seeing everywhere else in the app.")
                }
            }
        }
        .navigationTitle("Needs a Look")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ conflict: SyncEngine.ConflictSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conflict.title)
                    .font(.body.weight(.medium))
                Text(subtitle(for: conflict))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Keep mine") {
                    resolve(conflict.id, keepLocal: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Use theirs") {
                    resolve(conflict.id, keepLocal: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                if working == conflict.id {
                    ProgressView().controlSize(.small)
                }
            }
            .disabled(working != nil)
            // The buttons are the row's content, so the row must not also be
            // one big tappable thing that swallows them.
            .buttonStyle(.automatic)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("conflict.\(conflict.id.uuidString)")
    }

    private func subtitle(for conflict: SyncEngine.ConflictSummary) -> String {
        var parts = [conflict.kindLabel]
        if !conflict.personName.isEmpty { parts.append(conflict.personName) }
        parts.append("your edit \(conflict.localUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
        return parts.joined(separator: " · ")
    }

    private func resolve(_ id: UUID, keepLocal: Bool) {
        working = id
        Task {
            defer { working = nil }
            if keepLocal {
                await sync.resolveKeepingLocal(id: id)
            } else {
                await sync.resolveTakingRemote(id: id)
            }
            await load()
        }
    }

    private func load() async {
        conflicts = await sync.conflicts()
        await sync.refreshConflictCount()
        isLoaded = true
    }
}

#Preview {
    NavigationStack {
        ConflictsView()
    }
    .environment(SyncCoordinator.shared)
}
