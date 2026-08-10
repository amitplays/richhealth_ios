import SwiftUI
import StoreKit

/// Pro upgrade surface (Android ProUpgradeDialog) — now backed by StoreKit 2 IAP.
/// Plans + prices come from App Store Connect; on purchase the signed transaction is
/// verified by the backend (POST /api/payment/apple/verify) which flips the user to Pro.
struct PaywallView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitManager.shared
    @State private var didPurchase = false

    private let features: [(icon: String, title: String, detail: String)] = [
        ("bubble.left.and.text.bubble.right", "Unlimited AI chat", "No monthly session limits — chat as much as you need"),
        ("waveform.and.magnifyingglass", "Medical report analysis", "AI-powered analysis of uploaded medical documents"),
        ("chart.bar.xaxis", "Advanced health analysis", "Deep health trend analysis and personalized insights"),
        ("fork.knife", "Unlimited NutriCheck", "Check any food without daily limits"),
        ("brain.head.profile", "Dietary insights", "Ongoing personalized dietary guidance"),
        ("person.2.fill", "Family plan", "Share Pro benefits with up to 5 family members")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header
                featureList
                plansSection
                restoreButton
                footer
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Glass bottom-drawer look — translucent material behind the sheet.
        .presentationBackground(.thinMaterial)
        .task { await store.loadProducts() }
        .onAppear { Analytics.shared.track(.paywallView) }
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.brandTeal)
            Text("RichHealth Pro")
                .font(.largeTitle.bold())
            Text("Upgrade to unlock all features and remove limits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(features, id: \.title) { feature in
                GlassCard {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: feature.icon)
                            .font(.title2)
                            .foregroundStyle(Theme.brandTeal)
                            .frame(width: Theme.IconSize.card, height: Theme.IconSize.card)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.subheadline.weight(.semibold))
                            Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    // MARK: - Plans

    @ViewBuilder
    private var plansSection: some View {
        if store.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.m)
        } else if store.products.isEmpty {
            Text("Plans are unavailable right now. Please try again shortly.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.l)
        } else {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(store.products, id: \.id) { product in
                    planCard(product)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
    }

    private func planCard(_ product: Product) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundStyle(Theme.brandTeal)
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(product.displayPrice)
                        .font(.title3.bold())
                }
                Button {
                    Analytics.shared.track(.subscribeTap, ["plan": product.id])
                    Task {
                        let ok = await store.purchase(product)
                        Analytics.shared.track(ok ? .purchaseSuccess : .purchaseFailed, ["plan": product.id])
                        if ok {
                            await appEnv.auth.refreshProfile()
                            didPurchase = true
                        }
                    }
                } label: {
                    Text("Subscribe")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandTeal)
                .disabled(store.isPurchasing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
