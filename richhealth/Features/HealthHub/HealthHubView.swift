import SwiftUI

/// The six Android side panels become native .sheet drawers (CLAUDE.md §5).
enum HealthHubSheet: String, Identifiable {
    case symptoms, measurements, medications, reports, periods, family
    var id: String { rawValue }
}

struct HealthHubView: View {
    @State private var vm = HealthHubViewModel()
    @State private var activeSheet: HealthHubSheet?
    @State private var health = HealthKitManager.shared
    @Environment(AppEnvironment.self) private var appEnv

    // Matches Android: visible for female gender OR any non-excluded menstrual status.
    private var showPeriodCard: Bool {
        let user = appEnv.auth.currentUser
        if user?.gender?.lowercased() == "female" { return true }
        let excluded = ["not_applicable", "prefer_not_to_say"]
        if let ms = user?.menstrualStatus?.lowercased(), !ms.isEmpty, !excluded.contains(ms) { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {

                    // Subtitle — mirrors Android: "Your medical record, in your pocket"
                    Text("Your medical record, in your pocket")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // When Apple Watch is connected, show live vitals here instead of record counts.
                    if health.isConnected {
                        watchStatsRow
                    } else {
                        statsRow
                    }

                    // ── Daily Tracking ──────────────────────────────────────
                    SectionLabel("Daily Tracking")
                    VStack(spacing: Theme.Spacing.s) {
                        HubCard(title: "Symptoms",
                                icon: "waveform.path.ecg.rectangle",
                                subtitle: vm.symptomCount == 0 ? "No symptoms logged" : "\(vm.symptomCount) logged") {
                            activeSheet = .symptoms
                        }
                        HubCard(title: "Measurements",
                                icon: "ruler.fill",
                                subtitle: vm.measurementCount == 0 ? "No vitals recorded" : "\(vm.measurementCount) recorded") {
                            activeSheet = .measurements
                        }
                        if showPeriodCard {
                            HubCard(title: "Period Log",
                                    icon: "calendar.badge.clock",
                                    subtitle: "Track your cycle") {
                                activeSheet = .periods
                            }
                        }
                    }
                    .skeleton(isActive: vm.isLoading)

                    // ── Health Records ──────────────────────────────────────
                    SectionLabel("Health Records")
                    VStack(spacing: Theme.Spacing.s) {
                        HubCard(title: "Medications",
                                icon: "pills.fill",
                                subtitle: vm.medicationCount == 0 ? "No active medications" : "\(vm.medicationCount) active") {
                            activeSheet = .medications
                        }
                        HubCard(title: "Medical Reports",
                                icon: "doc.text.magnifyingglass",
                                subtitle: vm.reportCount == 0 ? "No reports uploaded" : "\(vm.reportCount) uploaded") {
                            activeSheet = .reports
                        }
                        HubCard(title: "Family",
                                icon: "person.2.fill",
                                subtitle: "Genetic history & shared records") {
                            activeSheet = .family
                        }
                    }
                    .skeleton(isActive: vm.isLoading)
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Health Hub")
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .task { await health.autoSyncIfNeeded() }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "Something went wrong.")
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
        }
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            StatChip(label: "Symptoms", count: vm.symptomCount, icon: "waveform.path.ecg")
            StatChip(label: "Vitals", count: vm.measurementCount, icon: "heart.text.square")
            StatChip(label: "Active Meds", count: vm.medicationCount, icon: "pills")
            StatChip(label: "Reports", count: vm.reportCount, icon: "doc.text.magnifyingglass")
        }
        .skeleton(isActive: vm.isLoading)
    }

    // MARK: Apple Watch live vitals (shown when connected)

    private var watchStatsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "applewatch")
                    .font(.system(size: 11, weight: .bold))
                Text("FROM APPLE WATCH")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: Theme.Spacing.s) {
                WatchStatChip(icon: "heart.fill",
                              value: health.latestHeartRate.map { "\($0)" } ?? "—", label: "Heart")
                WatchStatChip(icon: "lungs.fill",
                              value: health.reading(.bloodOxygen).map { "\($0.backendValue)%" } ?? "—", label: "SpO₂")
                WatchStatChip(icon: "thermometer.medium",
                              value: health.reading(.temperature).map { "\($0.backendValue)°" } ?? "—", label: "Temp")
                WatchStatChip(icon: "figure.walk",
                              value: health.reading(.steps)?.backendValue ?? "—", label: "Steps")
            }
        }
    }

    // MARK: Sheet routing

    @ViewBuilder
    private func sheetContent(for sheet: HealthHubSheet) -> some View {
        switch sheet {
        case .symptoms:
            SymptomsSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .measurements:
            MeasurementsSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .medications:
            MedicationsSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .reports:
            MedicalReportsSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .periods:
            PeriodLogSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .family:
            FamilySheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Section label
// Mirrors Android's 11sp bold uppercase letter-spaced gray section headers.

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .kerning(1.0)
            .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Stat chip

private struct StatChip: View {
    let label: String
    let count: Int
    let icon: String

    var body: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.brandTeal)
                Text("\(count)")
                    .font(.title2.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
        }
    }
}

// MARK: - Watch stat chip
// Same footprint as StatChip but takes a string value (bpm, %, °, steps). Single line, scales
// down rather than wrapping — keeps all four cards identical height.

private struct WatchStatChip: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.brandTeal)
                Text(value)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
        }
    }
}

// MARK: - Hub card
// Icon in teal container + teal title + subtitle + chevron.
// Mirrors Android: 48dp icon-in-teal-bg, title in rh_accent, 12.5sp gray subtitle.

private struct HubCard: View {
    let title: String
    let icon: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: Theme.Spacing.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.icon)
                            .fill(Theme.brandTeal.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.brandTeal)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.brandTeal)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 52)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview { HealthHubView().environment(AppEnvironment()) }
