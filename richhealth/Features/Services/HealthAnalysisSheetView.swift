import SwiftUI

// MARK: - Sheet

struct HealthAnalysisSheetView: View {
    @State private var analysis: HealthAnalysis?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss

    private let service = HealthAnalysisService()

    init(analysis: HealthAnalysis?) {
        self._analysis = State(initialValue: analysis)
    }

    private let tabs = ["Overall", "Symptoms", "Vitals", "Medications", "Reports", "Genetics"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {

                    // Status chip + headline
                    if let a = analysis {
                        statusHeader(a)
                    } else if !isGenerating {
                        noAnalysisPrompt
                    }

                    // Data-changed banner
                    if let changes = analysis?.dataChangesSinceAnalysis, changes.hasChanges {
                        GlassCard {
                            HStack(spacing: Theme.Spacing.s) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(StatusLevel.orange.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("New health data since last analysis")
                                        .font(.subheadline.weight(.semibold))
                                    Text(changes.changeSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Refresh") {
                                    Task { await generate() }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(Theme.brandTeal)
                                .disabled(isGenerating)
                            }
                        }
                    }

                    if analysis != nil {
                        // Per-type analysis tabs
                        analysisTabs

                        // Profile snapshot
                        profileSnapshot
                    }

                    // Bottom spacer for sheet chrome
                    Color.clear.frame(height: Theme.Spacing.m)
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Health Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isGenerating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Analyzing…").font(.caption)
                        }
                    } else {
                        Button(action: { Task { await generate() } }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(isGenerating)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "Something went wrong.") }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Status header

    @ViewBuilder
    private func statusHeader(_ a: HealthAnalysis) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Label("Health Status", systemImage: "heart.text.clipboard")
                        .font(.headline)
                    Spacer()
                    if let s = a.healthAnalysisStatus {
                        StatusPill(text: s.displayLabel, level: s.statusLevel)
                    }
                }
                if let headline = a.headline, !headline.isEmpty {
                    Text(headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let reason = a.healthAnalysisStatus?.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // Profile completion
                if let comp = a.profileCompletion, let pct = comp.percent {
                    Divider()
                    HStack {
                        Text("Profile completeness")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(pct)%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pct >= 80 ? StatusLevel.green.color : StatusLevel.yellow.color)
                    }
                    ProgressView(value: Double(pct) / 100.0)
                        .tint(pct >= 80 ? StatusLevel.green.color : StatusLevel.yellow.color)
                    if let missing = comp.missing, !missing.isEmpty {
                        Text("Add: \(missing.prefix(3).map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - No analysis prompt

    private var noAnalysisPrompt: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.brandTeal)
                Text("No Analysis Yet")
                    .font(.headline)
                Text("Generate your first AI health analysis based on your symptoms, vitals, medications, and reports.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: { Task { await generate() } }) {
                    HStack {
                        if isGenerating { ProgressView().tint(.white) }
                        Text(isGenerating ? "Analyzing… (up to 2 min)" : "Generate Analysis")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandTeal)
                .disabled(isGenerating)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
        }
    }

    // MARK: - Per-type tabs

    private var analysisTabs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("DETAILED ANALYSIS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(1.0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { idx, label in
                        Button(action: { selectedTab = idx }) {
                            Text(label)
                                .font(.subheadline.weight(selectedTab == idx ? .semibold : .regular))
                                .foregroundStyle(selectedTab == idx ? Theme.brandTeal : .secondary)
                                .padding(.horizontal, Theme.Spacing.s)
                                .padding(.vertical, Theme.Spacing.xs)
                                .glassEffect(
                                    selectedTab == idx
                                        ? .regular.tint(Theme.brandTeal).interactive()
                                        : .regular.interactive(),
                                    in: .capsule
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GlassCard {
                let item = cacheItem(for: selectedTab)
                if let text = item?.summary, !text.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let ts = item?.generatedAt {
                            Text("Generated \(ts.shortDate)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("No \(tabs[selectedTab].lowercased()) analysis yet. Add data and generate a new analysis.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
    }

    private func cacheItem(for tab: Int) -> HealthAnalysis.HACacheItem? {
        guard let cache = analysis?.healthAnalysisCache else { return nil }
        switch tab {
        case 0: return cache.overall
        case 1: return cache.symptoms
        case 2: return cache.measurements
        case 3: return cache.medications
        case 4: return cache.reports
        case 5: return cache.genetics
        default: return nil
        }
    }

    // MARK: - Profile snapshot

    private var profileSnapshot: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("PROFILE SNAPSHOT")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(1.0)

            GlassCard {
                if let m = analysis?.metrics {
                    HStack(spacing: 0) {
                        if let age = m.age {
                            SnapshotCell(label: "Age", value: "\(age) yrs")
                        }
                        if let bmi = m.bmi {
                            SnapshotCell(label: "BMI", value: String(format: "%.1f", bmi))
                        }
                        if let aqi = m.aqi {
                            SnapshotCell(label: "AQI", value: "\(aqi)")
                        }
                        if let loc = m.location, !loc.isEmpty {
                            SnapshotCell(label: "Location", value: loc)
                        }
                    }
                } else {
                    Text("Complete your profile to see a health snapshot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Generate

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            if let result = try await service.generate().analysis {
                analysis = result
            }
        } catch let err as APIError {
            switch err {
            case .limitReached: errorMessage = "Analysis limit reached. Upgrade to Pro for more analyses."
            case .notAllowed:   errorMessage = "Health analysis requires a Pro plan."
            default:            errorMessage = err.userMessage
            }
            showError = true
        } catch {
            errorMessage = "Analysis failed. Please try again."
            showError = true
        }
    }
}

// MARK: - Snapshot cell

private struct SnapshotCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HealthAnalysisSheetView(analysis: nil)
}
