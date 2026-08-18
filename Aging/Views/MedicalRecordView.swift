import SwiftData
import SwiftUI

/// The medical half of a person's record, as a screen.
///
/// This used to be a menu that dropped out of the Today tab's "Medical" chip.
/// Every other chip in that row pushes a screen, so one that instead popped a
/// list of six words read as a mis-tap: the same tap gesture produced two
/// different kinds of thing, and the menu gave a caregiver no idea what was in
/// any of them before choosing. A pushed hub of the same tiles the person's
/// record already uses answers "what is in here" before the tap rather than
/// after it.
struct MedicalRecordView: View {
    let person: Person

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var pushed: CareFeature?
    @State private var isEditingDetails = false

    /// The same list `QuickAction.medical` publishes, so the chip and this
    /// screen can never drift apart.
    private var features: [CareFeature] { QuickAction.medical.members }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(features) { feature in
                        Button {
                            if feature == .healthDetails {
                                isEditingDetails = true
                            } else {
                                pushed = feature
                            }
                        } label: {
                            FeatureTile(
                                feature: feature,
                                detail: CareOverview.detail(for: feature, person: person),
                                isEmpty: CareOverview.isEmpty(feature, person: person)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("medical.\(feature.rawValue)")
                    }
                }
            } footer: {
                Text("Everything here is kept on this phone first, so it opens with no signal.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)
        }
        .navigationTitle("Medical")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushed) { feature in
            destination(for: feature)
        }
        .sheet(isPresented: $isEditingDetails) {
            PersonDetailsEditorSheet(person: person)
        }
    }

    @ViewBuilder
    private func destination(for feature: CareFeature) -> some View {
        switch feature {
        case .visits:
            VisitsView(person: person)
        case .vitals:
            VitalsView(person: person)
        case .incidents:
            CareEventsView(person: person)
        case .providers:
            ProvidersView(person: person)
        case .timeline:
            TimelineView(person: person)
        default:
            // Health details is a sheet; nothing else is in this menu.
            EmptyView()
        }
    }
}

#Preview {
    NavigationStack {
        MedicalRecordView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
