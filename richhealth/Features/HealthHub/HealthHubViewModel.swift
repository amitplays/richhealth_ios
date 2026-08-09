import Foundation
import Observation

@Observable @MainActor
final class HealthHubViewModel {
    var isLoading = false
    var symptomCount = 0
    var measurementCount = 0
    var medicationCount = 0
    var reportCount = 0
    var recentItems: [MedicalDataRecord] = []
    var errorMessage: String?
    var showError = false

    private let dataService = HealthDataService()
    private let medService = MedicationService()
    private let reportService = MedicalReportService()
    private var hasLoaded = false

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        showError = false
        defer { isLoading = false }

        // Each load is independent — a failure (e.g. empty data for new user) does NOT
        // block the other loads or show an error. Empty data is a valid first-run state.
        async let statsResult = dataService.getStats()
        async let medStatsResult = medService.getStats()
        async let reportsResult = reportService.list()

        if let s = try? await statsResult {
            symptomCount = s.stats.symptomCount
            measurementCount = s.stats.measurementCount
            recentItems = s.recentItems ?? []
        }
        if let m = try? await medStatsResult {
            medicationCount = m.stats.currentCount
        }
        if let r = try? await reportsResult {
            reportCount = r.reports.count
        }
    }

    func reload() async {
        hasLoaded = false
        await load()
    }
}
