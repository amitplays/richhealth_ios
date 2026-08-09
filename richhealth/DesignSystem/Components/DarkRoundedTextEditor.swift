import SwiftUI

/// Curved, near-black text editor for long-form input.
/// Single canonical style so the Profile "Custom Instructions" sheet and the Richie
/// composer drawer look identical: white text on `Theme.inputSurfaceDark`, rounded corners.
struct DarkRoundedTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 160

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden) // let our dark fill show through
                .foregroundStyle(.white)          // white text on the dark field (owner request)
                .tint(Theme.brandTeal)
                .padding(Theme.Spacing.s)
                .frame(minHeight: minHeight)

            // Placeholder — TextEditor has no native prompt param (confirmed: only text:/text:selection:),
            // so overlay one, aligned to its text inset, using the semantic .placeholder style.
            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.placeholder)
                    .padding(.horizontal, Theme.Spacing.s + 5)
                    .padding(.vertical, Theme.Spacing.s + 8)
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.inputSurfaceDark, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
