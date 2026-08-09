import Foundation

/// Wraps /api/health/reports.
/// Confirmed against ../richhealthbackend/routes/medicalReportRoutes.js
/// File storage: MongoDB (not S3). Upload field name: "file". 16 MB max.
struct MedicalReportService {
    private let client = APIClient()

    // All calls here run inside the Medical Reports sheet, which has its own loading/processing
    // UI — so they don't trigger the global overlay (it renders behind the sheet).
    func list() async throws -> MedicalReportsListResponse {
        try await client.send(Endpoint(path: "/api/health/reports", showsLoader: false, loaderMessage: "Loading your reports…"),
                              as: MedicalReportsListResponse.self)
    }

    func get(_ id: String) async throws -> MedicalReportRecord {
        try await client.send(
            Endpoint(path: "/api/health/reports/\(id)", showsLoader: false, loaderMessage: "Loading report…"),
            as: MedicalReportRecord.self)
    }

    /// Multipart upload. reportType must be one of the backend enum values.
    func upload(fileData: Data, fileName: String, mimeType: String, reportType: String) async throws -> UploadReportResponse {
        try await client.sendMultipart(
            path: "/api/health/reports",
            fields: ["reportType": reportType],
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            showsLoader: false,
            loaderMessage: "Uploading your report…",
            as: UploadReportResponse.self
        )
    }

    /// POST /api/health/reports/:id/analyze — pro-gated (403 if free tier)
    func requestAnalysis(_ id: String) async throws -> AnalyzeReportResponse {
        try await client.send(
            Endpoint(path: "/api/health/reports/\(id)/analyze", method: .post, body: Data("{}".utf8),
                     showsLoader: false, loaderMessage: "Analyzing your report…"),
            as: AnalyzeReportResponse.self
        )
    }

    /// Polls GET /:id every 4 s up to 25 times (~100 s). Returns when processed/failed/timeout.
    /// get() already runs with the loader off — the sheet shows its own "processing" state.
    func pollUntilComplete(_ id: String) async throws -> MedicalReportRecord {
        for _ in 0..<25 {
            try await Task.sleep(nanoseconds: 4_000_000_000)
            let report = try await get(id)
            if report.status == "processed" || report.status == "failed" { return report }
        }
        // Return last known state even if still processing
        return try await get(id)
    }

    func delete(_ id: String) async throws {
        try await client.send(Endpoint(path: "/api/health/reports/\(id)", method: .delete, showsLoader: false, loaderMessage: "Deleting report…"))
    }
}
