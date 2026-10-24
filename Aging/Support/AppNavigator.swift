import Foundation
import Observation

/// Which tab is showing.
///
/// Lifted out of `RootView` so a screen inside one tab can send someone to
/// another one. The setup checklist needs exactly this: "Invite the family"
/// only ever appears when there is no group, and the invite lives on the Family
/// tab, which is a peer of the tab the checklist is on and cannot be pushed
/// onto its stack. A checklist row that leads nowhere is worse than no row.
@Observable
@MainActor
final class AppNavigator {
    var tab: RootView.Tab = .today

    /// Set by whoever is about to switch to Sharing, so the Sharing tab can open
    /// the invite sheet on arrival rather than leaving someone on a screen
    /// wondering which button they were sent for.
    var wantsInvite = false
    var pendingInviteCode = ""
    var wantsJoin = false

    /// The Care stack: whose record is open, and what is pushed on it.
    ///
    /// Held here rather than in `PeopleView` because unfolding an iPhone Duo
    /// moves Care out of the tab bar into its own pane beside the fold, which
    /// builds a new `PeopleView`. This is what reopens it where it was, in
    /// either direction.
    var carePath: [UUID] = []
    var careHub = HubRoute()

    func showFamilyInvite() {
        wantsInvite = true
        tab = .family
    }

    func showJoinInvite(code: String) {
        pendingInviteCode = code
        wantsJoin = true
        tab = .family
    }
}

/// What a person's hub has pushed. One value, so a whole route can be handed
/// to the hub and restored in one write.
struct HubRoute: Hashable {
    var feature: CareFeature?
    var showsEmergencyCard = false
}

/// What the Care pane of the unfolded iPhone Duo shows as its root.
///
/// Folded, Care is a stack: the list, a person's hub pushed on it, a screen
/// pushed on that. Split, the pane sits beside the fold as a detail column
/// and shows the same `AppNavigator` state as one root screen, so it never
/// carries a back button against the fold. Its record menu moves between
/// them (`CareRecordPane`). Read from the same two values either way, so
/// folding or unfolding lands on the same screen.
enum CarePaneScreen: Equatable {
    case people
    case hub(UUID)
    case feature(UUID, CareFeature)
    case emergencyCard(UUID)

    /// A person who is gone (deleted on another phone) falls back to the list.
    static func resolve(path: [UUID], route: HubRoute, personIDs: Set<UUID>) -> CarePaneScreen {
        guard let id = path.last, personIDs.contains(id) else { return .people }
        if route.showsEmergencyCard { return .emergencyCard(id) }
        if let feature = route.feature, menuFeatures.contains(feature) { return .feature(id, feature) }
        return .hub(id)
    }

    /// Every hub tile that opens a screen, in the hub's order. Medications
    /// are the hub's own list and health details is a sheet.
    static let menuFeatures: [CareFeature] =
        (PersonDetailView.everyday + PersonDetailView.records).filter { $0 != .healthDetails }
}
