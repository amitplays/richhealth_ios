import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
private final class WorkoutSheetVM {
    var workouts: [WorkoutRecord] = []
    var isLoading = false
    var showAddSheet = false
    var newWorkoutName = ""
    var isSaving = false
    var error: String?

    private let service = WorkoutService()

    func load() async {
        isLoading = true
        defer { isLoading = false }
        workouts = (try? await service.fetchWorkouts()) ?? []
    }

    func addWorkout() async {
        let name = newWorkoutName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Exercise catalogue is a backend stub — create workout with empty exercises for now.
            let record = try await service.createWorkout(name: name, exercises: [])
            workouts.insert(record, at: 0)
            newWorkoutName = ""
            showAddSheet = false
        } catch {
            self.error = "Failed to save workout."
        }
    }

    func delete(id: String) async {
        try? await service.deleteWorkout(id: id)
        workouts.removeAll { $0.id == id }
    }
}

// MARK: - View

struct WorkoutSheetView: View {
    @State private var vm = WorkoutSheetVM()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading workouts…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "figure.run",
                        description: Text("Tap + to log your first workout session.")
                    )
                } else {
                    workoutList
                }
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await vm.load() }
        .sheet(isPresented: $vm.showAddSheet) { addWorkoutSheet }
    }

    // MARK: - List

    private var workoutList: some View {
        List {
            ForEach(vm.workouts) { workout in
                WorkoutRow(workout: workout)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                let ids = offsets.map { vm.workouts[$0].id }
                for id in ids { Task { await vm.delete(id: id) } }
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.load() }
    }

    // MARK: - Add sheet

    private var addWorkoutSheet: some View {
        NavigationStack {
            Form {
                Section("Workout Name") {
                    TextField("e.g. Morning Run, Leg Day…", text: $vm.newWorkoutName)
                        .submitLabel(.done)
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Exercise tracking will be available once the exercise library is ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = vm.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red) // error feedback
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.newWorkoutName = ""
                        vm.showAddSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await vm.addWorkout() }
                    }
                    .disabled(vm.newWorkoutName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Row

private struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text(workout.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(workout.date.shortDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if workout.exercises.isEmpty {
                    Text("No exercises logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(workout.exercises.prefix(3)) { ex in
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(ex.exercise.name)
                                    .font(.caption)
                                let weightText = ex.weight == 0 ? "Bodyweight" : "\(Int(ex.weight)) kg"
                                Text("• \(ex.sets)×\(ex.reps) \(weightText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if workout.exercises.count > 3 {
                            Text("+\(workout.exercises.count - 3) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
