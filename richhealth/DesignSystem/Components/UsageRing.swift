import SwiftUI

/// Circular usage indicator. Replaces Android UsageRing.java.
///
/// Built from a trimmed `Circle` (NOT `Gauge`): the `.accessoryCircularCapacity` gauge style has a
/// fixed ~50pt intrinsic size and ignores `.frame(...)`, so it overflowed its container. A stroked
/// Circle scales exactly to whatever frame the caller sets (e.g. 16×16 in the Richie input bar).
struct UsageRing: View {
    var value: Double            // 0...1
    var lineWidth: CGFloat = 2.5

    private var clamped: Double { max(0, min(value, 1)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.brandTeal.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Theme.brandTeal, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
        }
    }
}
