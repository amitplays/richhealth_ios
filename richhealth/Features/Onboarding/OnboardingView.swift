import SwiftUI

struct OnboardingView: View {
    @State private var vm = OnboardingViewModel()
    var body: some View {
        VStack {
            Text("Onboarding")
                .font(.title.bold())
            Text("TODO: paged onboarding (goal, body, diet, activity, habits, medical, sleep/stress).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .task { await vm.load() }
    }
}

#Preview { OnboardingView() }
