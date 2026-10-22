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
struct HubRoute: Equatable {
    var feature: CareFeature?
    var showsEmergencyCard = false
}
