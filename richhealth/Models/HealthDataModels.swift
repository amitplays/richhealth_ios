import Foundation

// MARK: - Shared

struct Pagination: Decodable {
    let total: Int
    let page: Int
    let limit: Int
    let pages: Int
}

// MARK: - Medical Data (Symptoms + Measurements) — /api/health/data

/// Unified backend model for both symptoms (type="symptom") and measurements (type="measurement").
struct MedicalDataRecord: Identifiable, Codable {
    let id: String
    var type: String          // "symptom" | "measurement"
    var title: String         // symptom name OR metric type (e.g. "Blood Pressure")
    var value: String?        // measurement value only
    var unit: String?         // measurement unit only
    var description: String?  // notes / description
    var dateTime: String?     // ISO 8601
    var severity: Int?        // symptom: 1–10
    var duration: String?     // symptom only
    var shareWithFamily: Bool
    var includeInChat: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, title, value, unit, description, dateTime, severity, duration
        case shareWithFamily, includeInChat, createdAt, updatedAt
    }
}

extension MedicalDataRecord {
    /// Provenance marker written into `description` by HealthKitManager for Apple Watch / Health
    /// imports. The backend has no `source` field and Android sends none, so we reuse `description`
    /// as the signal rather than change the shared schema.
    static let appleWatchSourceTag = "Imported from Apple Health"

    /// True when this measurement originated from Apple Health. The sentinel is preserved on edit
    /// (see MeasurementsSheetView.save), so editing an import keeps it grouped under Apple Watch.
    var isFromAppleWatch: Bool { description == Self.appleWatchSourceTag }

    /// Subtitle for list rows — hides the provenance sentinel (shown as a compact badge instead).
    var displaySubtitle: String? { isFromAppleWatch ? nil : description }
}

struct MedicalDataListResponse: Decodable {
    let data: [MedicalDataRecord]
    let pagination: Pagination?
}

struct MedicalDataStats: Decodable {
    let stats: StatsBody
    let recentItems: [MedicalDataRecord]?
    let commonSymptoms: [CommonSymptom]?

    struct StatsBody: Decodable {
        let symptomCount: Int
        let measurementCount: Int
        let totalCount: Int

        private enum CodingKeys: String, CodingKey { case symptomCount, measurementCount, totalCount }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            symptomCount    = (try? c.decode(Int.self, forKey: .symptomCount))    ?? 0
            measurementCount = (try? c.decode(Int.self, forKey: .measurementCount)) ?? 0
            totalCount      = (try? c.decode(Int.self, forKey: .totalCount))      ?? 0
        }
    }
    struct CommonSymptom: Decodable {
        let id: String
        let count: Int
        enum CodingKeys: String, CodingKey { case id = "_id"; case count }
    }
}

struct CreateMedicalDataRequest: Encodable {
    let type: String
    let title: String
    var value: String?
    var unit: String?
    var description: String?
    var dateTime: String?
    var severity: Int?
    var duration: String?
    var shareWithFamily: Bool = false
    var includeInChat: Bool = true
}

struct MedicalDataSingleResponse: Decodable {
    let message: String?
    let data: MedicalDataRecord
}

// MARK: - Medications — /api/health/medications

struct MedicationRecord: Identifiable, Codable {
    let id: String
    var name: String
    var dosage: String
    var frequency: String
    var customFrequency: String?
    var startDate: String?
    var endDate: String?
    var isOngoing: Bool
    var purpose: String?
    var prescribedBy: String?
    var medicationType: String
    var administrationMethod: String
    var notes: String?
    var shareWithFamily: Bool
    var includeInChat: Bool
    let isCurrent: Bool?
    let durationText: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, dosage, frequency, customFrequency, startDate, endDate, isOngoing
        case purpose, prescribedBy, medicationType, administrationMethod, notes
        case shareWithFamily, includeInChat, isCurrent, durationText, createdAt
    }

}

struct MedicationsListResponse: Decodable {
    let medications: [MedicationRecord]
    let pagination: Pagination?
}

struct MedicationStats: Decodable {
    let stats: StatsBody
    let recentMedications: [MedicationRecord]?  // absent when user has no medications

    struct StatsBody: Decodable {
        let currentCount: Int
        let completedCount: Int
        let totalCount: Int

        private enum CodingKeys: String, CodingKey { case currentCount, completedCount, totalCount }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            currentCount   = (try? c.decode(Int.self, forKey: .currentCount))   ?? 0
            completedCount = (try? c.decode(Int.self, forKey: .completedCount)) ?? 0
            totalCount     = (try? c.decode(Int.self, forKey: .totalCount))     ?? 0
        }
    }
}

struct CreateMedicationRequest: Encodable {
    let name: String
    let dosage: String
    let frequency: String
    var customFrequency: String?
    var startDate: String?
    var endDate: String?
    var isOngoing: Bool = true
    var purpose: String?
    var prescribedBy: String?
    var medicationType: String = "Prescription"
    var administrationMethod: String = "Oral"
    var notes: String?
    var shareWithFamily: Bool = false
    var includeInChat: Bool = true
}

struct MedicationSingleResponse: Decodable {
    let message: String?
    let medication: MedicationRecord
}

// MARK: - Period Logs — /api/health/period-logs

struct PeriodLogRecord: Identifiable, Codable {
    let id: String
    var startDate: String
    var endDate: String?
    var flowIntensity: String   // "light" | "medium" | "heavy"
    var painLevel: Int          // 1–5
    var notes: String?
    var shareWithFamily: Bool
    var includeInChat: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case startDate, endDate, flowIntensity, painLevel, notes
        case shareWithFamily, includeInChat, createdAt
    }

}

struct PeriodLogsListResponse: Decodable {
    let periodLogs: [PeriodLogRecord]
    let pagination: Pagination?
}

struct CreatePeriodLogRequest: Encodable {
    let startDate: String
    var endDate: String?
    let flowIntensity: String
    let painLevel: Int
    var notes: String?
    var shareWithFamily: Bool = false
    var includeInChat: Bool = true
}

struct PeriodLogSingleResponse: Decodable {
    let message: String?
    let data: PeriodLogRecord?
    let periodLog: PeriodLogRecord?

    // Backend uses either "data" or "periodLog" depending on the operation
    var record: PeriodLogRecord? { data ?? periodLog }
}

// MARK: - Medical Reports — /api/health/reports

struct MedicalReportRecord: Identifiable, Codable {
    let id: String
    var fileName: String
    var fileType: String
    var fileUrl: String?
    var reportType: String
    var status: String          // "uploaded" | "queued" | "processing" | "processed" | "failed"
    var fileSize: Int?
    var uploadDate: String?
    var aiAnalysisSummary: String?
    var aiAnalysisDetailed: String?
    var detailedSummary: String?
    var aiOpinion: String?
    var riskLevel: String?      // "low" | "moderate" | "high" | "critical"
    var urgency: String?        // "routine" | "soon" | "urgent" | "emergency"
    var reportTypeDetected: String?
    var analysisStatus: String? // "ok" | "extraction_failed" | "not_a_medical_report" | "unreadable" | "partial"
    var statusMessage: String?
    var recommendations: [String]?
    var followUpTests: [String]?
    var lifestyleAdvice: [String]?
    var possibleConditions: [PossibleCondition]?
    var keyFindings: [KeyFinding]?
    var shareWithFamily: Bool
    var includeInChat: Bool
    let createdAt: String?
    var canAnalyzeThisReport: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case fileName, fileType, fileUrl, reportType, status, fileSize, uploadDate
        case aiAnalysisSummary, aiAnalysisDetailed, detailedSummary, aiOpinion
        case riskLevel, urgency, reportTypeDetected, analysisStatus, statusMessage
        case recommendations, followUpTests, lifestyleAdvice
        case possibleConditions, keyFindings
        case shareWithFamily, includeInChat, createdAt, canAnalyzeThisReport
    }

    var isAnalysisProcessing: Bool { status == "queued" || status == "processing" }
    var isAnalysisTrustworthy: Bool {
        guard let s = analysisStatus else { return false }
        return s == "ok" || s == "partial"
    }
}

struct KeyFinding: Codable, Identifiable {
    var id: String { canonicalKey ?? parameter }
    let parameter: String
    let value: String?
    let unit: String?
    let normalRange: String?
    let status: String?         // "normal" | "high" | "low" | "critical"
    let canonicalKey: String?
    let valueNumeric: Double?
}

struct PossibleCondition: Codable, Identifiable {
    var id: String { name }
    let name: String
    let confidence: String?
    let rationale: String?
}

struct MedicalReportsListResponse: Decodable {
    let reports: [MedicalReportRecord]
    let canAnalyze: Bool?
}

struct UploadReportResponse: Decodable {
    let message: String?
    let report: MedicalReportRecord
    let autoAnalyzed: Bool?
    let canAnalyze: Bool?
}

struct AnalyzeReportResponse: Decodable {
    let message: String?
    let report: MedicalReportRecord
    let usageStatus: UsageStatus?

    struct UsageStatus: Decodable {
        let limitReached: Bool
        let used: Int
        let limit: Int
        let remaining: Int
    }
}

// MARK: - Family / Relationships — /api/users/relationships + /api/dependents/users

struct RelationshipRecord: Identifiable, Codable {
    var id: String { email ?? userId ?? name ?? UUID().uuidString }
    let email: String?
    let name: String?
    let userId: String?
    let relationship: String?
    let status: String         // "accepted" | "pending" | "rejected" | "dependent"
    let isPro: Bool?
    let isCoveredByMyPlan: Bool?
}

struct RelationshipsResponse: Decodable {
    let relationships: [RelationshipRecord]
    let isFamilyPlanOwner: Bool?
    let familyProMemberCount: Int?
    let maxFamilyMembers: Int?
}

struct DependentRecord: Identifiable, Codable {
    let id: String
    let name: String?
    let dependentType: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"; case name, dependentType
    }
}

struct DependentsResponse: Decodable {
    let dependents: [DependentRecord]
    let maxDependents: Int?
    let count: Int?
}

struct AddRelationshipRequest: Encodable {
    let email: String
    let relationship: String
}

// MARK: - Shared Helpers

extension MedicalDataRecord {
    // Custom decode in extension so the memberwise init (used by .placeholder) is still synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self, forKey: .id)
        type        = (try? c.decode(String.self, forKey: .type))        ?? "symptom"
        title       = (try? c.decode(String.self, forKey: .title))       ?? ""
        value       = try? c.decode(String.self, forKey: .value)
        unit        = try? c.decode(String.self, forKey: .unit)
        description = try? c.decode(String.self, forKey: .description)
        dateTime    = try? c.decode(String.self, forKey: .dateTime)
        severity    = try? c.decode(Int.self,    forKey: .severity)
        duration    = try? c.decode(String.self, forKey: .duration)
        shareWithFamily = (try? c.decode(Bool.self, forKey: .shareWithFamily)) ?? false
        includeInChat   = (try? c.decode(Bool.self, forKey: .includeInChat))   ?? true
        createdAt   = try? c.decode(String.self, forKey: .createdAt)
        updatedAt   = try? c.decode(String.self, forKey: .updatedAt)
    }

    /// Skeleton placeholder — used in loading states across sheet views.
    static let placeholder = MedicalDataRecord(
        id: UUID().uuidString, type: "symptom", title: "Placeholder",
        value: nil, unit: nil, description: "Some description", dateTime: nil,
        severity: 3, duration: "2 days", shareWithFamily: false, includeInChat: true,
        createdAt: nil, updatedAt: nil)
}

extension String {
    /// Parses an ISO 8601 timestamp and returns a short display date (e.g. "Jan 15, 2026").
    var shortDate: String {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: self) { return d.formatted(date: .abbreviated, time: .omitted) }
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: self) { return d.formatted(date: .abbreviated, time: .omitted) }
        // Fallback: try yyyy-MM-dd prefix
        if self.count >= 10, let d = DateFormatter.yyyyMMdd.date(from: String(prefix(10))) {
            return d.formatted(date: .abbreviated, time: .omitted)
        }
        return self
    }
}

// Custom decode in extensions so memberwise inits (used by placeholders) are still synthesized.

extension MedicationRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try  c.decode(String.self, forKey: .id)
        name                 = (try? c.decode(String.self, forKey: .name))                 ?? ""
        dosage               = (try? c.decode(String.self, forKey: .dosage))               ?? ""
        frequency            = (try? c.decode(String.self, forKey: .frequency))            ?? ""
        customFrequency      = try? c.decode(String.self, forKey: .customFrequency)
        startDate            = try? c.decode(String.self, forKey: .startDate)
        endDate              = try? c.decode(String.self, forKey: .endDate)
        isOngoing            = (try? c.decode(Bool.self,   forKey: .isOngoing))            ?? true
        purpose              = try? c.decode(String.self, forKey: .purpose)
        prescribedBy         = try? c.decode(String.self, forKey: .prescribedBy)
        medicationType       = (try? c.decode(String.self, forKey: .medicationType))       ?? "Prescription"
        administrationMethod = (try? c.decode(String.self, forKey: .administrationMethod)) ?? "Oral"
        notes                = try? c.decode(String.self, forKey: .notes)
        shareWithFamily      = (try? c.decode(Bool.self,   forKey: .shareWithFamily))      ?? false
        includeInChat        = (try? c.decode(Bool.self,   forKey: .includeInChat))        ?? true
        isCurrent            = try? c.decode(Bool.self,   forKey: .isCurrent)
        durationText         = try? c.decode(String.self, forKey: .durationText)
        createdAt            = try? c.decode(String.self, forKey: .createdAt)
    }
}

extension PeriodLogRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try  c.decode(String.self, forKey: .id)
        startDate       = (try? c.decode(String.self, forKey: .startDate)) ?? ""
        endDate         = try? c.decode(String.self, forKey: .endDate)
        flowIntensity   = (try? c.decode(String.self, forKey: .flowIntensity)) ?? "medium"
        painLevel       = (try? c.decode(Int.self,    forKey: .painLevel))     ?? 1
        notes           = try? c.decode(String.self, forKey: .notes)
        shareWithFamily = (try? c.decode(Bool.self,   forKey: .shareWithFamily)) ?? false
        includeInChat   = (try? c.decode(Bool.self,   forKey: .includeInChat))   ?? true
        createdAt       = try? c.decode(String.self, forKey: .createdAt)
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
