import SwiftUI

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var restoreResult: String?
    @State private var selectedPlanID: String?

    private var plans: [PlanOption] {
        store.plans
    }

    /// What "Continue" buys. Defaults to the yearly plan, which is both the
    /// best value and the one the savings line is measured against; falls back
    /// to whatever loaded if that plan is missing.
    private var selectedPlan: PlanOption? {
        if let selectedPlanID, let match = plans.first(where: { $0.id == selectedPlanID }) {
            return match
        }
        return plans.first { $0.period == .yearly } ?? plans.first
    }

    /// The monthly plan's price, used as the baseline for the yearly plan's
    /// savings line. Nil when there is no monthly plan to compare against, and
    /// the savings badge then simply does not appear rather than being invented.
    private var monthlyBaseline: Decimal? {
        plans.first { $0.period == .monthly }.map(\.amount)
    }

    /// Whole per cent saved by paying yearly. Rounded down so the badge can
    /// never overstate it.
    private func savingsPercent(for plan: PlanOption) -> Int? {
        guard plan.period == .yearly,
              let monthly = monthlyBaseline,
              monthly > 0 else { return nil }
        let twelveMonths = monthly * 12
        guard plan.amount < twelveMonths else { return nil }
        let saved = (twelveMonths - plan.amount) / twelveMonths * 100
        let percent = Int(truncating: NSDecimalNumber(decimal: saved))
        return percent > 0 ? percent : nil
    }

    private func caption(for plan: PlanOption) -> String? {
        switch plan.period {
        case .monthly: return "Cancel any time"
        case .yearly: return plan.perMonthLabel().map { "\($0) a month, billed yearly" }
        case .lifetime: return "One payment, no renewal"
        }
    }

    private enum LegalLinks {
        static let privacy = URL(string: "https://jackwallner.github.io/elderhub/privacy-policy.html")!
        static let terms = URL(string: "https://jackwallner.github.io/elderhub/terms.html")!
        static let eula = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.badge.key")
                            .font(.system(size: 46))
                            .foregroundStyle(.tint)
                        Text("Add another person")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 14) {
                        benefit("person.2", "Keep care records for Mom, Dad, a partner, or anyone else")
                        benefit("person.3", "Everyone stays in one care circle")
                        benefit("person.badge.plus", "Invite as many family helpers as you need, with no seat fees")
                        benefit("checkmark.seal", "Every care feature is included for every person")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)

                    if plans.isEmpty {
                        ProgressView()
                            .padding(.vertical, 30)
                            .accessibilityIdentifier("paywall.loading")
                    } else {
                        // Pick, then buy. Three identically prominent buttons
                        // showing a title and a raw price made the user do the
                        // arithmetic and guess which was the best value, and
                        // gave them no way to look at a choice before
                        // committing to it.
                        VStack(spacing: 10) {
                            ForEach(plans) { plan in
                                planRow(plan)
                            }
                        }

                        Button {
                            if let plan = selectedPlan { purchase(plan) }
                        } label: {
                            Text(isPurchasing ? "Working…" : "Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPurchasing || selectedPlan == nil)
                        .accessibilityIdentifier("paywall.continue")
                    }

                    Text("Monthly and yearly plans include a 1-week free trial for eligible new subscribers. After the trial, the displayed price is charged through your Apple ID and the selected plan renews automatically each month or year unless cancelled at least 24 hours before the period ends. Lifetime is a one-time purchase and does not renew. Manage or cancel subscriptions in your Apple ID settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Restore purchases") {
                        Task { await restore() }
                    }
                    .font(.footnote)
                    .disabled(isRestoring)

                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Link("Privacy Policy", destination: LegalLinks.privacy)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Link("Terms of Use", destination: LegalLinks.terms)
                        }
                        Link("Apple Standard EULA", destination: LegalLinks.eula)
                    }
                    .font(.footnote)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .alert(
                "Restore purchases",
                isPresented: Binding(get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } })
            ) {
                Button("OK", role: .cancel) { restoreResult = nil }
            } message: {
                Text(restoreResult ?? "")
            }
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
            Spacer()
        }
    }

    /// Says which of the three things happened, rather than the `try?` that
    /// made a failed restore, an empty restore and a working one all look like
    /// nothing at all.
    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            if store.isPro {
                dismiss()
            } else {
                restoreResult = "No previous purchase was found on this Apple ID."
            }
        } catch {
            restoreResult = "Couldn't reach the App Store. \(error.localizedDescription)"
        }
    }

    /// One plan, as something you can look at before you buy it: what it is,
    /// what it costs, what that works out to, and whether it is the cheapest.
    private func planRow(_ plan: PlanOption) -> some View {
        let isSelected = selectedPlan?.id == plan.id
        return Button {
            selectedPlanID = plan.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let percent = savingsPercent(for: plan) {
                            Text("Save \(percent)%")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    if let caption = caption(for: plan) {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(plan.price)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .accessibilityIdentifier("paywall.plan.\(plan.id)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func purchase(_ plan: PlanOption) {
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await store.purchase(plan)
                if store.isPro { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    PaywallView()
        .environment(StoreService.shared)
}
