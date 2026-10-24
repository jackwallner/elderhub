import SwiftUI

/// One person's record as the root of the unfolded iPhone Duo's Care pane:
/// their hub, or one of the screens its tiles open, in place.
///
/// Folded these are pushed, and that is right on a phone. Beside the fold
/// the pane is a detail column, and a back chevron there reads as a screen
/// that slid in from the tabs (visual review, 2026-10-23). So the pane
/// swaps its root instead, and the record menu at its leading edge (the
/// person's initials) moves between the overview, every screen, and the
/// other people in the circle.
struct CareRecordPane: View {
    let person: Person
    let people: [Person]
    @Binding var route: HubRoute

    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        screen
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    recordMenu
                }
            }
    }

    @ViewBuilder
    private var screen: some View {
        if route.showsEmergencyCard {
            EmergencyCardView(person: person)
        } else if let feature = route.feature, CarePaneScreen.menuFeatures.contains(feature) {
            CareFeatureScreen(feature: feature, person: person)
        } else {
            PersonDetailView(person: person, route: $route, pushesRoute: false)
        }
    }

    private var recordMenu: some View {
        Menu {
            Picker("Show", selection: $route) {
                Label("Overview", systemImage: "square.grid.2x2").tag(HubRoute())
                ForEach(CarePaneScreen.menuFeatures) { feature in
                    Label(feature.title, systemImage: feature.symbol).tag(HubRoute(feature: feature))
                }
                Label("Emergency card", systemImage: "cross.case").tag(HubRoute(showsEmergencyCard: true))
            }
            .pickerStyle(.inline)

            Section {
                Picker("Person", selection: personSelection) {
                    ForEach(people) { person in
                        Text(person.displayLabel).tag(person.id)
                    }
                }
                .pickerStyle(.inline)

                Button {
                    route = HubRoute()
                    navigator.carePath = []
                } label: {
                    Label("All people", systemImage: "person.2")
                }
            }
        } label: {
            Text(person.initials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(person.color)
                .frame(width: 34, height: 34)
                .background(person.color.opacity(0.18), in: Circle())
        }
        .accessibilityLabel("\(person.displayLabel)'s record")
        .accessibilityHint("Switches between the overview, each screen and the other people.")
        .accessibilityIdentifier("care-pane.record-menu")
    }

    /// Another person opens on their overview, as tapping them in the list would.
    private var personSelection: Binding<UUID> {
        Binding(
            get: { person.id },
            set: { id in
                route = HubRoute()
                navigator.carePath = [id]
            }
        )
    }
}
