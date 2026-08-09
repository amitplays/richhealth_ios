import Foundation

/// Wraps /api/fitness/workouts — full CRUD for workout logs.
/// Confirmed against ../richhealthbackend/routes/workoutRoutes.js
/// mounted at "/api/fitness" (canonical) and "/api/workouts" (alias).
///
/// Note: GET /api/fitness/exercises is a backend stub — exercise catalogue is not yet live.
/// Workout creation flow must gracefully handle the unavailable catalogue.
struct WorkoutService {
    private let api = APIClient()

    func fetchWorkouts() async throws -> [WorkoutRecord] {
        try await api.send(Endpoint(path: "/api/fitness/workouts", showsLoader: false, loaderMessage: "Loading your workouts…"), as: [WorkoutRecord].self)
    }

    func fetchWorkout(id: String) async throws -> WorkoutRecord {
        try await api.send(Endpoint(path: "/api/fitness/workouts/\(id)", showsLoader: false, loaderMessage: "Loading workout…"), as: WorkoutRecord.self)
    }

    func createWorkout(name: String, exercises: [WorkoutExerciseInput]) async throws -> WorkoutRecord {
        let body = try JSONEncoder().encode(WorkoutCreateRequest(name: name, exercises: exercises))
        return try await api.send(
            Endpoint(path: "/api/fitness/workouts", method: .post, body: body, showsLoader: false, loaderMessage: "Saving workout…"),
            as: WorkoutRecord.self)
    }

    /// PUT replaces the entire exercises array — send the full list, not a diff.
    func updateWorkout(id: String, name: String, exercises: [WorkoutExerciseInput]) async throws -> WorkoutRecord {
        let body = try JSONEncoder().encode(WorkoutCreateRequest(name: name, exercises: exercises))
        return try await api.send(
            Endpoint(path: "/api/fitness/workouts/\(id)", method: .put, body: body, showsLoader: false, loaderMessage: "Updating workout…"),
            as: WorkoutRecord.self)
    }

    func deleteWorkout(id: String) async throws {
        try await api.send(Endpoint(path: "/api/fitness/workouts/\(id)", method: .delete, showsLoader: false, loaderMessage: "Deleting workout…"))
    }
}
