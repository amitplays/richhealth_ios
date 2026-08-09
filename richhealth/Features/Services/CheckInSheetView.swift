import SwiftUI
import Charts

// MARK: - Service

private struct CheckInService {
    private let client = APIClient()

    func getList() async throws -> CheckInListResponse {
        try await client.send(Endpoint(path: "/api/checkin/list", showsLoader: false, loaderMessage: "Loading your check-ins…"), as: CheckInListResponse.self)
    }

    func start() async throws -> CheckInStartResponse {
        try await client.send(
            Endpoint(path: "/api/checkin/start", method: .post, body: Data("{}".utf8), showsLoader: false, loaderMessage: "Starting your check-in…"),
            as: CheckInStartResponse.self
        )
    }

    func respond(sessionId: String, req: CheckInRespondRequest) async throws -> CheckInRespondResponse {
        try await client.send(
            Endpoint(path: "/api/checkin/sessions/\(sessionId)/respond", method: .post, body: try JSONEncoder().encode(req), showsLoader: false, loaderMessage: "Saving your answer…"),
            as: CheckInRespondResponse.self
        )
    }
}

// MARK: - ViewModel

@Observable @MainActor
final class CheckInSheetViewModel {
    var isLoading = false
    var sessions: [CheckInSessionRecord] = []
    var isDue = false
    var nextDueDate: String? = nil
    var canAccess = true
    var tier: String? = nil
    var errorMessage: String? = nil

    // Question flow
    var questions: [CheckInQuestion] = []
    var currentQuestionIndex = 0
    var selectedOption: CheckInOption? = nil
    var activeSessionId: String? = nil
    var isStarting = false
    var isSubmitting = false
    var showQuestionFlow = false

    private let service = CheckInService()

    var currentQuestion: CheckInQuestion? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    var isLastQuestion: Bool { currentQuestionIndex == questions.count - 1 }

    var completedCount: Int { sessions.filter { $0.status == "completed" }.count }
    var missedCount:   Int { sessions.filter { $0.status == "missed" }.count }
    var inProgressCount: Int { sessions.filter { $0.status == "in_progress" }.count }
    var hasChartData:  Bool { completedCount + missedCount + inProgressCount > 0 }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let resp = try await service.getList()
            canAccess = resp.canAccess
            tier = resp.tier
            isDue = resp.isDue ?? false
            nextDueDate = resp.nextDueDate
            sessions = resp.sessions
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }

    func startOrResume() async {
        isStarting = true; defer { isStarting = false }
        do {
            let resp = try await service.start()
            activeSessionId = resp.sessionId
            questions = resp.questions
            currentQuestionIndex = 0
            selectedOption = nil
            showQuestionFlow = true
        } catch let apiErr as APIError {
            errorMessage = apiErr.userMessage
        } catch {
            errorMessage = "Could not start check-in. Please try again."
        }
    }

    func submitAnswer() async {
        guard let q = currentQuestion, let opt = selectedOption, let sid = activeSessionId else { return }
        isSubmitting = true; defer { isSubmitting = false }
        do {
            let req = CheckInRespondRequest(questionId: q.id, selectedLabel: opt.label, selectedEmoji: opt.emoji, selectedValue: opt.value)
            _ = try await service.respond(sessionId: sid, req: req)
            if isLastQuestion {
                Analytics.shared.track(.checkinCompleted)
                showQuestionFlow = false
                await load()
            } else {
                currentQuestionIndex += 1
                selectedOption = nil
            }
        } catch {
            errorMessage = "Failed to save answer. Try again."
        }
    }
}

// MARK: - View

struct CheckInSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = CheckInSheetViewModel()
    @State private var expandedSessionId: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if !vm.canAccess {
                    noAccessView
                } else if vm.showQuestionFlow {
                    questionFlowView
                } else if vm.isLoading && vm.sessions.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    sessionListView
                }
            }
            .navigationTitle("Daily Check-In")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: No-access

    private var noAccessView: some View {
        ContentUnavailableView(
            "Check-In Not Available",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("Upgrade your plan to access daily health check-ins.")
        )
    }

    // MARK: Session list

    private var sessionListView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                if vm.isDue {
                    startCard
                } else if let nextDate = vm.nextDueDate {
                    allCaughtUpCard(nextDate: nextDate)
                }

                if vm.hasChartData { chartCard }

                if !vm.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("History")
                            .font(.headline)
                            .padding(.horizontal, Theme.Spacing.m)

                        ForEach(vm.sessions) { session in
                            SessionCard(
                                session: session,
                                isExpanded: expandedSessionId == session.id,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedSessionId = expandedSessionId == session.id ? nil : session.id
                                    }
                                },
                                onAction: { Task { await vm.startOrResume() } }
                            )
                            .padding(.horizontal, Theme.Spacing.m)
                        }
                    }
                } else if !vm.isDue {
                    ContentUnavailableView(
                        "No Check-Ins Yet",
                        systemImage: "calendar",
                        description: Text("Your check-in history will appear here.")
                    )
                    .padding(.top, Theme.Spacing.l)
                }
            }
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
    }

    private var startCard: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.brandTeal)
                Text("Time for your check-in!")
                    .font(.headline)
                Text("A few quick questions about how you're feeling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                let hasInProgress = vm.sessions.contains { $0.status == "in_progress" }
                Button {
                    Task { await vm.startOrResume() }
                } label: {
                    Group {
                        if vm.isStarting {
                            ProgressView().tint(.white)
                        } else {
                            Label(hasInProgress ? "Continue Check-In" : "Start Check-In",
                                  systemImage: hasInProgress ? "arrow.right.circle.fill" : "play.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandTeal)
                .disabled(vm.isStarting)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    private func allCaughtUpCard(nextDate: String) -> some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Theme.brandTeal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("All caught up!").font(.headline)
                    Text("Next check-in: \(formatDate(nextDate))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    // MARK: Bar chart

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                let maxVal = max(vm.completedCount, vm.missedCount, vm.inProgressCount, 1)
                Chart {
                    if vm.completedCount > 0 {
                        BarMark(x: .value("Status", "Completed"), y: .value("Count", vm.completedCount))
                            .foregroundStyle(Theme.brandTeal)
                    }
                    if vm.missedCount > 0 {
                        BarMark(x: .value("Status", "Missed"), y: .value("Count", vm.missedCount))
                            .foregroundStyle(Color.red)
                    }
                    if vm.inProgressCount > 0 {
                        BarMark(x: .value("Status", "In Progress"), y: .value("Count", vm.inProgressCount))
                            .foregroundStyle(Color.orange)
                    }
                }
                .frame(height: 120)
                .chartYScale(domain: 0...(maxVal + 1))

                let total = vm.completedCount + vm.missedCount + vm.inProgressCount
                Text("\(total) total · \(vm.completedCount) completed · \(vm.missedCount) missed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    // MARK: Question flow

    private var questionFlowView: some View {
        VStack(spacing: 0) {
            if !vm.questions.isEmpty {
                let progress = Double(vm.currentQuestionIndex) / Double(vm.questions.count)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.secondary.opacity(0.2))
                        Rectangle()
                            .fill(Theme.brandTeal)
                            .frame(width: geo.size.width * progress)
                            .animation(.easeInOut(duration: 0.3), value: vm.currentQuestionIndex)
                    }
                }
                .frame(height: 4)
            }

            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    if let q = vm.currentQuestion {
                        VStack(spacing: Theme.Spacing.s) {
                            Text("Question \(vm.currentQuestionIndex + 1) of \(vm.questions.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(q.text)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.m)
                        }
                        .padding(.top, Theme.Spacing.l)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.m) {
                            ForEach(q.options, id: \.label) { opt in
                                OptionCard(
                                    option: opt,
                                    isSelected: vm.selectedOption?.label == opt.label
                                ) {
                                    vm.selectedOption = opt
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.m)

                        Button {
                            Task { await vm.submitAnswer() }
                        } label: {
                            Group {
                                if vm.isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(vm.isLastQuestion ? "Done" : "Next")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                        .disabled(vm.selectedOption == nil || vm.isSubmitting)
                        .padding(.horizontal, Theme.Spacing.m)
                    }
                }
                .padding(.bottom, Theme.Spacing.l)
            }
        }
    }

    private func formatDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) {
            let out = DateFormatter()
            out.dateStyle = .medium; out.timeStyle = .none
            return out.string(from: d)
        }
        return iso
    }
}

// MARK: - Session Card

private struct SessionCard: View {
    let session: CheckInSessionRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAction: () -> Void

    var statusLevel: StatusLevel {
        switch session.status {
        case "completed":  return .green
        case "missed":     return .red
        case "in_progress": return .yellow
        default:           return .yellow
        }
    }

    var statusLabel: String {
        switch session.status {
        case "completed":  return "Completed"
        case "missed":     return "Missed"
        case "in_progress": return "In Progress"
        default:           return "Pending"
        }
    }

    var periodLabel: String {
        switch session.period {
        case "monthly":    return "Monthly"
        case "semi_weekly": return "Bi-Weekly"
        default:           return "Weekly"
        }
    }

    var dateLabel: String {
        let raw = session.scheduledFor ?? session.periodDate ?? ""
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = fmt.date(from: raw) else { return raw }
        let out = DateFormatter()
        switch session.period {
        case "monthly":    out.dateFormat = "MMMM yyyy"
        default:           out.dateFormat = "EEEE, MMM d"
        }
        return out.string(from: d)
    }

    var subInfo: String {
        switch session.status {
        case "completed":
            return "\(session.totalQuestions) answered"
        case "in_progress":
            let rem = session.totalQuestions - session.answeredCount
            return "\(rem) of \(session.totalQuestions) remaining"
        case "missed":
            return "Not completed in time"
        default:
            return "\(session.totalQuestions) question\(session.totalQuestions == 1 ? "" : "s")"
        }
    }

    var body: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(periodLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.brandTeal)
                            Text("·").foregroundStyle(.tertiary)
                            Text(dateLabel)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(subInfo).font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        StatusPill(text: statusLabel, level: statusLevel)
                        if session.status == "pending" || session.status == "in_progress" {
                            Button(session.status == "in_progress" ? "Continue" : "Start") { onAction() }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.brandTeal)
                        }
                        if session.status == "completed",
                           let responses = session.responses, !responses.isEmpty {
                            Button {
                                onToggle()
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if isExpanded, let responses = session.responses, !responses.isEmpty {
                    Divider()
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(responses.indices, id: \.self) { i in
                            let r = responses[i]
                            HStack {
                                Text(r.questionText ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(r.selectedEmoji ?? "") \(r.selectedLabel ?? "")")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.brandTeal)
                            }
                        }
                    }
                }
            }
            .opacity(session.status == "missed" ? 0.6 : 1)
        }
    }
}

// MARK: - Option Card (2-column grid for check-in answers)

private struct OptionCard: View {
    let option: CheckInOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(option.emoji).font(.system(size: 32))
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(Theme.Spacing.s)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                        .fill(Theme.brandTeal.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                                .strokeBorder(Theme.brandTeal, lineWidth: 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                        .fill(Color.secondary.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview { CheckInSheetView() }
