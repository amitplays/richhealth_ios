import SwiftUI

/// Briefly slides the first row left to hint at swipe actions, then springs back.
/// Fires once per unique list context via AppStorage, so users are educated without repeated noise.
struct SwipeHintModifier: ViewModifier {
    let active: Bool
    @AppStorage private var hasShownHint: Bool
    @State private var offset: CGFloat = 0

    init(key: String, active: Bool) {
        self.active = active
        _hasShownHint = AppStorage(wrappedValue: false, "swipeHint_\(key)")
    }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                guard active, !hasShownHint else { return }
                hasShownHint = true
                withAnimation(.easeOut(duration: 0.35).delay(0.8)) {
                    offset = -42
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.25))
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                        offset = 0
                    }
                }
            }
    }
}

extension View {
    /// Teaches swipe affordance once on the first row of a list.
    /// Pass `isFirst: item.id == collection.first?.id` to target the correct row.
    func swipeHint(key: String, isFirst: Bool) -> some View {
        modifier(SwipeHintModifier(key: key, active: isFirst))
    }
}
