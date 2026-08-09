import SwiftUI

// MARK: - Metric types and units

private let metricTypes: [String] = [
    "Blood Pressure", "Glucose", "Heart Rate", "Weight",
    "Temperature", "Oxygen Saturation", "Cholesterol", "TSH"
]

private let unitOptions: [String: [String]] = [
    "Blood Pressure": ["mmHg"],
    "Glucose": ["mg/dL", "mmol/L"],
    "Heart Rate": ["bpm"],
    "Weight": ["kg", "lbs"],
    "Temperature": ["°C", "°F"],
    "Oxygen Saturation": ["%"],
    "Cholesterol": ["mg/dL", "mmol/L"],
    "TSH": ["mIU/L"]
]

/// Client-side status classification for measurements (server returns no status field for health/data).
private func measurementStatus(type: String, value: Double) -> StatusLevel {
    switch type {
    case "Heart Rate":
        if value < 60 || value > 100 { return value < 40 || value > 130 ? .red : .orange }
        return .green
    case "Oxygen Saturation":
        if value < 90 { return .red }
        if value < 95 { return .orange }
        return .green
    case "Glucose":
        if value < 70 || value > 200 { return .red }
        if value < 100 || value > 140 { return .yellow }
        return .green
    case "Weight":
        return .green  // no universal threshold
    case "Temperature":
        if value > 39 || value < 35 { return .red }
        if value > 37.5 || value < 36 { return .yellow }
        return .green
    default:
        return .green
    }
}

// MARK: - ViewModel

@Observable @MainActor
final class MeasurementsSheetViewModel {
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
        return items.filter {
            $0.title.lowercased().contains(q) ||
            ($0.unit?.lowercased().contains(q) ?? false) ||
            ($0.description?.lowercased().contains(q) ?? false)
        }
    }

    private let service = HealthDataService()

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.list(type: "measurement")
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

struct MeasurementsSheetView: View {
    @State private var vm = MeasurementsSheetViewModel()
    @State private var appleExpanded = false

    private var appleItems: [MedicalDataRecord] { vm.filtered.filter { $0.isFromAppleWatch } }
    private var manualItems: [MedicalDataRecord] { vm.filtered.filter { !$0.isFromAppleWatch } }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    placeholderList
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView("No Measurements", systemImage: "heart.text.square",
                        description: Text("Tap + to record a vital."))
                } else {
                    measurementList
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "Search measurements")
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
                MeasurementFormView(existing: nil) { saved in
                    vm.items.insert(saved, at: 0)
                }
            }
            .sheet(item: $vm.editingItem) { item in
                MeasurementFormView(existing: item) { saved in
                    if let idx = vm.items.firstIndex(where: { $0.id == saved.id }) {
                        vm.items[idx] = saved
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var measurementList: some View {
        List {
            // Manually-entered measurements (in-app / any platform)
            if !manualItems.isEmpty {
                Section {
                    ForEach(manualItems) { item in
                        measurementRow(item, compact: false)
                    }
                } header: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.brandTeal)
                        Text("Manually Added")
                    }
                }
            }

            // Apple Watch imports — collapsible group. Compact rows (no description), watch icon.
            // Explicit tappable header + manual row inclusion — reliable in any List style
            // (native Section(isExpanded:) only shows a chevron in sidebar lists).
            if !appleItems.isEmpty {
                Section {
                    if appleExpanded {
                        ForEach(appleItems) { item in
                            measurementRow(item, compact: true)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { appleExpanded.toggle() }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "applewatch").foregroundStyle(Theme.brandTeal)
                            Text("Apple Watch")
                            Spacer()
                            // Item count in brand teal
                            Text("\(appleItems.count)").foregroundStyle(Theme.brandTeal)
                            Image(systemName: appleExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // List enforces a 44pt min row height by default — that's why compact rows didn't shrink.
        // Lower it so the Apple rows can be genuinely shorter; manual rows are icon-bound at 44 and unaffected.
        .environment(\.defaultMinListRowHeight, 38)
    }

    @ViewBuilder
    private func measurementRow(_ item: MedicalDataRecord, compact: Bool) -> some View {
        let level: StatusLevel = {
            guard let vs = item.value, let v = Double(vs) else { return .green }
            return measurementStatus(type: item.title, value: v)
        }()
        let pillText: String? = item.value.flatMap { v in item.unit.map { "\(v) \($0)" } }
        HealthRecordRow(
            icon: compact ? "applewatch" : "ruler.fill",   // watch icon in the leading slot for Apple rows
            title: item.title,
            subtitle: item.displaySubtitle,                 // nil for Apple imports → shorter row
            pillText: pillText,
            pillLevel: pillText != nil ? level : nil,
            date: item.dateTime?.shortDate,
            compact: compact
        )
        .contentShape(Rectangle())
        // Compact (Apple) rows: trim the row's vertical insets so they sit tighter than manual rows.
        .listRowInsets(EdgeInsets(top: compact ? 2 : 8, leading: 20, bottom: compact ? 2 : 8, trailing: 20))
        .onTapGesture { vm.editingItem = item }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await vm.delete(item.id) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var placeholderList: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                HealthRecordRow(icon: "ruler.fill",
                                title: "Blood Pressure",
                                subtitle: "Loading notes",
                                pillText: "120 mmHg", pillLevel: .green,
                                date: "Jan 1")
                    .skeleton(isActive: true)
            }
        }
    }
}

// MARK: - Form

struct MeasurementFormView: View {
    let existing: MedicalDataRecord?
    let onSave: (MedicalDataRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType = metricTypes[0]
    @State private var value = ""
    @State private var selectedUnit = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var shareWithFamily = false
    @State private var includeInChat = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let service = HealthDataService()

    private var availableUnits: [String] { unitOptions[selectedType] ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metric") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(metricTypes, id: \.self) { Text($0) }
                    }
                    .onChange(of: selectedType) { _, _ in
                        selectedUnit = availableUnits.first ?? ""
                    }
                    HStack {
                        TextField("Value", text: $value)
                            .keyboardType(.decimalPad)
                        if !availableUnits.isEmpty {
                            Picker("", selection: $selectedUnit) {
                                ForEach(availableUnits, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Sharing") {
                    Toggle("Share with family", isOn: $shareWithFamily)
                    Toggle("Include in AI chat context", isOn: $includeInChat)
                }
            }
            .navigationTitle(existing == nil ? "Add Measurement" : "Edit Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(value.isEmpty || isSaving)
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
        if let e = existing {
            selectedType = e.title
            value = e.value ?? ""
            selectedUnit = e.unit ?? availableUnits.first ?? ""
            // Don't prefill the Apple Watch provenance sentinel into the editable notes field.
            notes = e.isFromAppleWatch ? "" : (e.description ?? "")
            shareWithFamily = e.shareWithFamily
            includeInChat = e.includeInChat
            if let raw = e.dateTime, let parsed = ISO8601DateFormatter().date(from: raw) { date = parsed }
        } else {
            selectedUnit = availableUnits.first ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        // Preserve Apple Health provenance on edit: keep the sentinel in `description` so an edited
        // import stays grouped under Apple Watch instead of silently becoming a manual entry.
        let keepAppleTag = existing?.isFromAppleWatch == true
        var req = CreateMedicalDataRequest(
            type: "measurement", title: selectedType,
            value: value, unit: selectedUnit,
            description: keepAppleTag ? MedicalDataRecord.appleWatchSourceTag : notes,
            dateTime: ISO8601DateFormatter().string(from: date)
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

#Preview { MeasurementsSheetView() }
