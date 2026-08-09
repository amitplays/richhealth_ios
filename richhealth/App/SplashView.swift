import SwiftUI

/// Branded launch screen shown during the .launching phase while AppEnvironment.bootstrap() runs.
/// Duration = however long the auth check takes — no artificial delay.
struct SplashView: View {
    @State private var logoScale: CGFloat = 0.65
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("RichHealth")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("Your Health, Intelligently Rich")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .opacity(textOpacity)
            }

            // Footer — mirrors Android RichLabs branding
            VStack {
                Spacer()
                Text("A product of RichLabs.io")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, Theme.Spacing.l)
            }
            .opacity(textOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.35).delay(0.2)) {
                textOpacity = 1.0
            }
        }
    }
}

// MARK: - Biometric lock overlay

/// Full-screen lock shown over the tab shell when biometric lock is active.
struct BiometricLockScreen: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.l) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                VStack(spacing: Theme.Spacing.s) {
                    Text("RichHealth is locked")
                        .font(.title3.bold())
                    Text("Verify your identity to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onUnlock) {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .foregroundStyle(Theme.brandTeal)
            }
            .padding(Theme.Spacing.l)
        }
        .onAppear { onUnlock() } // auto-trigger Face ID as soon as screen appears
    }
}
