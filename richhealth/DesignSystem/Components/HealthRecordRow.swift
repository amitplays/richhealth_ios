import SwiftUI

/// Canonical list row for all Health Hub data views (symptoms, measurements, medications,
/// period logs, medical reports).
///
/// This is just `StandardCard` at `.row` density — a list row IS the canonical card without the
/// GlassCard wrapper, so it uses the exact same fixed slot map (icon | title+subtitle | chip+date).
/// Kept as a thin, named wrapper so the existing call-sites and their skeleton/swipe/tap modifiers
/// stay unchanged. See `StandardCard` for the slot map.
struct HealthRecordRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let pillText: String?
    let pillLevel: StatusLevel?
    let date: String?
    /// Compact mode: smaller leading icon + tighter height, for subtitle-less rows
    /// (e.g. Apple Watch imports, which carry no description).
    var compact: Bool = false

    var body: some View {
        StandardCard(
            density: .row,
            compact: compact,
            icon: icon,
            title: title,
            subtitle: subtitle,
            statusText: pillText,
            statusLevel: pillLevel,
            date: date
        )
    }
}
