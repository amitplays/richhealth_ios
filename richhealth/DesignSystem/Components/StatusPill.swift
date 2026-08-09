import SwiftUI

// ── Canonical status levels (see CLAUDE.md §12) ───────────────────────────────

/// The four allowed colours for any status-indicating pill in the app.
/// Use these everywhere instead of ad-hoc tints so all status signals look consistent.
enum StatusLevel {
    case green    // Good, healthy, normal, verified, within limits
    case yellow   // Borderline, pending, mild warning, approaching limit
    case orange   // Elevated, moderate concern, caution (use sparingly)
    case red      // Critical, bad, expired, limit reached, error

    var color: Color {
        switch self {
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        }
    }
}

// ── StatusPill ────────────────────────────────────────────────────────────────

/// Small status/plan pill. Replaces Android StatusPill.java / PlanBadge.java.
///
/// Status use (pass a level):
///   StatusPill(text: "Normal",   level: .green)
///   StatusPill(text: "Caution",  level: .yellow)
///   StatusPill(text: "Elevated", level: .orange)
///   StatusPill(text: "Critical", level: .red)
///
/// Non-status use (plan badge, Pro label, etc. — defaults to brand teal):
///   StatusPill(text: "Pro")
///   StatusPill(text: "Beta", tint: .purple)
struct StatusPill: View {
    var text: String
    var level: StatusLevel? = nil     // when set, overrides tint
    var tint: Color = Theme.brandTeal // used only when level is nil

    private var effectiveTint: Color { level?.color ?? tint }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // Non-status badges (no level): solid teal background + white text (matches Android plan pill).
            // Status indicators (level set): colored text + translucent background for readability.
            .foregroundStyle(level != nil ? effectiveTint : .white)
            .background(level != nil ? effectiveTint.opacity(0.15) : effectiveTint, in: Capsule())
    }
}
