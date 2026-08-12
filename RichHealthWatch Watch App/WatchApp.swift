import SwiftUI

// MARK: - App entry

@main
struct RichHealthWatchApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// MARK: - Root — vertical paging (the modern watchOS pattern): one "moment" per page

struct RootView: View {
    var body: some View {
        TabView {
            TodayGlanceView()
            NutriCheckVoiceView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Small shared bits

/// The RichHealth logo, reused from the shared asset (add `AppLogo` to the watch asset catalog).
private struct BrandHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: WatchTheme.Spacing.s) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Page 1 — Today glance

struct TodayGlanceView: View {
    @State private var model = TodayGlanceModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                BrandHeader(title: "Today")

                if model.isLoading && model.metrics.isEmpty {
                    ProgressView().tint(WatchTheme.brandTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WatchTheme.Spacing.l)
                } else if let err = model.errorText {
                    RHGlassCard { Text(err).font(.footnote).foregroundStyle(.secondary) }
                } else {
                    ForEach(model.metrics) { m in
                        RHGlassCard {
                            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                                Text(m.label.uppercased())
                                    .font(.caption2).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(m.value)
                                        .font(.system(.title2, design: .rounded).weight(.semibold))
                                        .foregroundStyle(WatchTheme.brandTeal)
                                    Text(m.unit).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let asOf = model.asOfText {
                        Text(asOf + (model.source.map { " · \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.leading, WatchTheme.Spacing.xs)
                    }
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.s)
        }
        .containerBackground(WatchTheme.brandTeal.opacity(0.18).gradient, for: .tabView)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

// MARK: - Page 2 — NutriCheck voice

struct NutriCheckVoiceView: View {
    @State private var model = NutriCheckModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                BrandHeader(title: "NutriCheck")

                switch model.phase {
                case .idle:
                    prompt
                case .thinking:
                    RHGlassCard {
                        HStack(spacing: WatchTheme.Spacing.s) {
                            ProgressView().tint(WatchTheme.brandTeal)
                            Text("Checking \(model.foodItem)…")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                case .result:
                    resultCard
                case .error:
                    RHGlassCard { Text(model.errorText).font(.footnote).foregroundStyle(.secondary) }
                    againButton
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.s)
        }
        .containerBackground(WatchTheme.brandTeal.opacity(0.18).gradient, for: .tabView)
    }

    // Tap the field → the watch input UI opens with Dictation; speak the food, then submit.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
            RHGlassCard {
                HStack(spacing: WatchTheme.Spacing.s) {
                    Image(systemName: "mic.fill").foregroundStyle(WatchTheme.brandTeal)
                    TextField("Tap & speak a food", text: $model.foodItem)
                        .font(.footnote)
                        .onSubmit { Task { await model.submit() } }
                }
            }
            Button {
                Task { await model.submit() }
            } label: {
                Text("Check").frame(maxWidth: .infinity)
            }
            .tint(WatchTheme.brandTeal)
            .disabled(model.foodItem.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
            RHGlassCard {
                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                    Text(model.foodItem)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(model.verdictLabel)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(model.isPositive ? WatchTheme.brandTeal : .primary)
                    if !model.reason.isEmpty {
                        Text(model.reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            againButton
        }
    }

    private var againButton: some View {
        Button { model.reset() } label: {
            Label("Check another", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .tint(WatchTheme.brandTeal)
    }
}
