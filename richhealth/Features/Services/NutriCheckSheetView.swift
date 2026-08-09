import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
private final class NutriCheckVM {
    var foodInput = ""
    var isChecking = false
    var result: NutriCheckResponse?
    var history: [NutriCheckEntry] = []
    var isLoadingHistory = false
    var showPaywall = false
    var errorMessage: String?
    var selectedTab = 0   // 0 = Check, 1 = History

    private let service = InsightsService()

    func check() async {
        let item = foodInput.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        isChecking = true
        defer { isChecking = false }
        result = nil
        errorMessage = nil
        do {
            result = try await service.nutriCheck(foodItem: item)
            Analytics.shared.track(.nutricheckRun)
        } catch let e as APIError {
            switch e {
            case .limitReached: showPaywall = true
            default: errorMessage = e.userMessage
            }
        } catch {
            errorMessage = "Check failed. Please try again."
        }
    }

    func loadHistory() async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        history = (try? await service.fetchNutriCheckHistory())?.history ?? []
    }

    func react(id: String, reaction: String?) async {
        try? await service.submitNutriCheckFeedback(id: id, reaction: reaction)
        await loadHistory()
    }

    func delete(id: String) async {
        try? await service.deleteNutriCheckEntry(id: id)
        history.removeAll { $0.id == id }
    }
}

// MARK: - View

struct NutriCheckSheetView: View {
    @State private var vm = NutriCheckVM()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $vm.selectedTab) {
                    Text("Check").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(Theme.Spacing.m)

                if vm.selectedTab == 0 {
                    checkTab
                } else {
                    historyTab
                }
            }
            .navigationTitle("NutriCheck")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: vm.selectedTab) {
            if vm.selectedTab == 1 { await vm.loadHistory() }
        }
        .sheet(isPresented: $vm.showPaywall) { PaywallView() }
    }

    // MARK: - Check tab

    private var checkTab: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Enter a food item and get an AI-powered recommendation based on your health profile.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("e.g. Banana, Chapati, Coffee…", text: $vm.foodInput)
                                .textFieldStyle(.plain)
                                .submitLabel(.search)
                                .onSubmit { Task { await vm.check() } }

                            if !vm.foodInput.isEmpty {
                                Button(action: { vm.foodInput = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(Theme.Spacing.s)
                        .background(.fill, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.icon))

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red) // error feedback
                        }

                        Button(action: { Task { await vm.check() } }) {
                            HStack {
                                if vm.isChecking {
                                    ProgressView()
                                        .tint(.white) // contrast on teal button
                                }
                                Text(vm.isChecking ? "Analyzing…" : "Check Food")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                        .disabled(vm.foodInput.trimmingCharacters(in: .whitespaces).isEmpty || vm.isChecking)
                    }
                }

                if let result = vm.result {
                    NutriCheckResultCard(foodItem: vm.foodInput, result: result)
                }
            }
            .padding(Theme.Spacing.m)
        }
    }

    // MARK: - History tab

    private var historyTab: some View {
        Group {
            if vm.isLoadingHistory {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.history.isEmpty {
                ContentUnavailableView(
                    "No Checks Yet",
                    systemImage: "magnifyingglass",
                    description: Text("Your NutriCheck history will appear here.")
                )
            } else {
                List {
                    ForEach(vm.history) { entry in
                        NutriCheckHistoryRow(
                            entry: entry,
                            onReact: { reaction in Task { await vm.react(id: entry.id, reaction: reaction) } }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { vm.history[$0].id }
                        for id in ids { Task { await vm.delete(id: id) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Result card

private struct NutriCheckResultCard: View {
    let foodItem: String
    let result: NutriCheckResponse

    var statusLevel: StatusLevel {
        switch result.recommendation {
        case "strong_yes", "yes": return .green
        case "moderate":          return .yellow
        case "no":                return .orange
        case "strong_no":         return .red
        default:                  return .yellow
        }
    }

    var label: String {
        switch result.recommendation {
        case "strong_yes": return "Highly Recommended"
        case "yes":        return "Good"
        case "moderate":   return "Moderate"
        case "no":         return "Avoid"
        case "strong_no":  return "Strongly Avoid"
        default:           return result.recommendation.capitalized
        }
    }

    var body: some View {
        // Same canonical card as the history rows — component draws the divider; "Based on:" is
        // the footer (bottom-left) and the freshly-computed result reads "Just now" (bottom-right).
        StandardCard(
            title: foodItem,
            titleFont: .subheadline.weight(.semibold),
            statusText: label,
            statusLevel: statusLevel,
            bodyText: result.reason,
            footerView: result.dataUsed.isEmpty ? nil : AnyView(
                Text("Based on: \(result.dataUsed.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            ),
            date: "just now"
        )
    }
}

// MARK: - History row

private struct NutriCheckHistoryRow: View {
    let entry: NutriCheckEntry
    let onReact: (String?) -> Void

    var body: some View {
        // Canonical card — §2A. Status chip, warning banner and date all land in their
        // consistent StandardCard slots; only the thumbs reaction is bespoke footer content.
        StandardCard(
            title: entry.foodItem,
            titleFont: .subheadline.weight(.semibold),
            statusText: entry.recommendationLabel,
            statusLevel: entry.statusLevel,
            bodyText: entry.reason,
            bodyLineLimit: 3,
            // Stale data warning — Android HealthDataFragment edge case
            warning: (entry.dataChangesSince?.isEmpty == false) ? entry.dataChangesSince : nil,
            // Thumbs reaction → meta slot (bottom-left); date → bottom-right, like every card.
            footerView: AnyView(
                HStack(spacing: Theme.Spacing.s) {
                    Button(action: {
                        onReact(entry.userReaction == "up" ? nil : "up")
                    }) {
                        Image(systemName: entry.userReaction == "up"
                              ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundStyle(entry.userReaction == "up" ? Theme.brandTeal : .secondary)
                    }
                    Button(action: {
                        onReact(entry.userReaction == "down" ? nil : "down")
                    }) {
                        Image(systemName: entry.userReaction == "down"
                              ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .foregroundStyle(entry.userReaction == "down" ? .red : .secondary) // negative reaction indicator
                    }
                }
            ),
            date: entry.checkedAt.shortDate
        )
    }
}
