import Observation

/// Global loading state for the branded UI blocker. Toggled automatically inside `APIClient`
/// around every REST call — a call begins on request start and ends on success OR failure.
/// Backed by a stack (not a bool) so concurrent calls (e.g. Health Hub's parallel loads) all
/// keep the loader up; it clears only when the last in-flight request finishes. Each entry
/// carries a context message so the loader can say what it's actually doing.
/// Mounted once in `RootView`, so every screen gets the effect.
@MainActor
@Observable
final class LoadingController {
    static let shared = LoadingController()
    private init() {}

    private var stack: [(id: Int, message: String)] = []
    private var nextID = 0

    var isActive: Bool { !stack.isEmpty }
    /// The message to show — the most recently started request wins.
    var message: String { stack.last?.message ?? "Loading…" }

    /// Start a loading context; returns a token to end it with.
    func begin(_ message: String) -> Int {
        nextID += 1
        stack.append((nextID, message))
        return nextID
    }

    func end(_ id: Int) { stack.removeAll { $0.id == id } }
}
