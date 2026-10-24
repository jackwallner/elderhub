import SwiftUI

/// One person's record as the root of the unfolded iPhone Duo's Care pane:
/// their hub, or one of the screens its tiles open, in place.
///
/// Folded these are pushed, and that is right on a phone. Beside the fold
/// the pane is a detail column, and a back chevron there reads as a screen
/// that slid in from the tabs (visual review, 2026-10-23). So the pane
/// swaps its root instead, and the record menu at its leading edge (the
/// person's initials and the screen's name) moves between the overview,
/// every screen, and the other people in the circle.
struct CareRecordPane: View {
    let person: Person
    let people: [Person]
    @Binding var route: HubRoute

    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        screen
            // The menu carries the screen's name, so every root in the pane
            // titles itself the same way, leading. Centred bar titles moved
            // to the leading edge whenever one did not fit beside the
            // trailing buttons and the status bar ("Appointments", review
            // 2026-10-23), so the pane's screens did not match each other.
            .barTitleInContent(true)
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
            HStack(spacing: 8) {
                Text(person.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(person.color)
                    .frame(width: 28, height: 28)
                    .background(person.color.opacity(0.18), in: Circle())
                Text(screenTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(screenTitle), \(person.displayLabel)'s record")
        .accessibilityHint("Switches between the overview, each screen and the other people.")
        .accessibilityIdentifier("care-pane.record-menu")
    }

    /// The hub is the person; every other screen goes by its tile's name.
    private var screenTitle: String {
        // Short, so the card's Share and Edit stay beside it rather than
        // folding into an overflow menu; the card's header names it in full.
        if route.showsEmergencyCard { return "ER card" }
        if let feature = route.feature, CarePaneScreen.menuFeatures.contains(feature) {
            return feature.title
        }
        return person.displayLabel
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
