import SwiftUI

@Observable @MainActor
final class SymptomsSheetViewModel {
    var isLoading = false
    var items: [MedicalDataRecord] = []
    var searchText = ""
    var showError = false
    var errorMessage: String?
    var showAddForm = false
    var editingItem: MedicalDataRecord?

    var filtered: [MedicalDataRecord] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter { $0.title.lowercased().contains(q) || ($0.description?.lowercased().contains(q) ?? false) }
    }

    private let service = HealthDataService()

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.list(type: "symptom")
            items = response.data
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

struct SymptomsSheetView: View {
    @State private var vm = SymptomsSheetViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    placeholderList
                } else if vm.filtered.isEmpty {
                    emptyState
                } else {
                    symptomList
                }
            }
            .navigationTitle("Symptoms")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "Search symptoms")
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
                SymptomFormView(existing: nil) { saved in
                    vm.items.insert(saved, at: 0)
                }
            }
            .sheet(item: $vm.editingItem) { item in
                SymptomFormView(existing: item) { saved in
                    if let idx = vm.items.firstIndex(where: { $0.id == saved.id }) {
                        vm.items[idx] = saved
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var symptomList: some View {
        List {
            ForEach(vm.filtered) { item in
                let parts = [item.duration, item.description]
                    .compactMap { s -> String? in guard let v = s, !v.isEmpty else { return nil }; return v }
                HealthRecordRow(
                    icon: "waveform.path.ecg.rectangle",
                    title: item.title,
                    subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                    pillText: item.severity.map { severityLabel($0) },
                    pillLevel: item.severity.map { severityLevel($0) },
                    date: item.dateTime?.shortDate
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

    private var emptyState: some View {
        ContentUnavailableView("No Symptoms", systemImage: "waveform.path.ecg.rectangle",
            description: Text("Tap + to log a symptom."))
    }

    private var placeholderList: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                HealthRecordRow(icon: "waveform.path.ecg.rectangle",
                                title: "Loading symptom",
                                subtitle: "Duration · Notes",
                                pillText: "Mild", pillLevel: .yellow,
                                date: "Jan 1")
                    .skeleton(isActive: true)
            }
        }
    }
}

// MARK: - Add / Edit Form

struct SymptomFormView: View {
    let existing: MedicalDataRecord?
    let onSave: (MedicalDataRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var severity = 3
    @State private var duration = ""
    @State private var description = ""
    @State private var date = Date()
    @State private var shareWithFamily = false
    @State private var includeInChat = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let service = HealthDataService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Symptom") {
                    TextField("Name (e.g. Headache)", text: $name)
                    LabeledContent("Severity: \(severityLabel(severity))") {
                        Slider(value: Binding(get: { Double(severity) }, set: { severity = Int($0) }),
                               in: 1...5, step: 1)
                            .tint(severityLevel(severity).color)
                    }
                    TextField("Duration (e.g. 2 days)", text: $duration)
                    TextField("Notes", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Sharing") {
                    Toggle("Share with family", isOn: $shareWithFamily)
                    Toggle("Include in AI chat context", isOn: $includeInChat)
                }
            }
            .navigationTitle(existing == nil ? "Add Symptom" : "Edit Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
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
        name = e.title
        severity = min(max(e.severity ?? 3, 1), 5)
        duration = e.duration ?? ""
        description = e.description ?? ""
        shareWithFamily = e.shareWithFamily
        includeInChat = e.includeInChat
        if let raw = e.dateTime, let parsed = ISO8601DateFormatter().date(from: raw) { date = parsed }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var req = CreateMedicalDataRequest(
            type: "symptom", title: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            dateTime: ISO8601DateFormatter().string(from: date),
            severity: severity,
            duration: duration.isEmpty ? nil : duration
        )
        req.shareWithFamily = shareWithFamily
        req.includeInChat = includeInChat
        do {
            let record: MedicalDataRecord
            if let e = existing { record = try await service.update(e.id, req) }
            else { record = try await service.create(req) }
            onSave(record)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Helpers

private func severityLabel(_ v: Int) -> String {
    switch v {
    case 1: return "Very Mild"
    case 2: return "Mild"
    case 3: return "Moderate"
    case 4: return "Severe"
    default: return "Very Severe"
    }
}

private func severityLevel(_ v: Int) -> StatusLevel {
    switch v {
    case 1, 2: return .yellow
    case 3: return .orange
    default: return .red
    }
}


#Preview { SymptomsSheetView() }
