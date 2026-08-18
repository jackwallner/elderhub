import Foundation
import StoreKit
import os
@preconcurrency import RevenueCat

/// One purchasable plan, decoupled from where it came from.
///
/// On device the source is a RevenueCat `Package`. On the simulator RevenueCat is
/// never configured (see `configureIfNeeded`), so plans come straight from
/// StoreKit Testing instead. Without this the paywall can only ever render its
/// empty state on a sim, which makes the layout unverifiable.
/// How long one purchase covers, which is the fact the paywall needs in order
/// to compare two prices honestly. Derived from the product id rather than
/// parsed out of a localized string.
enum PlanPeriod: Sendable {
    case monthly, yearly, lifetime

    /// Months covered. Nil for lifetime, which has no per-month price and must
    /// not be given a fake one.
    var months: Int? {
        switch self {
        case .monthly: return 1
        case .yearly: return 12
        case .lifetime: return nil
        }
    }
}

struct PlanOption: Identifiable, Sendable {
    let id: String
    let title: String
    /// Already localized by StoreKit. Never rebuilt from `amount`.
    let price: String
    /// The raw figure, so the paywall can divide it. Kept alongside the
    /// formatted string rather than replacing it: currency formatting is
    /// StoreKit's job and getting it wrong is a compliance problem, not a
    /// cosmetic one.
    let amount: Decimal
    let currencyCode: String
    let period: PlanPeriod
    let package: Package?

    /// "$4.08 / month" for a yearly plan, so the two subscriptions can be
    /// compared without arithmetic. Nil for a one-off purchase.
    func perMonthLabel() -> String? {
        guard let months = period.months, months > 1, amount > 0 else { return nil }
        let perMonth = amount / Decimal(months)
        return perMonth.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
    }
}

enum ProProduct {
    static let monthly = "com.jackwallner.aging.pro.monthly"
    static let yearly = "com.jackwallner.aging.pro.yearly"
    static let lifetime = "com.jackwallner.aging.pro.lifetime"
    static let all: [String] = [monthly, yearly, lifetime]

    static func title(for productID: String) -> String {
        switch productID {
        case monthly: return "Monthly"
        case yearly: return "Yearly"
        case lifetime: return "Lifetime"
        default: return "Elderhub Plus"
        }
    }

    static func period(for productID: String) -> PlanPeriod {
        switch productID {
        case yearly: return .yearly
        case lifetime: return .lifetime
        default: return .monthly
        }
    }

    /// Cheapest commitment first, so the list reads the same way every time
    /// regardless of what order RevenueCat hands the packages back in.
    static func order(for productID: String) -> Int {
        all.firstIndex(of: productID) ?? all.count
    }
}

enum RevenueCatConfig {
    static let apiKey = "appl_dvyPWLaZxKyjLUrFVzDynNGjVGb"
    /// Entitlement identifier as configured on the RevenueCat dashboard. It is
    /// "Aging+" here, not the fleet-default "pro", so checking only "pro" would
    /// leave a paying customer locked out.
    static let proEntitlement = "Aging+"
    /// Kept so a purchase made against an alternate identifier still unlocks.
    static let fallbackEntitlements = ["pro", "AgingPro"]
}

/// Freemium gate. Every care feature is free for one person. Plus unlocks
/// additional people in the same care circle.
@MainActor
@Observable
final class StoreService: NSObject {
    static let shared = StoreService()

    private(set) var isPro: Bool = false
    private(set) var offerings: Offerings?
    private(set) var plans: [PlanOption] = []
    private(set) var isLoading: Bool = false

    private var isConfigured = false
    private var localOverride: Bool?
    private let log = Logger(subsystem: "com.jackwallner.aging", category: "store")

    private override init() {
        super.init()
    }

    /// Dev/sim escape hatch so paywalled screens can be driven without a purchase.
    func setLocalOverride(isPro value: Bool?) {
        localOverride = value
        if let value {
            isPro = value
        }
    }

    func start() {
        configureIfNeeded()
        Task {
            await identify()
            await refresh()
        }
    }

    /// Ties the RevenueCat customer to the Supabase user id, which is what makes
    /// the webhook able to find the payer's group. Without this the webhook sees
    /// an anonymous RevenueCat id, has nobody to credit, and the family silently
    /// never gets Plus.
    func identify() async {
        guard isConfigured, let userID = AuthService.shared.userID else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(userID.uuidString)
            apply(info)
        } catch {
            log.error("logIn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() async {
        if let localOverride {
            isPro = localOverride
        }

        isLoading = true
        defer { isLoading = false }

        guard isConfigured else {
            // Simulator: no RevenueCat, so fall back to StoreKit Testing products.
            await loadStoreKitTestingPlans()
            return
        }

        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
            let offerings = try await Purchases.shared.offerings()
            self.offerings = offerings
            plans = (offerings.current?.availablePackages ?? []).map {
                PlanOption(
                    id: $0.storeProduct.productIdentifier,
                    title: ProProduct.title(for: $0.storeProduct.productIdentifier),
                    price: $0.storeProduct.localizedPriceString,
                    amount: $0.storeProduct.price,
                    currencyCode: $0.storeProduct.currencyCode ?? Locale.current.currency?.identifier ?? "USD",
                    period: ProProduct.period(for: $0.storeProduct.productIdentifier),
                    package: $0
                )
            }
            .sorted { ProProduct.order(for: $0.id) < ProProduct.order(for: $1.id) }
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Populates `plans` from the local `.storekit` catalog. Only ever runs when
    /// RevenueCat is not configured, i.e. on the simulator.
    private func loadStoreKitTestingPlans() async {
        do {
            let products = try await Product.products(for: ProProduct.all)
            let order = ProProduct.all
            plans = products
                .sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
                .map {
                    PlanOption(
                        id: $0.id,
                        title: ProProduct.title(for: $0.id),
                        price: $0.displayPrice,
                        amount: $0.price,
                        currencyCode: $0.priceFormatStyle.currencyCode,
                        period: ProProduct.period(for: $0.id),
                        package: nil
                    )
                }
        } catch {
            log.error("StoreKit Testing load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase(_ plan: PlanOption) async throws {
        guard let package = plan.package else {
            // StoreKit Testing render only; there is nothing to charge against.
            return
        }
        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { return }
        apply(result.customerInfo)
        await propagateToGroup()
    }

    func restore() async throws {
        guard isConfigured else { return }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        await propagateToGroup()
    }

    /// The webhook is what actually writes `group_billing`, and it arrives
    /// server-to-server a moment later. This pulls the row so the rest of the
    /// family's entitlement is current on the payer's own device too, and so
    /// `hasPlus` is right if they hand the phone to someone.
    private func propagateToGroup() async {
        // Give the webhook a beat to land. Not load-bearing: the payer is
        // already unlocked locally either way, and the next foreground refresh
        // picks it up regardless.
        try? await Task.sleep(for: .seconds(2))
        await GroupService.shared.refreshBilling()
    }

    private func apply(_ info: CustomerInfo) {
        guard localOverride == nil else { return }
        let identifiers = [RevenueCatConfig.proEntitlement] + RevenueCatConfig.fallbackEntitlements
        isPro = identifiers.contains { info.entitlements[$0]?.isActive == true }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        // Agent/simulator runs must never create customers in the production
        // RevenueCat project. Use local UI state and StoreKit Testing instead.
        //
        // `#else` rather than an early `return`, which made every line after it
        // unreachable on a simulator build and so warned on every such build,
        // burying anything else the compiler had to say.
        #if !targetEnvironment(simulator)
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        isConfigured = true
        #endif
    }
}
