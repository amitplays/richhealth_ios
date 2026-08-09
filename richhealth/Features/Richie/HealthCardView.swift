import SwiftUI

/// One in-chat quick-log card rendered under an AI reply (Android ChatAdapter.HealthCardViewHolder).
/// Collapsed by default: teal icon + label + chevron. Expanded: native editable fields + an editable
/// time + Add / Dismiss. After Add → terminal (.added): collapsed, green check, "Added ·". Dismiss →
/// removed. Plain controls inside GlassCard (no per-field backgrounds — C3).
struct HealthCardView: View {
    @Bindable var card: HealthCardVM
    let onAdd: () async -> Void

    var body: some View {
        if card.status == .dismissed {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "xmark.circle").font(.caption)
                Text("Dismissed").font(.caption)
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s)
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    header
                    if card.expanded && card.status == .editable {
                        Divider()
                        fields
                        if let err = card.validationError {
                            Text(err).font(.caption).foregroundStyle(.red)  // error feedback
                        }
                        actionRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { card.expanded.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: card.status == .added ? "checkmark.circle.fill" : card.kindIcon)
                    .foregroundStyle(card.status == .added ? .green : Theme.brandTeal)  // green = saved (success)
                    .font(.subheadline)
                Text(card.headerLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if card.status == .editable {
                    Image(systemName: card.expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(card.status != .editable)
    }

    // MARK: - Fields per kind

    @ViewBuilder
    private var fields: some View {
        switch card.kind {
        case .symptom:     symptomFields
        case .measurement: measurementFields
        case .medication:  medicationFields
        case .period:      periodFields
        }
    }

    private var symptomFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("Symptom name", text: $card.title)
            severitySlider(title: "Severity", value: $card.severity)
            TextField("Duration (e.g. 2 days)", text: $card.duration)
            TextField("Notes (optional)", text: $card.notes, axis: .vertical)
            timePicker
        }
    }

    private var measurementFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("Measurement name", text: $card.title)
            // String value, default keyboard — "120/80" must be allowed (NOT numeric).
            TextField("Value", text: $card.value)
            TextField("Unit", text: $card.unit)
            TextField("Notes (optional)", text: $card.notes, axis: .vertical)
            timePicker
        }
    }

    private var medicationFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("Medication name", text: $card.name)
            TextField("Dosage", text: $card.dosage)
            // Frequency is read-only — trust the AI value (matches Android read-only dropdown).
            LabeledContent("Frequency") {
                Text(card.frequency).foregroundStyle(.secondary)
            }
            TextField("Purpose (optional)", text: $card.purpose)
            timePicker
        }
    }

    private var periodFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Picker("Flow", selection: $card.flowIntensity) {
                Text("Light").tag("light")
                Text("Medium").tag("medium")
                Text("Heavy").tag("heavy")
            }
            .pickerStyle(.segmented)
            severitySlider(title: "Pain / discomfort", value: $card.painLevel)
            TextField("Notes (optional)", text: $card.notes, axis: .vertical)
            timePicker
        }
    }

    // MARK: - Shared controls

    private func severitySlider(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title) {
                Text(card.severityLabel(value.wrappedValue))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = Int($0.rounded()) }),
                in: 1...5, step: 1
            )
            .tint(Theme.brandTeal)
        }
    }

    // Editable time — the added feature. date+time for symptom/measurement, date-only for medication/period.
    private var timePicker: some View {
        Group {
            if card.showsTime {
                DatePicker("Time", selection: $card.date, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
            } else {
                DatePicker("Date", selection: $card.date, in: ...Date(),
                           displayedComponents: .date)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button { Task { await onAdd() } } label: {
                if card.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Add").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.s)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandTeal)
            .disabled(card.isSaving)

            Button("Dismiss") {
                withAnimation(.easeInOut(duration: 0.2)) { card.status = .dismissed }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(card.isSaving)

            Spacer()
        }
        .padding(.top, Theme.Spacing.xs)
    }
}
