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
