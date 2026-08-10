import SwiftUI

/// A tappable option for `SelectableCardGrid` / `MultiSelectCardGrid`.
/// iOS equivalent of Android's `SelectableOption` (item_onboarding_card).
struct SelectableCardOption: Identifiable, Hashable {
    /// The value stored in the binding / sent in the signup payload.
    let value: String
    /// Display label shown on the card.
    let title: String
    /// Optional SF Symbol shown leading the label.
    let systemImage: String?
    /// When selected, reveals a free-text field (its text becomes the real value).
    let isOther: Bool
    /// A "None" style option — selecting it clears every other selection (multi-select only).
    let isNone: Bool

    var id: String { value }

    init(_ value: String,
         title: String,
         systemImage: String? = nil,
         isOther: Bool = false,
         isNone: Bool = false) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.isOther = isOther
        self.isNone = isNone
    }

    /// Sentinel value stored while the "Other" card is selected. The consumer swaps
    /// this for the typed free text before building its payload.
    static let otherValue = "__other__"

    /// Mirrors Android's `SelectableOption.other(...)` factory.
    static func other(_ title: String = "Other — you tell us",
                      systemImage: String = "pencil") -> SelectableCardOption {
        SelectableCardOption(otherValue, title: title, systemImage: systemImage, isOther: true)
    }
}

// MARK: - Single-select grid

/// A wrapping grid of tappable option cards bound to a single value.
/// Replaces Android's `SelectableCardAdapter` in single-select mode.
struct SelectableCardGrid: View {
    let options: [SelectableCardOption]
    @Binding var selection: String
    /// Bind to reveal a free-text field when an `isOther` card is selected.
    var otherText: Binding<String>? = nil
    var columns: Int = 2

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: max(1, columns))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            LazyVGrid(columns: gridItems, spacing: Theme.Spacing.s) {
                ForEach(options) { option in
                    SelectableCard(option: option, isSelected: selection == option.value) {
                        // Animate the mutation so progressive-reveal of the next question eases in.
                        withAnimation(.easeInOut(duration: 0.25)) { selection = option.value }
                    }
                }
            }
            if let otherText, selection == SelectableCardOption.otherValue {
                SelectableOtherField(text: otherText)
            }
        }
    }
}

// MARK: - Multi-select grid

/// A wrapping grid of tappable option cards bound to a `Set` of values.
/// Replaces Android's `SelectableCardAdapter` in multi-select mode.
struct MultiSelectCardGrid: View {
    let options: [SelectableCardOption]
    @Binding var selection: Set<String>
    /// Bind to reveal a free-text field when an `isOther` card is selected.
    var otherText: Binding<String>? = nil
    var columns: Int = 2

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: max(1, columns))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            LazyVGrid(columns: gridItems, spacing: Theme.Spacing.s) {
                ForEach(options) { option in
                    SelectableCard(option: option, isSelected: selection.contains(option.value)) {
                        toggle(option)
                    }
                }
            }
            if let otherText, selection.contains(SelectableCardOption.otherValue) {
                SelectableOtherField(text: otherText)
            }
        }
    }

    private func toggle(_ option: SelectableCardOption) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if selection.contains(option.value) {
                selection.remove(option.value)
                return
            }
            if option.isNone {
                // "None" is exclusive — clears every other selection.
                selection = [option.value]
            } else {
                // Any real selection clears the mutually-exclusive "None" options.
                for none in options where none.isNone { selection.remove(none.value) }
                selection.insert(option.value)
            }
        }
    }
}

// MARK: - Card + Other field (shared)

private struct SelectableCard: View {
    let option: SelectableCardOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let icon = option.systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.brandTeal : .secondary)
                        .frame(width: 26)
                }
                Text(option.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.brandTeal)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.input)
                    .strokeBorder(isSelected ? Theme.brandTeal : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct SelectableOtherField: View {
    @Binding var text: String

    var body: some View {
        TextField("Please specify…", text: $text)
            .autocorrectionDisabled()
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var single = "b"
        @State private var multi: Set<String> = ["y"]
        @State private var other = ""
        var body: some View {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    SelectableCardGrid(
                        options: [
                            .init("a", title: "Alpha", systemImage: "a.circle"),
                            .init("b", title: "Bravo", systemImage: "b.circle"),
                            .other()
                        ],
                        selection: $single,
                        otherText: $other
                    )
                    MultiSelectCardGrid(
                        options: [
                            .init("x", title: "Xray"),
                            .init("y", title: "Yankee"),
                            .init("none", title: "None", isNone: true)
                        ],
                        selection: $multi
                    )
                }
                .padding()
            }
        }
    }
    return PreviewWrapper()
}
