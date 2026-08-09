import SwiftUI

/// Canonical sheet-dismiss control — a brand-teal (X) toolbar button. Replaces the "Done"/"Close"
/// text buttons on every bottom sheet so the close affordance is identical app-wide (CLAUDE.md §2A).
/// No custom glass/effect: in iOS 26 a toolbar button is already a native glass button with native
/// tap behavior — we only supply the teal glyph and let the system chrome do the rest (§C8).
///
/// Usage: `ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }`
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .foregroundStyle(Theme.brandTeal)
        }
        .accessibilityLabel("Close")
    }
}
