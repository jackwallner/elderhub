import SwiftUI

/// The plan picker, and the app's only trial pitch.
///
/// It used to sell "Add another person" and mention the free week once, in the
/// middle of the legal paragraph under the buttons, which is the one place a
/// reader skips. Both subscriptions carry a real 1-week trial, so the trial —
/// not the feature and not the price — is the offer, and it now leads the
/// headline, the plan captions, the CTA and a timeline that says exactly when
/// money moves. Every one of those lines is gated on
/// `StoreService.eligibleTrialDays(for:)`, so an account that has already used
/// its trial sees an honest subscribe pitch instead.
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

    /// Trial length to advertise for the plan the user is about to buy, or nil
    /// when there is none they would actually receive. Everything on this
    /// screen that says "free" reads this, never `plan.trialDays` directly.
    private var selectedTrialDays: Int? {
        selectedPlan.flatMap { store.eligibleTrialDays(for: $0) }
    }

    /// The monthly plan, which the yearly plan's savings line is measured
    /// against. Nil when there is no monthly plan, and the badge then simply
    /// does not appear rather than being invented.
    private var monthlyBaseline: PlanOption? {
        plans.first { $0.period == .monthly }
    }

    private func savingsPercent(for plan: PlanOption) -> Int? {
        plan.savingsPercent(against: monthlyBaseline)
    }

    /// The plan row's second line. Leads with the trial when there is one,
    /// because that is what the reader is comparing; the billed figure stays on
    /// the right of the row either way, so the per-month maths never displaces
    /// the amount that is actually charged.
    private func caption(for plan: PlanOption) -> String? {
        let trialPrefix = store.eligibleTrialDays(for: plan).map { "\($0) days free, then " } ?? ""
        switch plan.period {
        case .monthly:
            return trialPrefix.isEmpty
                ? "Cancel any time"
                : "\(trialPrefix)\(plan.price) a month"
        case .yearly:
            guard let perMonth = plan.perMonthLabel() else {
                return trialPrefix.isEmpty ? "Billed yearly" : "\(trialPrefix)\(plan.price) a year"
            }
            return "\(trialPrefix)\(perMonth) a month, billed yearly"
        case .lifetime:
            // Never trial or subscription language, whatever is selected above.
            return "One payment, no renewal"
        }
    }

    private var headline: String {
        guard let days = selectedTrialDays else { return "Add another person" }
        return "Free for \(days) days"
    }

    /// Keeps the reason the sheet opened visible even when the trial takes the
    /// headline: the reader tapped "add person", not "subscribe".
    private var subhead: String {
        selectedTrialDays == nil
            ? "Care records for everyone you look after, in one circle."
            : "Add everyone you look after. Full access from today, nothing to pay now."
    }

    private var ctaTitle: String {
        guard let plan = selectedPlan else { return "Continue" }
        if isPurchasing { return "Working…" }
        if let days = selectedTrialDays { return "Start My \(days)-Day Free Trial" }
        if plan.period == .lifetime { return "Unlock Lifetime" }
        return "Subscribe"
    }

    /// Apple's required disclosure, rebuilt for the selected plan so the billed
    /// amount, the period and the trial always match the row above.
    private var disclosureText: String? {
        guard let plan = selectedPlan else { return nil }
        if plan.period == .lifetime {
            return "\(plan.price) once. Lifetime access, no subscription and no renewal."
        }
        let unit = plan.period == .yearly ? "year" : "month"
        let renewal = "Cancel at least 24 hours before the period ends to avoid renewal. Manage or cancel in your Apple ID settings."
        if let days = selectedTrialDays {
            return "Free for \(days) days, then \(plan.price) per \(unit), renewing automatically. \(renewal)"
        }
        return "\(plan.price) per \(unit), renewing automatically. \(renewal)"
    }

    private enum LegalLinks {
        static let privacy = URL(string: "https://jackwallner.github.io/elderhub/privacy-policy.html")!
        static let terms = URL(string: "https://jackwallner.github.io/elderhub/terms.html")!
        static let eula = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: selectedTrialDays == nil ? "person.2.badge.key" : "gift")
                            .font(.system(size: 46))
                            .foregroundStyle(.tint)
                        Text(headline)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(subhead)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    // Three rows, not a feature catalogue: this screen has to
                    // reach the plan cards above the fold on the smallest phone.
                    //
                    // Every row has to be a thing this purchase actually buys.
                    // "No seat fees" was here and is not one: siblings join a
                    // free circle without paying too, so selling it as a Plus
                    // benefit is charging for something already given away, and
                    // a reader who works that out stops believing the other two
                    // rows. It still belongs in Settings and on the site as the
                    // reassurance it is. What a second person really unlocks is
                    // the Everyone view, which does not exist below two.
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("person.2", "Keep care records for Mom, Dad, a partner, or anyone else")
                        benefit("sun.max", "One Today screen that answers for everyone, not one person at a time")
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

                        if let days = selectedTrialDays {
                            TrialTimeline(trialDays: days, priceLabel: selectedPlan?.price)
                        }
                    }
                }
                .padding(24)
            }
            // The purchase area is pinned rather than scrolled to, so the
            // decision is always under the reader's thumb and does not move
            // when the plan changes or an error appears.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                purchaseFooter
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .task {
                // Eligibility can change between launches (a trial started on
                // another device), so it is re-resolved every time the sheet
                // opens rather than trusted from app start.
                if store.plans.isEmpty {
                    await store.refresh()
                } else {
                    await store.refreshIntroEligibility()
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

    /// CTA, reassurance, disclosure and legal, all at the point of purchase.
    /// The variable text sits in one min-height slot that grows upward, so the
    /// button itself never jumps as plans, errors and states change under it.
    private var purchaseFooter: some View {
        VStack(spacing: 8) {
            if !plans.isEmpty {
                Button {
                    if let plan = selectedPlan { purchase(plan) }
                } label: {
                    Text(ctaTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing || selectedPlan == nil)
                .accessibilityIdentifier("paywall.continue")

                if selectedTrialDays != nil {
                    Text("No payment now · Cancel any time")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                // Error takes the disclosure's slot rather than stacking with
                // it: two paragraphs appearing at once is what pushed the
                // button off the screen before.
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if let disclosureText {
                    Text(disclosureText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button("Restore") { Task { await restore() } }
                        .disabled(isRestoring)
                    Text("·").foregroundStyle(.secondary)
                    Link("Terms", destination: LegalLinks.terms)
                    Text("·").foregroundStyle(.secondary)
                    Link("Privacy", destination: LegalLinks.privacy)
                    Text("·").foregroundStyle(.secondary)
                    Link("EULA", destination: LegalLinks.eula)
                }
                .font(.caption)
            }
            .frame(minHeight: 64, alignment: .top)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
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
                        // Exactly one badge on the whole list, so there is no
                        // contest between "best value" and "free trial" for
                        // the reader's attention. The trial rides the caption.
                        if let percent = savingsPercent(for: plan) {
                            Text("Save \(percent)%")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(.green)
                                // The badge is the row's only differentiator, so
                                // it must not be the thing that gets compressed
                                // away when the caption grew a trial clause.
                                .fixedSize()
                                .layoutPriority(1)
                        }
                    }
                    if let caption = caption(for: plan) {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

/// What happens on which day, which is the question people are actually
/// declining a trial over: not the price, but whether they will be charged
/// without noticing. Every line is true — access starts now, the reminder is
/// Apple's rather than ours (this app schedules no billing notification), and
/// the final day names the real amount.
private struct TrialTimeline: View {
    let trialDays: Int
    let priceLabel: String?

    private var reminderDay: Int { max(trialDays - 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How the free trial works")
                .font(.subheadline.bold())
                .padding(.bottom, 12)

            step(
                symbol: "lock.open",
                title: "Today: everything unlocks",
                detail: "Add the people you look after and use every feature.",
                isLast: false
            )
            step(
                symbol: "bell",
                title: "Day \(reminderDay): a heads-up",
                detail: "The App Store reminds you before the trial ends.",
                isLast: false
            )
            step(
                symbol: "checkmark.seal",
                title: "Day \(trialDays): the trial ends",
                detail: priceLabel.map { "Billed \($0) unless you cancel first." }
                    ?? "You are only billed if you keep it.",
                isLast: true
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "How the free trial works. Today, everything unlocks. Day \(reminderDay), the App Store reminds you. Day \(trialDays), the trial ends and you are billed unless you cancel."
        )
    }

    private func step(symbol: String, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    PaywallView()
        .environment(StoreService.shared)
}
