import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
private final class DoctorSheetVM {
    // Search
    var searchQuery = ""
    var searchResults: [DoctorSearchResult] = []
    var isSearching = false
    var searchError: String?

    // Connected
    var connectedDoctors: [DoctorSearchResult] = []

    // Pending outbound + incoming
    var pendingRequests: [DoctorPendingRecord] = []
    var incomingRequests: [IncomingDoctorRequest] = []

    var isLoadingConnections = false
    var selectedTab = 0  // 0=Search, 1=Connected, 2=Requests
    var actionError: String?
    var disclaimerDoctor: DoctorSearchResult? = nil  // set before showing disclaimer

    private let service = DoctorService()

    func search() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        searchError = nil
        do {
            searchResults = try await service.searchDoctors(query: q)
        } catch {
            searchError = "Search failed. Please try again."
        }
    }

    func loadConnections() async {
        isLoadingConnections = true
        defer { isLoadingConnections = false }
        async let connected = service.fetchConnectedDoctors()
        async let pending   = service.fetchPendingRequests()
        async let incoming  = service.fetchIncomingRequests()
        connectedDoctors  = (try? await connected) ?? []
        pendingRequests   = (try? await pending) ?? []
        incomingRequests  = (try? await incoming) ?? []
    }

    func showDisclaimer(for doctor: DoctorSearchResult) {
        disclaimerDoctor = doctor
    }

    func connect(doctorId: String) async {
        disclaimerDoctor = nil
        actionError = nil
        do {
            try await service.sendConnectionRequest(doctorId: doctorId)
            // Refresh search results to update connectionStatus badge
            await search()
        } catch {
            actionError = "Failed to send request."
        }
    }

    func cancelRequest(doctorId: String) async {
        actionError = nil
        try? await service.cancelConnectionRequest(doctorId: doctorId)
        pendingRequests.removeAll { $0.doctor.id == doctorId }
    }

    func respondToIncoming(email: String, accept: Bool) async {
        actionError = nil
        try? await service.respondToRequest(email: email, accept: accept)
        incomingRequests.removeAll { $0.email == email }
        if accept { await loadConnections() }
    }
}

// MARK: - View

struct DoctorSheetView: View {
    @State private var vm = DoctorSheetVM()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $vm.selectedTab) {
                    Text("Search").tag(0)
                    Text("Connected").tag(1)
                    Text("Requests").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(Theme.Spacing.m)

                Group {
                    switch vm.selectedTab {
                    case 0: searchTab
                    case 1: connectedTab
                    default: requestsTab
                    }
                }
            }
            .navigationTitle("Doctor")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: vm.selectedTab) {
            if vm.selectedTab != 0 { await vm.loadConnections() }
        }
        .confirmationDialog(
            "Connect with \(vm.disclaimerDoctor?.name ?? "this doctor")?",
            isPresented: Binding(get: { vm.disclaimerDoctor != nil }, set: { if !$0 { vm.disclaimerDoctor = nil } }),
            titleVisibility: .visible
        ) {
            if let doc = vm.disclaimerDoctor {
                Button("Send Request") { Task { await vm.connect(doctorId: doc.id) } }
            }
            Button("Cancel", role: .cancel) { vm.disclaimerDoctor = nil }
        } message: {
            Text("By connecting, you agree to share relevant health data with \(vm.disclaimerDoctor?.name ?? "this doctor") so they can provide better care. You can disconnect at any time.")
        }
    }

    // MARK: - Search tab

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name, specialty, or licence…", text: $vm.searchQuery)
                    .submitLabel(.search)
                    .onSubmit { Task { await vm.search() } }
                if vm.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(Theme.Spacing.s)
            .background(.fill, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.button))
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)

            if let error = vm.searchError {
                Text(error).font(.caption).foregroundStyle(.red) // error feedback
                    .padding(.horizontal, Theme.Spacing.m)
            }

            if vm.actionError != nil {
                Text(vm.actionError!)
                    .font(.caption).foregroundStyle(.red) // error feedback
                    .padding(.horizontal, Theme.Spacing.m)
            }

            List {
                if vm.searchResults.isEmpty && !vm.searchQuery.isEmpty && !vm.isSearching {
                    ContentUnavailableView.search(text: vm.searchQuery)
                } else {
                    ForEach(vm.searchResults) { doc in
                        DoctorRow(doc: doc) { _ in
                            vm.showDisclaimer(for: doc)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Connected tab

    private var connectedTab: some View {
        Group {
            if vm.isLoadingConnections {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.connectedDoctors.isEmpty {
                ContentUnavailableView(
                    "No Connected Doctors",
                    systemImage: "stethoscope",
                    description: Text("Use the Search tab to find and connect with a doctor.")
                )
            } else {
                List {
                    ForEach(vm.connectedDoctors) { doc in
                        DoctorRow(doc: doc, onConnect: nil)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.loadConnections() }
            }
        }
    }

    // MARK: - Requests tab

    private var requestsTab: some View {
        Group {
            if vm.isLoadingConnections {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.pendingRequests.isEmpty && vm.incomingRequests.isEmpty {
                ContentUnavailableView(
                    "No Pending Requests",
                    systemImage: "person.crop.circle.badge.clock",
                    description: Text("Outbound and incoming requests appear here.")
                )
            } else {
                List {
                    // Incoming from doctors
                    if !vm.incomingRequests.isEmpty {
                        Section("Incoming Requests") {
                            ForEach(vm.incomingRequests) { req in
                                IncomingRequestRow(req: req) { accept in
                                    Task { await vm.respondToIncoming(email: req.email, accept: accept) }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    // Outbound (sent by patient, awaiting doctor response)
                    if !vm.pendingRequests.isEmpty {
                        Section("Sent Requests") {
                            ForEach(vm.pendingRequests) { record in
                                PendingRequestRow(record: record) {
                                    Task { await vm.cancelRequest(doctorId: record.doctor.id) }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.loadConnections() }
            }
        }
    }
}

// MARK: - Doctor row

private struct DoctorRow: View {
    let doc: DoctorSearchResult
    let onConnect: ((String) -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    // Avatar initials
                    ZStack {
                        Circle()
                            .fill(Theme.brandTeal.opacity(0.15))
                            .frame(width: Theme.IconSize.avatar, height: Theme.IconSize.avatar)
                        Text(String(doc.name.prefix(2)).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.brandTeal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.name)
                            .font(.subheadline.weight(.semibold))
                        Text(doc.specialty)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !doc.city.isEmpty {
                            Text(doc.city)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if let level = doc.connectionStatusLevel {
                        StatusPill(text: (doc.connectionStatus ?? "").capitalized, level: level)
                    } else if let onConnect {
                        Button("Connect") { onConnect(doc.id) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brandTeal)
                            .font(.caption)
                    }
                }

                if doc.experience > 0 {
                    HStack(spacing: Theme.Spacing.s) {
                        Label("\(doc.experience) yrs", systemImage: "clock")
                        if !doc.hospitalAffiliation.isEmpty {
                            Label(doc.hospitalAffiliation, systemImage: "building.2")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Incoming request row

private struct IncomingRequestRow: View {
    let req: IncomingDoctorRequest
    let onRespond: (Bool) -> Void

    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(req.name)
                        .font(.subheadline.weight(.semibold))
                    Text(req.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Theme.Spacing.s) {
                    Button("Accept") { onRespond(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                        .font(.caption)
                    Button("Decline") { onRespond(false) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Pending outbound row

private struct PendingRequestRow: View {
    let record: DoctorPendingRecord
    let onCancel: () -> Void

    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.doctor.name)
                        .font(.subheadline.weight(.semibold))
                    Text(record.doctor.specialty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let msg = record.message, !msg.isEmpty {
                        Text("\"\(msg)\"")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    StatusPill(text: "Pending", level: .yellow)
                    Button("Cancel", action: onCancel)
                        .font(.caption)
                        .foregroundStyle(.red) // destructive action affordance
                }
            }
        }
    }
}
