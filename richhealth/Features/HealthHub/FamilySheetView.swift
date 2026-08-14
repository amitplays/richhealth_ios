import SwiftUI

/// The one relationship list, ordered oldest generation first. Kept identical to
/// Android's HealthDataFragment.RELATIONSHIP_OPTIONS, and every entry is covered
/// by the backend's reciprocal map (userController.getReciprocalRelationship) so
/// accepting an invite always produces a usable label on the other side.
///
/// The value describes the PICKER'S OWNER — "I am their ..." — which is what the
/// backend stores for the recipient.
private let relationshipOptions = [
    "Grandfather", "Grandmother",
    "Father", "Mother",
    "Paternal Uncle", "Paternal Aunt",
    "Maternal Uncle", "Maternal Aunt",
    "Spouse", "Brother", "Sister", "Cousin",
    "Son", "Daughter",
    "Nephew", "Niece",
    "Grandson", "Granddaughter",
    "Other"
]

// MARK: - ViewModel

@Observable @MainActor
final class FamilySheetViewModel {
    var isLoading = false
    var relationships: [RelationshipRecord] = []
    var dependents: [DependentRecord] = []
    var showError = false
    var showPaywall = false
    var errorMessage: String?
    var showAddForm = false
    var showAddDependent = false
    var confirmRemoveRecord: RelationshipRecord?
    var editingRelationship: RelationshipRecord?
    var maxDependents: Int?
    var dependentCount: Int?

    private let client = APIClient()

    /// §10.6: a backend limit/gate (429/403) must surface the paywall, not a generic error.
    /// Used by the add flows, which can return 403 `requiresUpgrade` (maxDependents / plan gate).
    private func handleActionError(_ error: Error) {
        if let api = error as? APIError, case .limitReached = api { showPaywall = true; return }
        if let api = error as? APIError, case .notAllowed = api { showPaywall = true; return }
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
        showError = true
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            async let relResp = client.send(Endpoint(path: "/api/users/relationships", showsLoader: false, loaderMessage: "Loading your family…"), as: RelationshipsResponse.self)
            async let depResp = client.send(Endpoint(path: "/api/dependents/users", showsLoader: false, loaderMessage: "Loading your family…"), as: DependentsResponse.self)
            let (rel, dep) = try await (relResp, depResp)
            relationships = rel.relationships
            dependents = dep.dependents
            maxDependents = dep.maxDependents
            dependentCount = dep.count
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func addDependent(name: String, type: String, dob: Date?, gender: String) async {
        struct Body: Encodable {
            let name: String
            let type: String
            let dateOfBirth: String?
            let gender: String?
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let dobStr = dob.map { fmt.string(from: $0) }
        do {
            let body = try JSONEncoder().encode(Body(name: name, type: type, dateOfBirth: dobStr, gender: gender.isEmpty ? nil : gender))
            try await client.send(Endpoint(path: "/api/dependents", method: .post, body: body, showsLoader: false, loaderMessage: "Adding dependent…"))
            await load()
        } catch {
            handleActionError(error)   // 403 requiresUpgrade → paywall
        }
    }

    func addRelationship(email: String, relationship: String) async {
        do {
            struct Wrapper: Decodable { let message: String? }
            let body = try JSONEncoder().encode(AddRelationshipRequest(email: email, relationship: relationship))
            try await client.send(Endpoint(path: "/api/user/relationship/request", method: .post, body: body, showsLoader: false, loaderMessage: "Sending invite…"))
            await load()
        } catch {
            handleActionError(error)   // plan gate → paywall
        }
    }

    func deleteDependent(_ id: String) async {
        do {
            try await client.send(Endpoint(path: "/api/dependents/\(id)", method: .delete, showsLoader: false, loaderMessage: "Removing dependent…"))
            dependents.removeAll { $0.id == id }
            if let c = dependentCount { dependentCount = max(0, c - 1) }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func remove(_ record: RelationshipRecord) async {
        guard let userId = record.userId else { return }
        do {
            struct Body: Encodable { let relativeUserId: String }
            let body = try JSONEncoder().encode(Body(relativeUserId: userId))
            try await client.send(Endpoint(path: "/api/user/relationship/delete", method: .post, body: body, showsLoader: false, loaderMessage: "Removing family member…"))
            relationships.removeAll { $0.id == record.id }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func cancelRequest(_ record: RelationshipRecord) async {
        guard let email = record.email else { return }
        do {
            struct Body: Encodable { let email: String }
            let body = try JSONEncoder().encode(Body(email: email))
            try await client.send(Endpoint(path: "/api/user/relationship/cancel", method: .post, body: body, showsLoader: false, loaderMessage: "Cancelling invite…"))
            relationships.removeAll { $0.id == record.id }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func updateRelationship(_ record: RelationshipRecord, newRelationship: String) async {
        guard let userId = record.userId else { return }
        do {
            struct Body: Encodable { let relativeUserId: String; let relationship: String }
            let body = try JSONEncoder().encode(Body(relativeUserId: userId, relationship: newRelationship))
            try await client.send(Endpoint(path: "/api/user/relationship/edit", method: .put, body: body, showsLoader: false, loaderMessage: "Updating relationship…"))
            if let idx = relationships.firstIndex(where: { $0.id == record.id }) {
                relationships[idx] = RelationshipRecord(
                    email: record.email, name: record.name, userId: record.userId,
                    relationship: newRelationship, status: record.status,
                    isPro: record.isPro, isCoveredByMyPlan: record.isCoveredByMyPlan
                )
            }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }
}

// MARK: - View

struct FamilySheetView: View {
    @State private var vm = FamilySheetViewModel()

    private var allEmpty: Bool { vm.relationships.isEmpty && vm.dependents.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && allEmpty {
                    ProgressView()
                } else if allEmpty {
                    ContentUnavailableView("No Family Members", systemImage: "person.2",
                        description: Text("Tap + to connect a family member or add a dependent."))
                } else {
                    familyList
                }
            }
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { vm.showAddForm = true } label: {
                            Label("Connect Family Member", systemImage: "person.badge.plus")
                        }
                        Button { vm.showAddDependent = true } label: {
                            Label("Add Dependent", systemImage: "person.crop.circle.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(vm.errorMessage ?? "Something went wrong.") }
            .sheet(isPresented: $vm.showPaywall) { PaywallView() }
            .confirmationDialog("Remove this person?", isPresented: Binding(
                get: { vm.confirmRemoveRecord != nil },
                set: { if !$0 { vm.confirmRemoveRecord = nil } }
            ), titleVisibility: .visible) {
                if let rec = vm.confirmRemoveRecord {
                    if rec.status == "pending" {
                        Button("Cancel Request", role: .destructive) {
                            Task { await vm.cancelRequest(rec) }
                            vm.confirmRemoveRecord = nil
                        }
                    } else {
                        Button("Remove", role: .destructive) {
                            Task { await vm.remove(rec) }
                            vm.confirmRemoveRecord = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { vm.confirmRemoveRecord = nil }
            }
            .sheet(isPresented: $vm.showAddForm) {
                AddFamilyMemberView { email, rel in
                    Task { await vm.addRelationship(email: email, relationship: rel) }
                }
            }
            .sheet(isPresented: $vm.showAddDependent) {
                AddDependentView { name, type, dob, gender in
                    Task { await vm.addDependent(name: name, type: type, dob: dob, gender: gender) }
                }
            }
            .sheet(item: $vm.editingRelationship) { rec in
                EditRelationshipSheet(record: rec) { newRel in
                    Task { await vm.updateRelationship(rec, newRelationship: newRel) }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var familyList: some View {
        List {
            if !vm.relationships.isEmpty {
                Section("Connections") {
                    ForEach(vm.relationships) { record in
                        FamilyRow(record: record)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    vm.confirmRemoveRecord = record
                                } label: {
                                    Label(record.status == "pending" ? "Cancel" : "Remove",
                                          systemImage: record.status == "pending" ? "xmark" : "person.badge.minus")
                                }
                                if record.status == "accepted" {
                                    Button {
                                        vm.editingRelationship = record
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.indigo)
                                }
                            }
                    }
                }
            }
            if !vm.dependents.isEmpty {
                let header = vm.maxDependents.map { "Dependents (\(vm.dependents.count)/\($0))" } ?? "Dependents"
                Section(header) {
                    ForEach(vm.dependents) { dep in
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.brandTeal)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(dep.name ?? "Unnamed").font(.headline)
                                if let t = dep.dependentType {
                                    Text(t.capitalized).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await vm.deleteDependent(dep.id) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct FamilyRow: View {
    let record: RelationshipRecord

    private var statusLevel: StatusLevel {
        switch record.status {
        case "accepted": return .green
        case "pending": return .yellow
        default: return .yellow
        }
    }

    private var statusLabel: String {
        switch record.status {
        case "accepted": return "Connected"
        case "pending": return "Pending"
        default: return record.status.capitalized
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "person.circle").font(.title2).foregroundStyle(Theme.brandTeal)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.name ?? record.email ?? "Unknown").font(.headline)
                if let rel = record.relationship {
                    Text(rel).font(.subheadline).foregroundStyle(.secondary)
                }
                if let email = record.email, record.name != nil {
                    Text(email).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: statusLabel, level: statusLevel)
                if record.isPro == true || record.isCoveredByMyPlan == true {
                    HStack(spacing: 4) {
                        if record.isCoveredByMyPlan == true { StatusPill(text: "Covered") }
                        if record.isPro == true { StatusPill(text: "Pro") }
                    }
                }
            }
        }
    }
}

// MARK: - Add Form

private struct AddFamilyMemberView: View {
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var relationship = relationshipOptions[0]
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("New Connection") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    Picker("I am their\u{2026}", selection: $relationship) {
                        ForEach(relationshipOptions, id: \.self) { Text($0) }
                    }
                }
                Section {
                    Text("A connection request will be sent to this email. They must accept to connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        isSending = true
                        onAdd(email, relationship)
                        dismiss()
                    }
                    .disabled(email.isEmpty || isSending)
                }
            }
        }
    }
}

// MARK: - Add Dependent Form

private let dependentTypes = ["Child", "Parent", "Grandparent", "Sibling", "Spouse", "Other"]
private let genderOptions = ["", "Male", "Female", "Other"]

private struct AddDependentView: View {
    let onAdd: (String, String, Date?, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = dependentTypes[0]
    @State private var dob: Date? = nil
    @State private var hasDOB = false
    @State private var gender = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dependent Info") {
                    TextField("Full name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(dependentTypes, id: \.self) { Text($0) }
                    }
                    Picker("Gender (optional)", selection: $gender) {
                        Text("Not specified").tag("")
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                        Text("Other").tag("Other")
                    }
                }
                Section("Date of Birth") {
                    Toggle("Include date of birth", isOn: $hasDOB)
                    if hasDOB {
                        DatePicker("Date of Birth",
                                   selection: Binding(get: { dob ?? Date() }, set: { dob = $0 }),
                                   in: ...Date(),
                                   displayedComponents: .date)
                    }
                }
                Section {
                    Text("Dependents are people in your care whose health you can track — such as children or elderly parents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Dependent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        isSaving = true
                        onAdd(name, type.lowercased(), hasDOB ? dob : nil, gender)
                        dismiss()
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }
}

// MARK: - Edit Relationship Sheet (mirrors Android showEditRelationshipDialog — PUT /api/user/relationship/edit)

private struct EditRelationshipSheet: View {
    let record: RelationshipRecord
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var relationship: String

    init(record: RelationshipRecord, onSave: @escaping (String) -> Void) {
        self.record = record
        self.onSave = onSave
        let stored = record.relationship ?? ""
        _relationship = State(initialValue:
            relationshipOptions.contains(stored) ? stored : relationshipOptions[0])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let name = record.name ?? record.email {
                        Text(name).font(.headline).foregroundStyle(.primary)
                    }
                    Text("Update how you are related to this person.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Relationship") {
                    Picker("I am their\u{2026}", selection: $relationship) {
                        ForEach(relationshipOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .navigationTitle("Edit Relationship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(relationship); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview { FamilySheetView() }
