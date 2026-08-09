import SwiftUI

/// Rounded card. Replaces Android CardView + bg_rounded_* drawables.
/// Stub uses a material background (guaranteed to compile). Switch to Liquid Glass with
/// `.glassEffect(in: RoundedRectangle(cornerRadius: 20))` once verified in Xcode.
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Theme.Spacing.cardPadding)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.card))
    }
}
