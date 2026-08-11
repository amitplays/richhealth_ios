import SwiftUI
import StoreKit

/// Pro upgrade surface. Three-pill plan selector (Plus · Pro · Ultra) — feature lists,
/// discount copy and "most popular" come from the backend (GET /api/payment/plans, the
/// single source of truth shared with Android); the price shown/charged comes from
/// StoreKit (App Store Connect). On purchase the signed transaction is verified by the
/// backend (POST /api/payment/apple/verify) which flips the user to Pro.
struct PaywallView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitManager.shared

    @State private var plans: [PaymentService.PaymentPlan] = []
    @State private var currentTier: String = "free"
    @State private var selectedTier: String = "pro"
    @State private var plansLoading = true
    @State private var didPurchase = false
    @State private var showManage = false

    private let service = PaymentService()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header
                if plansLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl)
                } else if plans.isEmpty {
                    unavailable
                } else {
                    planPills
                    selectedPlanCard
                    subscribeButton
                    restoreButton
                    if currentTier != "free" { manageButton }
                }
                footer
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            async let p: Void = store.loadProducts()
            async let q: Void = loadPlans()
            _ = await (p, q)
        }
        .onAppear { Analytics.shared.track(.paywallView) }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .alert("Purchase Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: didPurchase) { _, done in if done { dismiss() } }
    }

    // MARK: - Data

    private func loadPlans() async {
        plansLoading = true
        defer { plansLoading = false }
        guard let resp = try? await service.fetchPlans() else { return }
        plans = resp.plans
        currentTier = resp.currentTier ?? "free"
        // Default the selection to the most-popular plan (falls back to pro / first).
        if let popular = plans.first(where: { $0.isMostPopular == true }) {
            selectedTier = popular.tierKey
        } else if plans.contains(where: { $0.tierKey == "pro" }) {
            selectedTier = "pro"
        } else if let first = plans.first {
            selectedTier = first.tierKey
        }
    }

    private var selectedPlan: PaymentService.PaymentPlan? {
        plans.first { $0.tierKey == selectedTier }
    }

    private func product(for plan: PaymentService.PaymentPlan) -> Product? {
        store.products.first { $0.id == plan.appleProductID }
    }

    /// StoreKit localized price (what Apple charges); falls back to backend INR if the
    /// App Store product hasn't loaded yet.
    private func priceText(for plan: PaymentService.PaymentPlan) -> String {
        product(for: plan)?.displayPrice ?? "₹\(plan.price)"
    }

    private func durationText(for plan: PaymentService.PaymentPlan) -> String {
        switch plan.durationMonths {
        case 12: return "Billed yearly"
        case 1:  return "Billed monthly"
        case let m?: return "Billed every \(m) months"
        default: return ""
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brandTeal)
            Text("RichHealth Pro")
                .font(.largeTitle.bold())
            Text("Choose a plan to unlock premium health features.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.l)
    }

    // MARK: - 3-pill selector

    private var planPills: some View {
        Picker("Plan", selection: $selectedTier) {
            ForEach(plans) { plan in
                Text(plan.tierKey.capitalized).tag(plan.tierKey)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .sensoryFeedback(.selection, trigger: selectedTier)
    }

    // MARK: - Selected plan card

    @ViewBuilder
    private var selectedPlanCard: some View {
        if let plan = selectedPlan {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    // Name + most-popular / current badges
                    HStack(spacing: Theme.Spacing.s) {
                        Text(plan.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.brandTeal)
                        Spacer()
                        if plan.isMostPopular == true {
                            StatusPill(text: "MOST POPULAR", level: .green)
                        }
                        if currentTier == plan.tierKey {
                            StatusPill(text: "Current")   // no level → brand-teal plan badge
                        }
                    }

                    // Price + discount
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(priceText(for: plan))
                            .font(.system(size: 34, weight: .bold))
                        VStack(alignment: .leading, spacing: 0) {
                            if !durationText(for: plan).isEmpty {
                                Text(durationText(for: plan))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let pct = plan.discountPercent, pct > 0 {
                                Text("\(pct)% off")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.brandTeal)
                            }
                        }
                    }
                    if let msg = plan.discountMessage, !msg.isEmpty {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }

                    Divider()

                    // Features (backend — shared with Android)
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ForEach(plan.features, id: \.self) { feature in
                            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.brandTeal)
                                Text(feature)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var subscribeButton: some View {
        if let plan = selectedPlan {
            let isCurrent = currentTier == plan.tierKey
            let prod = product(for: plan)
            Button {
                guard let prod else { return }
                Analytics.shared.track(.subscribeTap, ["plan": plan.tierKey])
                Task {
                    let ok = await store.purchase(prod)
                    Analytics.shared.track(ok ? .purchaseSuccess : .purchaseFailed, ["plan": plan.tierKey])
                    if ok {
                        await appEnv.auth.refreshProfile()
                        didPurchase = true
                    }
                }
            } label: {
                Text(isCurrent ? "Your current plan"
                     : (prod == nil ? "Currently unavailable" : "Subscribe to \(plan.tierKey.capitalized)"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Theme.CornerRadius.button))
            .tint(Theme.brandTeal)
            .disabled(isCurrent || prod == nil || store.isPurchasing)
        }
    }

    private var restoreButton: some View {
        Button {
            Analytics.shared.track(.restore)
            Task {
                if await store.restore() {
                    await appEnv.auth.refreshProfile()
                    didPurchase = true
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(Theme.brandTeal)
        }
        .disabled(store.isPurchasing)
    }

    private var manageButton: some View {
        Button {
            showManage = true
        } label: {
            Text("Manage Subscription")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var unavailable: some View {
        Text("Plans are unavailable right now. Please try again shortly.")
            .font(.subheadline).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.vertical, Theme.Spacing.xl)
    }

    private var footer: some View {
        Text("Subscriptions auto-renew until cancelled. Manage or cancel anytime in Settings → Apple ID → Subscriptions.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
    }
}

#Preview { PaywallView().environment(AppEnvironment()) }
