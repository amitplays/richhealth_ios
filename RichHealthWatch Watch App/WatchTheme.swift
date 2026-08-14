import SwiftUI

/// RichHealth watch design tokens — mirrors iOS `Theme` so the two apps read as one.
/// Brand color is the ONLY accent (#008B8B, R:0 G:139 B:139). No other hues.
enum WatchTheme {
    static let brandTeal = Color(red: 0.0, green: 139.0 / 255.0, blue: 139.0 / 255.0)

    enum Spacing {
        static let xs: CGFloat = 3
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 16
    }

    enum Corner { static let card: CGFloat = 18 }
}

// MARK: - Glass surfaces (native Liquid Glass; falls back to material pre-26)

extension View {
    @ViewBuilder
    func rhGlass(cornerRadius: CGFloat = WatchTheme.Corner.card) -> some View {
        if #available(watchOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// A padded glass card — the watch equivalent of iOS `GlassCard { }`.
struct RHGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WatchTheme.Spacing.m)
            .rhGlass()
    }
}

/// Groups multiple glass shapes so they blend/morph as one system (native watchOS 26 behavior).
/// Falls back to a plain VStack container pre-26.
struct RHGlassGroup<Content: View>: View {
    var spacing: CGFloat = WatchTheme.Spacing.s
    @ViewBuilder var content: Content
    var body: some View {
        if #available(watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            VStack(spacing: spacing) { content }
        }
    }
}

// MARK: - Spinning brand logo (loader + idle motion)

/// The RichHealth logo that spins — used as the app's loading indicator and idle flourish.
struct BrandSpinner: View {
    var size: CGFloat = 30
    var continuous: Bool = true
    @State private var spinning = false
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(continuous ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                                  : .easeInOut(duration: 0.6), value: spinning)
            .onAppear { spinning = true }
            .accessibilityLabel("Loading")
    }
}

/// Page header: a small logo that gives one gentle spin when `busy` flips, plus a title.
struct BrandHeader: View {
    let title: String
    var busy: Bool = false
    var body: some View {
        HStack(spacing: WatchTheme.Spacing.s) {
            Image("AppLogo")
                .resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(busy ? 360 : 0))
                .animation(.easeInOut(duration: 0.8), value: busy)
            Text(title).font(.headline).foregroundStyle(.primary)
            Spacer()
        }
    }
}
