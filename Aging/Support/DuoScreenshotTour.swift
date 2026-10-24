#if DEBUG
import Foundation

/// Unattended iPhone Duo capture (`gh-sim launch --device 'iPhone Duo'`).
/// DEBUG only, so none of it ships.
///
/// `-DuoTour` walks the main screens on a timer, because `simctl openurl`
/// raises a confirmation alert on iOS 27 and the capture job cannot tap.
/// `-DuoRoutes a,b` is the walk while folded and `-DuoRoutesRegular a,b`
/// while split (the inner display). `-DuoTourFirst <s>` is the delay before
/// the first route and `-DuoTourStep <s>` the dwell on each. The walk
/// repeats, and restarts when the panes split or join, so each display gets
/// all of it. Every step is logged as a `DUOTOUR` line, which maps the
/// captures to routes.
///
/// A route is `tab` or `tab+person` or `tab+person.screen`: `tab` is
/// `today`, `care`, `sharing` or `settings`; `person` matches a relationship
/// ("mom", "dad"); `screen` is `card` (the emergency card) or a
/// `CareFeature` raw value pushed on that person's hub. No `+` leaves Care on
/// its list.
///
/// `-DuoScreen <route>` holds one route for the whole launch instead of the
/// walk. gh-sim `--screen` relaunches the app once per surface and shoots it
/// folded and unfolded, so that is how one run captures every surface.
enum DuoScreenshotTour {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var isEnabled: Bool { arguments.contains("-DuoTour") }

    /// The one route this launch shows, or `nil` to walk them.
    static var screen: Route? { value("-DuoScreen").map(Route.init) }

    static func routes(split: Bool) -> [Route] {
        let list = value(split ? "-DuoRoutesRegular" : "-DuoRoutes")
            ?? (split
                ? "today+mom,today+mom.card,sharing+mom.tasks,today+mom.visits,today+mom.vitals"
                : "today,care+mom,care+mom.card")
        return list.split(separator: ",").map { Route(String($0)) }
    }

    static var firstDelay: Double { value("-DuoTourFirst").flatMap(Double.init) ?? 3 }
    static var step: Double { value("-DuoTourStep").flatMap(Double.init) ?? 10 }

    private static func value(_ key: String) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    struct Route {
        let name: String
        let tab: RootView.Tab
        let person: String?
        let screen: String?

        init(_ name: String) {
            self.name = name
            let parts = name.split(separator: "+", maxSplits: 1).map(String.init)
            switch parts.first {
            case "care": tab = .people
            case "sharing": tab = .family
            case "settings": tab = .settings
            default: tab = .today
            }
            let target = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
            person = target.first
            screen = target.count > 1 ? target[1] : nil
        }

        private init(name: String, tab: RootView.Tab, person: String?, screen: String?) {
            self.name = name
            self.tab = tab
            self.person = person
            self.screen = screen
        }

        /// The same route on the person's hub, without the screen it pushes.
        var hub: Route { Route(name: name, tab: tab, person: person, screen: nil) }

        /// Folded there is one screen at a time, so a route about a person
        /// opens it on the Care tab, where the split shows it beside the tab.
        var folded: Route {
            person == nil ? self : Route(name: name, tab: .people, person: person, screen: screen)
        }

        /// Writes the route into the navigator, which is all either layout
        /// reads its tab and Care stack from.
        @MainActor
        func apply(to navigator: AppNavigator, people: [Person]) {
            navigator.tab = tab
            guard let person,
                  let match = people.first(where: { $0.relationship.lowercased() == person })
            else {
                navigator.carePath = []
                navigator.careHub = HubRoute()
                return
            }
            navigator.carePath = [match.id]
            navigator.careHub = HubRoute(
                feature: screen.flatMap(CareFeature.init(rawValue:)),
                showsEmergencyCard: screen == "card"
            )
        }
    }
}
#endif
