import SwiftUI
import UIKit

/// A password entry field with a trailing show/hide (eye) toggle.
/// Renders only the field + eye — no padding/background — so callers wrap it in
/// their own container (e.g. `brandedField` or the login glass row).
struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    /// `.password` for login, `.newPassword` for signup (enables Strong Password suggestions).
    var textContentType: UITextContentType = .password

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            .sensoryFeedback(.selection, trigger: isRevealed)   // native haptic on toggle
        }
    }
}
