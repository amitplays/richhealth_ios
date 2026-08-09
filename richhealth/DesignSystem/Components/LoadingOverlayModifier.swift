import SwiftUI

// Android equivalent: SimpleProgress overlay — full-screen non-dismissible indicator
// shown during async operations (save, fetch). Captures all taps while active.
// Usage: .loadingOverlay(isActive: vm.isSaving, message: "Saving profile…")
struct LoadingOverlayModifier: ViewModifier {
    let isActive: Bool
    let message: String

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                        VStack(spacing: Theme.Spacing.s) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.brandTeal)
                                .scaleEffect(1.2)
                            Text(message)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(Theme.Spacing.l)
                        .background(.thickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card))
                    }
                    .allowsHitTesting(true)
                }
            }
    }
}

extension View {
    func loadingOverlay(isActive: Bool, message: String = "Loading…") -> some View {
        modifier(LoadingOverlayModifier(isActive: isActive, message: message))
    }
}
