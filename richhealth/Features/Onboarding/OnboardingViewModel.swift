import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    var page = 0
    func load() async { /* TODO: hydrate step config from profile if any */ }
}
