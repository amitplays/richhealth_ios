import SwiftUI

// MARK: - App entry

@main
struct RichHealthWatchApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// MARK: - Root — vertical paging, one "moment" per page

struct RootView: View {
    var body: some View {
        TabView {
            TodayGlanceView()
            BriefingView()
            AskAIView()
            NutriCheckVoiceView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Shared bits

private let pageBackground = WatchTheme.brandTeal.opacity(0.18).gradient

private struct LoadingBlock: View {
    var body: some View {
        BrandSpinner(size: 34)
            .frame(maxWidth: .infinity)
            .padding(.vertical, WatchTheme.Spacing.l)
    }
}

private struct MessageCard: View {
    let text: String
    var body: some View {
        RHGlassCard { Text(text).font(.footnote).foregroundStyle(.secondary) }
    }
}

private struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var disabled: Bool = false
    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .tint(WatchTheme.brandTeal)
        .disabled(disabled)
    }
}

// MARK: - Page 1 — Today glance (richer vitals)

struct TodayGlanceView: View {
    @State private var model = TodayGlanceModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                BrandHeader(title: "Today", busy: model.isLoading)

                if model.isLoading && model.metrics.isEmpty {
                    LoadingBlock()
                } else if let err = model.errorText, model.metrics.isEmpty {
                    MessageCard(text: err)
                } else {
                    RHGlassGroup {
                        ForEach(model.metrics) { m in
                            RHGlassCard {
                                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                                    Text(m.label.uppercased())
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(m.value)
                                            .font(.system(.title2, design: .rounded).weight(.semibold))
                                            .foregroundStyle(WatchTheme.brandTeal)
                                        if !m.unit.isEmpty {
                                            Text(m.unit).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
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
        .containerBackground(pageBackground, for: .tabView)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

// MARK: - Page 2 — Daily AI briefing

struct BriefingView: View {
    @State private var model = BriefingModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                BrandHeader(title: "Briefing", busy: model.isLoading)

                if model.isLoading && model.cards.isEmpty {
                    LoadingBlock()
                } else if let err = model.errorText, model.cards.isEmpty {
                    MessageCard(text: err)
                } else {
                    RHGlassGroup {
                        ForEach(model.cards) { card in
                            RHGlassCard {
                                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                                    Text(card.title)
                                        .font(.headline).foregroundStyle(WatchTheme.brandTeal)
                                    ForEach(Array(card.points.enumerated()), id: \.offset) { _, p in
                                        Text("• " + p).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    PrimaryButton(title: "Read aloud", systemImage: "speaker.wave.2.fill") {
                        model.speakAll()
                    }
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.s)
        }
        .containerBackground(pageBackground, for: .tabView)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

// MARK: - Page 3 — Ask AI (voice)

struct AskAIView: View {
    @State private var model = AskAIModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                BrandHeader(title: "Ask RichHealth", busy: model.phase == .thinking)

                switch model.phase {
                case .idle:
                    ask
                case .thinking:
                    RHGlassCard {
                        HStack(spacing: WatchTheme.Spacing.s) {
                            BrandSpinner(size: 22)
                            Text("Thinking…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                case .answered:
                    RHGlassCard {
                        Text(model.answer).font(.footnote).foregroundStyle(.primary)
                    }
                    againButton
                case .error:
                    MessageCard(text: model.errorText)
                    againButton
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.s)
        }
        .containerBackground(pageBackground, for: .tabView)
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
            RHGlassCard {
                HStack(spacing: WatchTheme.Spacing.s) {
                    Image(systemName: "mic.fill").foregroundStyle(WatchTheme.brandTeal)
                    TextField("Tap & ask a question", text: $model.question)
                        .font(.footnote)
                        .onSubmit { Task { await model.submit() } }
                }
            }
            PrimaryButton(title: "Ask", systemImage: nil, action: { Task { await model.submit() } },
                          disabled: model.question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var againButton: some View {
        PrimaryButton(title: "Ask another", systemImage: "arrow.counterclockwise") { model.reset() }
    }
}

// MARK: - Page 4 — NutriCheck (voice)

struct NutriCheckVoiceView: View {
    @State private var model = NutriCheckModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                BrandHeader(title: "NutriCheck", busy: model.phase == .thinking)

                switch model.phase {
                case .idle:
                    prompt
                case .thinking:
                    RHGlassCard {
                        HStack(spacing: WatchTheme.Spacing.s) {
                            BrandSpinner(size: 22)
                            Text("Checking \(model.foodItem)…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                case .result:
                    resultCard
                case .error:
                    MessageCard(text: model.errorText)
                    againButton
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.s)
        }
        .containerBackground(pageBackground, for: .tabView)
    }

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
            PrimaryButton(title: "Check", systemImage: nil, action: { Task { await model.submit() } },
                          disabled: model.foodItem.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
            RHGlassCard {
                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                    Text(model.foodItem).font(.caption2).foregroundStyle(.secondary)
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
        PrimaryButton(title: "Check another", systemImage: "arrow.counterclockwise") { model.reset() }
    }
}
