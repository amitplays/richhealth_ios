import SwiftUI

/// Apple Health / Apple Watch detail sheet. Sync is automatic (on open + periodically in the
/// background of the app lifecycle), so this is mostly a status + readings view — no manual save.
struct WatchSyncSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var manager = HealthKitManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if !manager.isAvailable {
                    ContentUnavailableView("Apple Health Unavailable", systemImage: "heart.slash",
                        description: Text("This device doesn't support Apple Health."))
                } else if manager.isLoading && manager.readings.isEmpty {
                    ProgressView("Reading Apple Health…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if manager.readings.isEmpty {
                    emptyState
                } else {
                    readingsList
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
                if !manager.readings.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { Task { await manager.sync() } } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(manager.isLoading)
                    }
                }
            }
            // Automatic: sync as soon as the sheet opens.
            .task { await manager.sync() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Apple Health Data", systemImage: "applewatch.slash")
        } description: {
            Text(manager.errorMessage
                 ?? "We couldn't read any data. Allow RichHealth in the Health app (Sharing → Apps), then it'll sync automatically.")
        } actions: {
            Button("Try Again") { Task { await manager.sync() } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandTeal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline)
            .tint(Theme.brandTeal)
        }
    }

    private var readingsList: some View {
        List {
            Section {
                ForEach(manager.readings) { reading in
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: reading.metric.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.brandTeal)
                            .frame(width: 26)
                        Text(reading.metric.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(reading.display)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("From Apple Health & Apple Watch")
            } footer: {
                if manager.lastSyncTS > 0 {
                    Text("Saved automatically. Last synced \(Date(timeIntervalSince1970: manager.lastSyncTS).formatted(.relative(presentation: .named))).")
                } else {
                    Text("These save automatically to your RichHealth measurements.")
                }
            }
        }
    }
}

#Preview { WatchSyncSheetView() }
