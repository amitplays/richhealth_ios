import Charts
import SwiftUI
import UniformTypeIdentifiers

private let reportTypes = [
    "Blood Test", "X-Ray", "MRI", "CT Scan", "Ultrasound",
    "ECG", "Medical Checkup", "Lab Report", "Prescription", "Other"
]

// MARK: - ViewModel

@Observable @MainActor
final class MedicalReportsSheetViewModel {
    var isLoading = false
    var items: [MedicalReportRecord] = []
    var searchText = ""
    var canAnalyze = false
    var showError = false
    var errorMessage: String?
    var showPaywall = false
    var showTrends = false
    var isUploading = false
    var uploadProgress = ""
    var pendingFileData: Data?
    var pendingFileName = ""
    var pendingMimeType = ""
    var showReportTypePicker = false
    var selectedReport: MedicalReportRecord?
    var pollingReportId: String?

    var filtered: [MedicalReportRecord] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter {
            $0.fileName.lowercased().contains(q) || $0.reportType.lowercased().contains(q)
        }
    }

    private let service = MedicalReportService()

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let response = try await service.list()
            items = response.reports
            canAnalyze = response.canAnalyze ?? false
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }

    func upload(reportType: String) async {
        guard let data = pendingFileData else { return }
        isUploading = true; uploadProgress = "Uploading…"; defer { isUploading = false }
        do {
            let response = try await service.upload(
                fileData: data, fileName: pendingFileName,
                mimeType: pendingMimeType, reportType: reportType
            )
            items.insert(response.report, at: 0)
            Analytics.shared.track(.reportUploaded)
            // If auto-analyzed, poll for completion
            if response.autoAnalyzed == true {
                uploadProgress = "Analyzing…"
                Task { await pollIfNeeded(response.report.id) }
            }
            pendingFileData = nil
        } catch let err as APIError {
            if case .limitReached = err { showPaywall = true }
            else if case .notAllowed = err { showPaywall = true }
            else { errorMessage = err.userMessage; showError = true }
        } catch {
            errorMessage = error.localizedDescription; showError = true
        }
        uploadProgress = ""
    }

    func requestAnalysis(_ id: String) async {
        do {
            let response = try await service.requestAnalysis(id)
            if let idx = items.firstIndex(where: { $0.id == id }) { items[idx] = response.report }
            Task { await pollIfNeeded(id) }
        } catch let err as APIError {
            if case .notAllowed = err { showPaywall = true }
            else if case .limitReached = err { showPaywall = true }
            else { errorMessage = err.userMessage; showError = true }
        } catch {
            errorMessage = error.localizedDescription; showError = true
        }
    }

    func pollIfNeeded(_ id: String) async {
        pollingReportId = id
        defer { if pollingReportId == id { pollingReportId = nil } }
        do {
            let completed = try await service.pollUntilComplete(id)
            if let idx = items.firstIndex(where: { $0.id == id }) { items[idx] = completed }
        } catch { /* silent — user can pull-to-refresh */ }
    }

    func delete(_ id: String) async {
        do {
            try await service.delete(id)
            items.removeAll { $0.id == id }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            showError = true
        }
    }
}

// MARK: - View

struct MedicalReportsSheetView: View {
    @State private var vm = MedicalReportsSheetViewModel()
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    placeholderList
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView("No Reports", systemImage: "doc.text.magnifyingglass",
                        description: Text("Upload a medical report to get started."))
                } else {
                    reportList
                }
            }
            .navigationTitle("Medical Reports")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "Search reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showTrends = true } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(vm.items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isUploading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(vm.uploadProgress).font(.caption)
                        }
                    } else {
                        Button { showFilePicker = true } label: {
                            Label("Upload", systemImage: "arrow.up.doc")
                        }
                    }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .fileImporter(isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image, .jpeg, .png]) { result in
                handleFilePick(result)
            }
            .confirmationDialog("Select Report Type", isPresented: $vm.showReportTypePicker, titleVisibility: .visible) {
                ForEach(reportTypes, id: \.self) { type in
                    Button(type) { Task { await vm.upload(reportType: type) } }
                }
                Button("Cancel", role: .cancel) { vm.pendingFileData = nil }
            }
            .sheet(item: $vm.selectedReport) { report in
                ReportAnalysisSheet(report: report, canAnalyze: vm.canAnalyze) {
                    Task { await vm.requestAnalysis(report.id) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(vm.errorMessage ?? "Something went wrong.") }
            .sheet(isPresented: $vm.showTrends) {
                ReportTrendsSheet(items: vm.items)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var reportList: some View {
        List {
            ForEach(vm.filtered) { item in
                ReportRow(item: item, isPolling: vm.pollingReportId == item.id)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.selectedReport = item }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(item.id) }
                        } label: { Label("Archive", systemImage: "archivebox") }
                    }
            }
        }
    }

    private var placeholderList: some View {
        List { ForEach(0..<4, id: \.self) { _ in ReportRow(item: .placeholder, isPolling: false).skeleton(isActive: true) } }
    }

    private func handleFilePick(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                vm.pendingFileData = data
                vm.pendingFileName = url.lastPathComponent
                vm.pendingMimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
                vm.showReportTypePicker = true
            } catch {
                vm.errorMessage = "Could not read file."; vm.showError = true
            }
        case .failure(let error):
            vm.errorMessage = error.localizedDescription; vm.showError = true
        }
    }
}

// MARK: - Report Row

private struct ReportRow: View {
    let item: MedicalReportRecord
    let isPolling: Bool

    private var statusLevel: StatusLevel {
        switch item.status {
        case "processed": return .green
        case "failed": return .red
        case "queued", "processing": return .yellow
        default: return .yellow
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            // Consistent teal icon container — matches HealthRecordRow treatment
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.icon)
                    .fill(Theme.brandTeal.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: item.fileType.contains("pdf") ? "doc.fill" : "photo.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.brandTeal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName).font(.headline).lineLimit(1)
                Text(item.reportType).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if isPolling {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Analyzing").font(.caption2)
                    }
                } else {
                    StatusPill(text: item.status.capitalized, level: statusLevel)
                }
                if let date = item.uploadDate ?? item.createdAt {
                    Text(date.shortDate).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}

// MARK: - Analysis Sheet

private struct ReportAnalysisSheet: View {
    let report: MedicalReportRecord
    let canAnalyze: Bool
    let onRequestAnalysis: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var riskLevel: StatusLevel? {
        switch report.riskLevel {
        case "low": return .green
        case "moderate": return .yellow
        case "high": return .orange
        case "critical": return .red
        default: return nil
        }
    }

    private var urgencyLevel: StatusLevel? {
        switch report.urgency {
        case "routine": return .green
        case "soon": return .yellow
        case "urgent": return .orange
        case "emergency": return .red
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.reportTypeDetected ?? report.reportType)
                            .font(.headline)
                        Text(report.fileName).font(.subheadline).foregroundStyle(.secondary)
                    }

                    // Status banner for untrustworthy analysis
                    if !report.isAnalysisTrustworthy, let msg = report.statusMessage, !msg.isEmpty {
                        GlassCard {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(StatusLevel.orange.color)
                                Text(msg).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Risk + urgency chips
                    if report.isAnalysisTrustworthy {
                        HStack(spacing: 8) {
                            if let risk = riskLevel, let rl = report.riskLevel {
                                StatusPill(text: "Risk: \(rl.capitalized)", level: risk)
                            }
                            if let urg = urgencyLevel, let u = report.urgency {
                                StatusPill(text: u.capitalized, level: urg)
                            }
                        }
                    }

                    // Summary
                    if let summary = report.aiAnalysisSummary, !summary.isEmpty {
                        analysisSection("Summary") { Text(summary).font(.body) }
                    }

                    // Key findings
                    if report.isAnalysisTrustworthy, let findings = report.keyFindings, !findings.isEmpty {
                        analysisSection("Key Findings") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(findings) { f in
                                    KeyFindingRow(finding: f)
                                }
                            }
                        }
                    }

                    // AI opinion
                    if report.isAnalysisTrustworthy, let opinion = report.aiOpinion, !opinion.isEmpty {
                        analysisSection("AI Opinion") { Text(opinion).font(.body) }
                    }

                    // Possible conditions
                    if report.isAnalysisTrustworthy, let conditions = report.possibleConditions, !conditions.isEmpty {
                        analysisSection("Possible Conditions") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(conditions) { c in
                                    HStack {
                                        Text(c.name).font(.subheadline).fontWeight(.medium)
                                        Spacer()
                                        if let conf = c.confidence {
                                            Text(conf.capitalized).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    if let rationale = c.rationale {
                                        Text(rationale).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Recommendations
                    if let recs = report.recommendations, !recs.isEmpty {
                        analysisSection("Recommendations") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(recs, id: \.self) { Text("• \($0)").font(.body) }
                            }
                        }
                    }

                    // Follow-up tests
                    if let tests = report.followUpTests, !tests.isEmpty {
                        analysisSection("Follow-up Tests") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(tests, id: \.self) { Text("• \($0)").font(.body) }
                            }
                        }
                    }

                    // Analyse / re-analyse CTA
                    if report.canAnalyzeThisReport == true || report.status == "failed" {
                        Button(action: { onRequestAnalysis(); dismiss() }) {
                            Label(report.status == "failed" ? "Retry Analysis" : "Analyze Report",
                                  systemImage: "brain.head.profile")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                    } else if report.status == "uploaded" && !canAnalyze {
                        Text("AI analysis requires a Pro plan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else if report.isAnalysisProcessing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Analysis in progress…").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Report Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetCloseButton { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func analysisSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct KeyFindingRow: View {
    let finding: KeyFinding

    private var level: StatusLevel {
        switch finding.status {
        case "normal": return .green
        case "high", "low": return .orange
        case "critical": return .red
        default: return .green
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.parameter).font(.subheadline).fontWeight(.medium)
                if let range = finding.normalRange {
                    Text("Normal: \(range)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let val = finding.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(val)\(finding.unit.map { " \($0)" } ?? "")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(level.color)
                    StatusPill(text: finding.status?.capitalized ?? "—", level: level)
                }
            }
        }
    }
}

extension MedicalReportRecord {
    static let placeholder = MedicalReportRecord(
        id: UUID().uuidString, fileName: "blood_test.pdf", fileType: "application/pdf",
        fileUrl: nil, reportType: "Blood Test", status: "processed", fileSize: nil,
        uploadDate: nil, aiAnalysisSummary: nil, aiAnalysisDetailed: nil,
        detailedSummary: nil, aiOpinion: nil, riskLevel: nil, urgency: nil,
        reportTypeDetected: nil, analysisStatus: nil, statusMessage: nil,
        recommendations: nil, followUpTests: nil, lifestyleAdvice: nil,
        possibleConditions: nil, keyFindings: nil,
        shareWithFamily: false, includeInChat: true, createdAt: nil, canAnalyzeThisReport: nil)
}

// MARK: - Trends Sheet (mirrors Android dialog_report_trend_chart — line chart grouped by canonicalKey)

private struct ReportTrendsSheet: View {
    let items: [MedicalReportRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKey = ""

    private struct TrendPoint: Identifiable {
        let id: String   // stable: "\(date.timeIntervalSince1970)-\(key)"
        let date: Date
        let value: Double
    }

    private struct TestSeries {
        let key: String
        let displayName: String
        let unit: String?
        let normalRange: String?
        let points: [TrendPoint]   // sorted ascending by date
    }

    private static func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: str) { return d }
        full.formatOptions = [.withInternetDateTime]
        return full.date(from: str)
    }

    private var allSeries: [TestSeries] {
        var grouped: [String: (name: String, unit: String?, range: String?, pts: [TrendPoint])] = [:]
        for report in items {
            guard let findings = report.keyFindings else { continue }
            guard let date = Self.parseDate(report.uploadDate ?? report.createdAt) else { continue }
            for finding in findings {
                guard let numeric = finding.valueNumeric, !numeric.isNaN else { continue }
                let key = finding.canonicalKey ?? finding.parameter
                let pt = TrendPoint(id: "\(date.timeIntervalSince1970)-\(key)", date: date, value: numeric)
                if grouped[key] == nil {
                    grouped[key] = (finding.parameter, finding.unit, finding.normalRange, [pt])
                } else {
                    grouped[key]!.pts.append(pt)
                }
            }
        }
        return grouped
            .filter { $0.value.pts.count >= 2 }
            .map { key, info in
                TestSeries(key: key, displayName: info.name, unit: info.unit,
                           normalRange: info.range,
                           points: info.pts.sorted { $0.date < $1.date })
            }
            .sorted { $0.points.count > $1.points.count }
    }

    private var activeSeries: TestSeries? {
        allSeries.first { $0.key == selectedKey } ?? allSeries.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if allSeries.isEmpty {
                    ContentUnavailableView(
                        "No Trend Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Upload and analyze at least two reports of the same type to see trends.")
                    )
                } else {
                    trendsContent
                }
            }
            .navigationTitle("Report Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetCloseButton { dismiss() } }
            }
        }
        .onAppear { selectedKey = allSeries.first?.key ?? "" }
    }

    private var trendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Picker("Parameter", selection: $selectedKey) {
                    ForEach(allSeries, id: \.key) { Text($0.displayName).tag($0.key) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, Theme.Spacing.m)

                if let series = activeSeries {
                    let values = series.points.map { $0.value }
                    let latest = series.points.last?.value ?? 0
                    let minVal = values.min() ?? 0
                    let maxVal = values.max() ?? 0
                    let unitSuffix = series.unit.map { " \($0)" } ?? ""

                    // Stats row — mirrors Android: latest · min-max · count
                    HStack(spacing: 0) {
                        statCell("Latest", "\(fmt(latest))\(unitSuffix)")
                        Divider().frame(height: 32)
                        statCell("Min", "\(fmt(minVal))\(unitSuffix)")
                        Divider().frame(height: 32)
                        statCell("Max", "\(fmt(maxVal))\(unitSuffix)")
                        Divider().frame(height: 32)
                        statCell("Reports", "\(series.points.count)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.m)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.card))
                    .padding(.horizontal, Theme.Spacing.m)

                    if let range = series.normalRange {
                        Text("Reference range: \(range)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.m)
                    }

                    // Swift Charts line + area (replaces MPAndroidChart LineChart)
                    Chart {
                        ForEach(series.points) { pt in
                            AreaMark(x: .value("Date", pt.date), y: .value(series.displayName, pt.value))
                                .foregroundStyle(Theme.brandTeal.opacity(0.15))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Date", pt.date), y: .value(series.displayName, pt.value))
                                .foregroundStyle(Theme.brandTeal)
                                .lineStyle(StrokeStyle(lineWidth: 3))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", pt.date), y: .value(series.displayName, pt.value))
                                .foregroundStyle(Theme.brandTeal)
                                .symbolSize(50)
                        }
                    }
                    .frame(height: 220)
                    .padding(.horizontal, Theme.Spacing.m)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { v in
                            if let d = v.as(Date.self) {
                                AxisValueLabel { Text(d, format: .dateTime.month(.abbreviated).day()) }
                            }
                            AxisGridLine()
                        }
                    }
                    .chartYAxisLabel(series.unit ?? "")
                }
            }
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

#Preview { MedicalReportsSheetView() }
