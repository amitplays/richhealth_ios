import Foundation
import Observation

/// Interaction state for one in-chat quick-log card (Android ChatAdapter.HealthCardViewHolder).
/// Held by RichieViewModel (keyed to the AI message) so the expanded/edited/terminal state survives
/// LazyVStack recycling — pure view @State would reset "Added" when scrolled off-screen, allowing a
/// double-log. Editable fields seed from the AI-suggested HealthCardDTO; save reuses the existing
/// HealthHub services (no new networking). The added feature is `date` — an editable time, defaulted
/// to now and always sent (the save endpoints already accept a timestamp, so no backend change).
@Observable
@MainActor
final class HealthCardVM: Identifiable {
    enum Status { case editable, added, dismissed }

    let id: UUID
    let kind: HealthCardKind

    // Editable fields (seeded from the suggested card).
    var title: String
    var value: String
    var unit: String
    var duration: String
    var notes: String
    var name: String
    var dosage: String
    var purpose: String
    var severity: Int
    var painLevel: Int
    var flowIntensity: String
    let frequency: String        // display-only — trust the backend value (matches Android read-only dropdown)
    var date: Date               // editable time — the added feature

    var expanded = false
    var status: Status = .editable
    var isSaving = false
    var validationError: String?

    private static let levelLabels = ["Very Mild", "Mild", "Moderate", "Severe", "Very Severe"]

    init(dto: HealthCardDTO) {
        id = dto.id
        kind = dto.kind
        title = dto.title
        value = dto.value
        unit = dto.unit
        duration = dto.duration
        name = dto.name
        dosage = dto.dosage
        purpose = dto.purpose
        severity = dto.severity
        painLevel = dto.painLevel
        flowIntensity = dto.flowIntensity
        frequency = dto.frequency
        switch dto.kind {
        case .symptom, .measurement: notes = dto.description
        case .period:                notes = dto.notes
        case .medication:            notes = ""
        }
        date = HealthCardVM.seedDate(kind: dto.kind, dateTime: dto.dateTime, startDate: dto.startDate)
    }

    // Header label — mirrors Android "Log symptom · <title>" etc., "Added · …" when terminal.
    var headerLabel: String {
        let added = status == .added
        switch kind {
        case .symptom:
            let base = added ? "Added" : "Log symptom"
            return title.isEmpty ? base : "\(base) · \(title)"
        case .measurement:
            let base = added ? "Added" : "Log measurement"
            return title.isEmpty ? base : "\(base) · \(title)"
        case .medication:
            let base = added ? "Added" : "Add medication"
            return name.isEmpty ? base : "\(base) · \(name)"
        case .period:
            return added ? "Added · Period" : "Log period"
        }
    }

    var kindIcon: String {
        switch kind {
        case .symptom:     return "cross.case"
        case .measurement: return "waveform.path.ecg"
        case .medication:  return "pills"
        case .period:      return "drop"
        }
    }

    /// Time-picker uses date+time for symptom/measurement, date-only for medication/period (matches sheets).
    var showsTime: Bool { kind == .symptom || kind == .measurement }

    func severityLabel(_ v: Int) -> String { Self.levelLabels[min(5, max(1, v)) - 1] }

    // ── Validation (match Android — inline error, don't disable the button) ────
    func validate() -> String? {
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch kind {
        case .symptom:
            if blank(title)    { return "Add a symptom name" }
            if blank(duration) { return "Add a duration" }
        case .measurement:
            if blank(title) { return "Add a measurement name" }
            if blank(value) { return "Add a value" }
            if blank(unit)  { return "Add a unit" }
        case .medication:
            if blank(name)   { return "Add a medication name" }
            if blank(dosage) { return "Add a dosage" }
        case .period:
            break
        }
        return nil
    }

    // ── Save — reuse existing HealthHub services; always send the picked time ──
    func save() async throws {
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let orNil = { (s: String) -> String? in
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? nil : v
        }
        switch kind {
        case .symptom:
            _ = try await HealthDataService().create(CreateMedicalDataRequest(
                type: "symptom", title: t(title), description: orNil(notes),
                dateTime: ISO8601DateFormatter().string(from: date),
                severity: severity, duration: t(duration),
                shareWithFamily: false, includeInChat: true))
        case .measurement:
            _ = try await HealthDataService().create(CreateMedicalDataRequest(
                type: "measurement", title: t(title), value: t(value), unit: t(unit),
                description: orNil(notes), dateTime: ISO8601DateFormatter().string(from: date),
                shareWithFamily: false, includeInChat: true))
        case .medication:
            _ = try await MedicationService().create(CreateMedicationRequest(
                name: t(name), dosage: t(dosage), frequency: frequency,
                startDate: DateFormatter.rhISO8601Date.string(from: date),
                isOngoing: true, purpose: orNil(purpose),
                medicationType: "Prescription", administrationMethod: "Oral",
                shareWithFamily: false, includeInChat: true))
        case .period:
            _ = try await PeriodLogService().create(CreatePeriodLogRequest(
                startDate: DateFormatter.rhISO8601Date.string(from: date),
                flowIntensity: flowIntensity, painLevel: painLevel, notes: orNil(notes),
                shareWithFamily: false, includeInChat: true))
        }
    }

    // ── Confirmation text posted to chat (Android confirmationText) ───────────
    func confirmationText() -> String {
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch kind {
        case .symptom:
            var detail = [severityLabel(severity)]
            if !t(duration).isEmpty { detail.append(t(duration)) }
            return "Logged symptom · \(t(title)) (\(detail.joined(separator: " · ")))"
        case .measurement:
            return "Logged measurement · \(t(title)) \(t(value)) \(t(unit))"
        case .medication:
            return "Added medication · \(t(name)) \(t(dosage))"
        case .period:
            return "Logged period · \(flowIntensity) flow · pain \(severityLabel(painLevel))"
        }
    }

    /// Seed the picker from the AI-suggested date when present, else now.
    private static func seedDate(kind: HealthCardKind, dateTime: String, startDate: String) -> Date {
        let raw = (kind == .period || kind == .medication) ? startDate : dateTime
        guard !raw.isEmpty else { return Date() }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        if raw.count >= 10, let d = DateFormatter.rhYYYYMMdd.date(from: String(raw.prefix(10))) { return d }
        return Date()
    }
}

// Same encoding the HealthHub sheets use — date-only UTC for medication/period, plain yyyy-MM-dd for parsing.
extension DateFormatter {
    static let rhISO8601Date: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    static let rhYYYYMMdd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
