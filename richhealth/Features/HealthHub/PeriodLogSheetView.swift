import SwiftUI

private let flowOptions = ["light", "medium", "heavy"]

private func flowLabel(_ v: String) -> String {
    switch v.lowercased() {
    case "light": return "Light"
    case "medium": return "Medium"
    case "heavy": return "Heavy"
    default: return v.capitalized
    }
}

private func flowLevel(_ v: String) -> StatusLevel {
    switch v.lowercased() {
    case "light": return .green
    case "medium": return .yellow
    case "heavy": return .orange
    default: return .yellow
    }
}

private func painLabel(_ v: Int) -> String {
    switch v {
    case 1: return "Very Mild"
    case 2: return "Mild"
    case 3: return "Moderate"
    case 4: return "Severe"
    default: return "Very Severe"
    }
}

// MARK: - ViewModel

@Observable @MainActor
final class PeriodLogSheetViewModel {
    var isLoading = false
    var items: [PeriodLogRecord] = []
    var searchText = ""
    var showError = false
    var errorMessage: String?
    var showAddForm = false
    var editingItem: PeriodLogRecord?

    var filtered: [PeriodLogRecord] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter {
            $0.flowIntensity.lowercased().contains(q) ||
            ($0.notes?.lowercased().contains(q) ?? false)
        }
    }

    private let service = PeriodLogService()

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.list()
            items = response.periodLogs
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func delete(_ id: String) async {
        do {
            try await service.delete(id)
            items.removeAll { $0.id == id }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }
}

// MARK: - View

struct PeriodLogSheetView: View {
    @State private var vm = PeriodLogSheetViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    placeholderList
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView("No Period Logs", systemImage: "calendar.badge.clock",
                        description: Text("Tap + to log a cycle."))
                } else {
                    logList
                }
            }
            .navigationTitle("Period Log")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "Search logs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showAddForm = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(vm.errorMessage ?? "Something went wrong.") }
            .sheet(isPresented: $vm.showAddForm) {
                PeriodLogFormView(existing: nil) { saved in vm.items.insert(saved, at: 0) }
            }
            .sheet(item: $vm.editingItem) { item in
                PeriodLogFormView(existing: item) { saved in
                    if let idx = vm.items.firstIndex(where: { $0.id == saved.id }) { vm.items[idx] = saved }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var logList: some View {
        List {
            ForEach(vm.filtered) { item in
                let title = item.endDate.map { "\(item.startDate.shortDate) → \($0.shortDate)" }
                    ?? item.startDate.shortDate
                let subtitle = "\(flowLabel(item.flowIntensity)) flow · Pain: \(painLabel(item.painLevel))"
                HealthRecordRow(
                    icon: "calendar.badge.clock",
                    title: title,
                    subtitle: subtitle,
                    pillText: flowLabel(item.flowIntensity),
                    pillLevel: flowLevel(item.flowIntensity),
                    date: nil   // dates are in the title
                )
                .contentShape(Rectangle())
                .onTapGesture { vm.editingItem = item }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.delete(item.id) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private var placeholderList: some View {
        List {
            ForEach(0..<4, id: \.self) { _ in
                HealthRecordRow(icon: "calendar.badge.clock",
                                title: "Jan 1 → Jan 5, 2026",
                                subtitle: "Medium flow · Pain: Mild",
                                pillText: "Medium", pillLevel: .yellow,
                                date: nil)
                    .skeleton(isActive: true)
            }
        }
    }
}

// MARK: - Form

struct PeriodLogFormView: View {
    let existing: PeriodLogRecord?
    let onSave: (PeriodLogRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var flow = flowOptions[1]
    @State private var painLevel = 2
    @State private var notes = ""
    @State private var shareWithFamily = false
    @State private var includeInChat = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let service = PeriodLogService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, in: ...Date(), displayedComponents: .date)
                    Toggle("Has end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                    }
                }
                Section("Details") {
                    Picker("Flow Intensity", selection: $flow) {
                        ForEach(flowOptions, id: \.self) { Text(flowLabel($0)) }
                    }
                    LabeledContent("Pain: \(painLabel(painLevel))") {
                        Slider(value: Binding(get: { Double(painLevel) }, set: { painLevel = Int($0) }),
                               in: 1...5, step: 1)
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                Section("Sharing") {
                    Toggle("Share with family", isOn: $shareWithFamily)
                    Toggle("Include in AI chat context", isOn: $includeInChat)
                }
            }
            .navigationTitle(existing == nil ? "Log Period" : "Edit Period Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .disabled(isSaving)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "Could not save.") }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let e = existing else { return }
        flow = e.flowIntensity; painLevel = e.painLevel; notes = e.notes ?? ""
        shareWithFamily = e.shareWithFamily
        includeInChat = e.includeInChat
        if let d = DateFormatter.yyyyMMdd.date(from: String(e.startDate.prefix(10))) { startDate = d }
        if let raw = e.endDate {
            hasEndDate = true
            if let d = DateFormatter.yyyyMMdd.date(from: String(raw.prefix(10))) { endDate = d }
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let fmt = DateFormatter.iso8601Date
        let req = CreatePeriodLogRequest(
            startDate: fmt.string(from: startDate),
            endDate: hasEndDate ? fmt.string(from: endDate) : nil,
            flowIntensity: flow, painLevel: painLevel,
            notes: notes.isEmpty ? nil : notes,
            shareWithFamily: shareWithFamily,
            includeInChat: includeInChat
        )
        do {
            let record: PeriodLogRecord
            if let e = existing { record = try await service.update(e.id, req) }
            else { record = try await service.create(req) }
            onSave(record); dismiss()
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }
}

extension PeriodLogRecord {
    static let placeholder = PeriodLogRecord(
        id: UUID().uuidString, startDate: "2026-01-01T00:00:00Z", endDate: nil,
        flowIntensity: "medium", painLevel: 2, notes: nil,
        shareWithFamily: false, includeInChat: true, createdAt: nil)
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let iso8601Date: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
}

#Preview { PeriodLogSheetView() }
