import SwiftUI

/// RichHealth watch design tokens — mirrors iOS `Theme` so the two apps read as one.
/// Brand color is the ONLY accent (Android rh_accent / iOS brandTeal = #008B8B, R:0 G:139 B:139).
/// No other hues — verdicts use teal + neutral only, per house rule "only our app color".
enum WatchTheme {
    static let brandTeal = Color(red: 0.0, green: 139.0 / 255.0, blue: 139.0 / 255.0)

    enum Spacing {
        static let xs: CGFloat = 3
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 16
    }

    enum Corner {
        static let card: CGFloat = 18   // slightly tighter than iOS 20 for the small screen
    }
}

/// Liquid Glass surface, mirroring iOS `GlassCard` (`.glassEffect(.regular, …)`).
/// Falls back to a material on watchOS < 26 so it always compiles/renders.
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

/// A padded glass card container — the watch equivalent of iOS `GlassCard { }`.
struct RHGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WatchTheme.Spacing.m)
            .rhGlass()
    }
}
