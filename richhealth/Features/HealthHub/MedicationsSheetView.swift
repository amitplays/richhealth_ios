import SwiftUI

private let frequencyOptions = [
    "Once daily", "Twice daily", "Three times daily", "Four times daily",
    "Every 6 hours", "Every 8 hours", "Every 12 hours",
    "As needed", "Weekly", "Monthly", "Custom"
]

private let medicationTypes = ["Prescription", "Over-the-counter", "Supplement", "Herbal", "Vitamin", "Other"]
private let administrationMethods = ["Oral", "Injection", "Topical", "Inhaled", "Eye drops", "Nasal", "Other"]

// MARK: - ViewModel

@Observable @MainActor
final class MedicationsSheetViewModel {
    var isLoading = false
    var items: [MedicationRecord] = []
    var searchText = ""
    var showError = false
    var errorMessage: String?
    var showAddForm = false
    var editingItem: MedicationRecord?
    var discontinuingItem: MedicationRecord?

    var filtered: [MedicationRecord] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(q) ||
            $0.dosage.lowercased().contains(q) ||
            ($0.purpose?.lowercased().contains(q) ?? false)
        }
    }

    private let service = MedicationService()

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.list()
            items = response.medications
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func discontinue(_ id: String, reason: String, date: Date?) async {
        do {
            let updated = try await service.discontinue(id, reason: reason, date: date)
            if let idx = items.firstIndex(where: { $0.id == id }) { items[idx] = updated }
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

struct MedicationsSheetView: View {
    @State private var vm = MedicationsSheetViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    placeholderList
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView("No Medications", systemImage: "pills",
                        description: Text("Tap + to add a medication."))
                } else {
                    medList
                }
            }
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "Search medications")
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
                MedicationFormView(existing: nil) { saved in vm.items.insert(saved, at: 0) }
            }
            .sheet(item: $vm.editingItem) { item in
                MedicationFormView(existing: item) { saved in
                    if let idx = vm.items.firstIndex(where: { $0.id == saved.id }) { vm.items[idx] = saved }
                }
            }
            .sheet(item: $vm.discontinuingItem) { item in
                DiscontinueMedicationSheet(medicationName: item.name) { reason, date in
                    Task { await vm.discontinue(item.id, reason: reason, date: date) }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var medList: some View {
        List {
            ForEach(vm.filtered) { item in
                let displayDate: String? = {
                    if let d = item.durationText, !d.isEmpty { return d }
                    return item.startDate.map { "Since \($0.shortDate)" }
                }()
                HealthRecordRow(
                    icon: "pills.fill",
                    title: item.name,
                    subtitle: "\(item.dosage) · \(item.frequency)",
                    pillText: item.isOngoing ? "Active" : "Completed",
                    pillLevel: item.isOngoing ? .green : .yellow,
                    date: displayDate
                )
                .contentShape(Rectangle())
                .onTapGesture { vm.editingItem = item }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.delete(item.id) }
                    } label: { Label("Delete", systemImage: "trash") }
                    if item.isOngoing {
                        Button {
                            vm.discontinuingItem = item
                        } label: { Label("Discontinue", systemImage: "xmark.circle") }
                            .tint(StatusLevel.orange.color) // orange signals medication concern
                    }
                }
            }
        }
    }

    private var placeholderList: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                HealthRecordRow(icon: "pills.fill",
                                title: "Medication name",
                                subtitle: "500mg · Once daily",
                                pillText: "Active", pillLevel: .green,
                                date: "Since Jan 1")
                    .skeleton(isActive: true)
            }
        }
    }
}

// MARK: - Form

struct MedicationFormView: View {
    let existing: MedicationRecord?
    let onSave: (MedicationRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency = frequencyOptions[0]
    @State private var customFrequency = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isOngoing = true
    @State private var purpose = ""
    @State private var prescribedBy = ""
    @State private var medType = medicationTypes[0]
    @State private var adminMethod = administrationMethods[0]
    @State private var notes = ""
    @State private var shareWithFamily = false
    @State private var includeInChat = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let service = MedicationService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $name)
                    TextField("Dosage (e.g. 500mg)", text: $dosage)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencyOptions, id: \.self) { Text($0) }
                    }
                    if frequency == "Custom" {
                        TextField("Custom schedule", text: $customFrequency)
                    }
                }
                Section("Type") {
                    Picker("Type", selection: $medType) {
                        ForEach(medicationTypes, id: \.self) { Text($0) }
                    }
                    Picker("Administration", selection: $adminMethod) {
                        ForEach(administrationMethods, id: \.self) { Text($0) }
                    }
                }
                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, in: ...Date.distantFuture, displayedComponents: .date)
                    Toggle("Still taking", isOn: $isOngoing)
                    if isOngoing {
                        Label("Remember to update this when you stop taking this medication", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.vertical, 2)
                    }
                    if !isOngoing {
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                Section("Details") {
                    TextField("Purpose", text: $purpose)
                    TextField("Prescribed by", text: $prescribedBy)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3, reservesSpace: true)
                }
                Section("Sharing") {
                    Toggle("Share with family", isOn: $shareWithFamily)
                    Toggle("Include in AI chat context", isOn: $includeInChat)
                }
            }
            .navigationTitle(existing == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.isEmpty || dosage.isEmpty || isSaving)
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
        name = e.name; dosage = e.dosage; frequency = e.frequency
        customFrequency = e.customFrequency ?? ""
        isOngoing = e.isOngoing
        purpose = e.purpose ?? ""; prescribedBy = e.prescribedBy ?? ""
        medType = e.medicationType; adminMethod = e.administrationMethod
        notes = e.notes ?? ""
        shareWithFamily = e.shareWithFamily
        includeInChat = e.includeInChat
        if let raw = e.startDate, let d = DateFormatter.yyyyMMdd.date(from: String(raw.prefix(10))) { startDate = d }
        if let raw = e.endDate, let d = DateFormatter.yyyyMMdd.date(from: String(raw.prefix(10))) { endDate = d }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let req = CreateMedicationRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosage.trimmingCharacters(in: .whitespaces),
            frequency: frequency,
            customFrequency: frequency == "Custom" ? customFrequency : nil,
            startDate: DateFormatter.iso8601Date.string(from: startDate),
            endDate: isOngoing ? nil : DateFormatter.iso8601Date.string(from: endDate),
            isOngoing: isOngoing,
            purpose: purpose.isEmpty ? nil : purpose,
            prescribedBy: prescribedBy.isEmpty ? nil : prescribedBy,
            medicationType: medType,
            administrationMethod: adminMethod,
            notes: notes.isEmpty ? nil : notes,
            shareWithFamily: shareWithFamily,
            includeInChat: includeInChat
        )
        do {
            let record: MedicationRecord
            if let e = existing { record = try await service.update(e.id, req) }
            else { record = try await service.create(req) }
            onSave(record); dismiss()
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }
}

extension MedicationRecord {
    static let placeholder = MedicationRecord(
        id: UUID().uuidString, name: "Placeholder Med", dosage: "500mg", frequency: "Once daily",
        customFrequency: nil, startDate: nil, endDate: nil, isOngoing: true,
        purpose: nil, prescribedBy: nil, medicationType: "Prescription",
        administrationMethod: "Oral", notes: nil, shareWithFamily: false,
        includeInChat: true, isCurrent: true, durationText: "Since Jan 1, 2026", createdAt: nil)
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let iso8601Date: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"; f.timeZone = TimeZone(identifier: "UTC"); return f }()
}

// MARK: - Discontinue Sheet (reason + optional date — mirrors Android dialog_discontinue_medication)

private struct DiscontinueMedicationSheet: View {
    let medicationName: String
    let onConfirm: (String, Date?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var hasDate = false
    @State private var discontinueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Mark \"\(medicationName)\" as discontinued.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Reason (Optional)") {
                    TextField("Why are you stopping?", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Discontinue Date") {
                    Toggle("Use a specific end date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $discontinueDate, in: ...Date(), displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Discontinue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Discontinue", role: .destructive) {
                        onConfirm(reason, hasDate ? discontinueDate : nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview { MedicationsSheetView() }
