import SwiftUI

/// Branded loading indicator — the iOS equivalent of Android's `SimpleProgress`
/// (layout_simple_progress.xml): full-screen dim + centered card with the RichHealth
/// logo spinning 0→360° over 2s and a status message (evenly padded on all sides).
/// The card uses the native Liquid Glass surface (GlassCard / .glassEffect), not a flat fill.
struct BrandedLoaderView: View {
    var message: String = "Loading…"

    // Scoped rotation — driven by .animation(_:value:) rather than a repeatForever in onAppear,
    // so the infinite spin can't leak into sibling layout.
    @State private var spinning = false

    var body: some View {
        ZStack {
            // Translucent tint veil (UI blocker). The .clear Liquid Glass pane looked wrong here,
            // so we use the material tint at 70% — subtle, lets the glass card stay the focus.
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.70)
                .ignoresSafeArea()

            GlassCard {
                VStack(spacing: Theme.Spacing.m) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(.linear(duration: 2).repeatForever(autoreverses: false),
                                   value: spinning)

                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                }
                // Even padding all around the logo + message (consistent on every side).
                .padding(Theme.Spacing.m)
                .frame(minWidth: 180)
            }
        }
        .allowsHitTesting(true)
        .onAppear { spinning = true }
    }
}

#Preview {
    ZStack {
        Color(.systemBackground)
        BrandedLoaderView(message: "Loading health data…")
    }
}
