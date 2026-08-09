import SwiftUI
import Observation

/// Destinations pushed onto a NavigationStack. Extend per feature.
enum Route: Hashable {
    case healthAnalysis
    case doctorSearch
    case editProfile
    case paywall
}

@Observable
@MainActor
final class Router {
    var path: [Route] = []
    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
