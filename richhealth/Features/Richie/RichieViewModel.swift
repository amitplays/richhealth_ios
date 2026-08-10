import Foundation
import Observation

/// Which kind of limit was hit — drives distinct in-chat banners.
/// sessionMessageLimit → this chat is full, can start a new one.
/// monthlySessionLimit → used all monthly chats, CANNOT start new until reset.
/// monthlyOrRate       → 429/403 quota; show paywall.
enum ChatLimitKind {
    case sessionMessageLimit
    case monthlySessionLimit
    case monthlyOrRate
}

@Observable
@MainActor
final class RichieViewModel {

    // ── UI state ──────────────────────────────────────────────────────────────
    var messages: [ChatMessage] = []
    var input = ""
    var isSending = false
    var isLoadingHistory = false
    var errorMessage: String? = nil
    var showPaywall = false
    var showHistory = false
    var limitKind: ChatLimitKind? = nil

    // ── Usage tracking (from SendMessageResponse) ─────────────────────────────
    var messagesUsed: Int? = nil
    var messageLimit: Int? = nil


    // ── Suggestions ───────────────────────────────────────────────────────────
    // Show first 3; keep remainder as backup swap-pool for "Not helpful" dismissals.
    var suggestions: [ChatSuggestion] = []
    var nudge: ChatNudge? = nil
    private var suggestionsBackup: [ChatSuggestion] = []

    // ── Chat font size (Aa cycle: 13 → 14 → 16 → 13) ─────────────────────────
    var chatFontSize: CGFloat = 14

    // ── Model selection ───────────────────────────────────────────────────────
    var selectedModel = "auto"
    var showModelPicker = false

    static let allModels: [(id: String, name: String, isPro: Bool)] = [
        ("auto",      "Auto",        false),
        ("gemini",    "Gemini",      false),
        ("mistral",   "Mistral",     false),
        ("deepseek",  "DeepSeek R1", false),
        ("llama",     "Llama 3.3",   false),
        ("gpt5.3",    "GPT-5.3",     true),
        ("claude4.5", "Claude 4.5",  true),
    ]

    var selectedModelDisplayName: String {
        RichieViewModel.allModels.first(where: { $0.id == selectedModel })?.name ?? "Auto"
    }

    // ── Session ───────────────────────────────────────────────────────────────
    var currentSession: ChatSessionDTO? = nil
    var sessions: [ChatSessionDTO] = []

    // ── Quick-log cards ───────────────────────────────────────────────────────
    // Interaction state per AI message (messageId → cards). Lives here (not view @State) so the
    // expanded/edited/added state survives LazyVStack recycling. Cleared on new chat / open session.
    var cardVMs: [String: [HealthCardVM]] = [:]

    // ── Dependents (family member selector — Android inputProfileChip) ────────
    var dependents: [DependentEntry] = []
    var selectedDependent: DependentEntry? = nil
    var showDependentPicker = false

    // ── Composer drawer (expand button → full-screen editor sheet) ────────────
    var showComposer = false

    private let service = ChatService()
    private var hasLoaded = false

    // ── Load ──────────────────────────────────────────────────────────────────

    // Launch loads only what the chat empty state needs. The health-summary subtitle was removed —
    // it block-fetched two slow /stats endpoints at launch (redundant with HealthHub) for one line.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        async let s: Void = loadSuggestions()
        async let d: Void = loadDependents()
        _ = await (s, d)
    }

    func loadDependents() async {
        dependents = (try? await service.getDependents()) ?? []
    }

    private func loadSuggestions() async {
        guard let resp = try? await service.getSuggestions() else { return }
        suggestions = Array(resp.suggestions.prefix(3))
        suggestionsBackup = resp.suggestions.count > 3 ? Array(resp.suggestions.dropFirst(3)) : []
        nudge = resp.nudge
    }

    // ── "Not helpful" — dismiss one suggestion and swap in a backup ───────────
    func dismissSuggestion(id: UUID) {
        suggestions.removeAll { $0.id == id }
        if !suggestionsBackup.isEmpty {
            suggestions.append(suggestionsBackup.removeFirst())
        }
    }

    // ── Aa font size cycle ────────────────────────────────────────────────────
    func cycleChatFontSize() {
        switch chatFontSize {
        case 13:  chatFontSize = 14
        case 14:  chatFontSize = 16
        default:  chatFontSize = 13
        }
    }

    var chatFontSizeLabel: String {
        switch chatFontSize {
        case 13: return "Aa"
        case 16: return "AA"
        default: return "Aa"
        }
    }

    // ── Send ──────────────────────────────────────────────────────────────────

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        // Monthly quota exhausted → surface the paywall drawer and DON'T send. The tap keeps
        // re-presenting the paywall (input is preserved). Session-message limit is handled
        // separately in the UI (Start-New-Chat banner), so it's not intercepted here.
        if limitKind == .monthlySessionLimit || limitKind == .monthlyOrRate {
            showPaywall = true
            return
        }

        input = ""
        isSending = true
        errorMessage = nil

        let tempId = UUID().uuidString
        messages.append(ChatMessage(id: tempId, text: text, kind: .user,
                                    reasoning: nil, isSaved: false, memorySaved: false))
        do {
            if currentSession == nil {
                let session = try await service.createSession(dependentId: selectedDependent?.id)
                currentSession = session
            }
            guard let sessionId = currentSession?.id else { throw APIError.invalidResponse }

            let response = try await service.sendMessage(text, sessionId: sessionId, model: selectedModel)

            if let idx = messages.firstIndex(where: { $0.id == tempId }) {
                messages[idx] = response.userMessage.toLocal()
            }
            var aiMessage = response.aiMessage.toLocal()
            // Show the "Remembered" badge on this fresh reply when the backend saved memories this turn.
            // Prefer the memoriesAdded list; fall back to the response bool or the DTO value.
            let remembered = !(response.memoriesAdded?.isEmpty ?? true)
                || (response.memorySaved ?? false)
            aiMessage.memorySaved = aiMessage.memorySaved || remembered
            // Attach quick-log cards (Android dataCards) to the AI reply — ephemeral, not persisted.
            let cards = response.dataCards ?? []
            aiMessage.cards = cards
            messages.append(aiMessage)
            if !cards.isEmpty {
                cardVMs[aiMessage.id] = cards.map { HealthCardVM(dto: $0) }
            }
            Analytics.shared.track(.richieMessageSent, ["model": selectedModel])  // count only, never content

            // Track usage for the ring in the input bar.
            if let used = response.messagesUsed { messagesUsed = used }
            if let limit = response.messageLimit { messageLimit = limit }
            if let used = response.sessionsUsed  { _ = used }   // available if needed later

            if response.isLimitReached == true {
                limitKind = .sessionMessageLimit
            }
        } catch {
            messages.removeAll { $0.id == tempId }
            handleSendError(error, originalText: text)
        }

        isSending = false
    }

    private func handleSendError(_ error: Error, originalText: String) {
        guard let apiErr = error as? APIError else {
            input = originalText
            errorMessage = error.localizedDescription
            return
        }
        switch apiErr {
        case .limitReached(_), .notAllowed(_):
            limitKind = .monthlyOrRate
            showPaywall = true

        case .server(let status, let msg) where status == 400:
            let lower = (msg ?? "").lowercased()
            if lower.contains("monthly session limit") || lower.contains("session limit reached") {
                // Monthly quota exhausted: user cannot start new chats until reset date.
                limitKind = .monthlySessionLimit
            } else if lower.contains("limit reached") || lower.contains("session limit") {
                limitKind = .sessionMessageLimit
            } else {
                input = originalText
                errorMessage = msg ?? apiErr.userMessage
            }

        default:
            input = originalText
            errorMessage = apiErr.userMessage
        }
    }

    // ── Session history ───────────────────────────────────────────────────────

    func loadSessions() async {
        isLoadingHistory = true
        sessions = (try? await service.getSessions()) ?? []
        isLoadingHistory = false
    }

    func openSession(_ session: ChatSessionDTO) async {
        currentSession = session
        messages = []
        cardVMs = [:]   // cards are ephemeral — never restored from history
        limitKind = session.isLimitReached == true ? .sessionMessageLimit : nil
        showHistory = false
        isLoadingHistory = true
        do {
            let dtos = try await service.getMessages(sessionId: session.id)
            messages = dtos.map { $0.toLocal() }
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? "Failed to load chat."
        }
        isLoadingHistory = false
    }

    func startNewChat() {
        currentSession = nil
        messages = []
        cardVMs = [:]
        limitKind = nil
        errorMessage = nil
        input = ""
        selectedDependent = nil
    }

    // ── Quick-log cards ─────────────────────────────────────────────────────────

    /// Save one card via the existing HealthHub service, then persist a "logged" confirmation to chat.
    /// On success: card goes terminal (.added). Validation fails inline; 429/403 surface the paywall.
    func addCard(_ card: HealthCardVM) async {
        guard card.status == .editable, !card.isSaving else { return }
        if let err = card.validate() { card.validationError = err; return }
        card.validationError = nil
        card.isSaving = true
        defer { card.isSaving = false }
        do {
            try await card.save()
            card.status = .added
            card.expanded = false
            await logCardConfirmation(card.confirmationText())
        } catch {
            handleCardError(error, card: card)
        }
    }

    /// POST the confirmation to /log so it survives reload, and append it locally (Android logCardToChat).
    private func logCardConfirmation(_ text: String) async {
        guard let sessionId = currentSession?.id else { return }
        if let dto = try? await service.logDataEntry(sessionId: sessionId, text: text) {
            messages.append(dto.toLocal())
        } else {
            // Non-fatal: the health record already saved — show the confirmation locally anyway.
            messages.append(ChatMessage(id: UUID().uuidString, text: text, kind: .log,
                                        reasoning: nil, isSaved: false, memorySaved: false))
        }
    }

    // ── Extract logs from the conversation ──────────────────────────────────────

    /// User-initiated: scan the current chat, create the health records mentioned, then append a
    /// .log confirmation summarizing what was logged + remembered. Never auto-fired (avoids surprise
    /// logging). Reuses the .log append pattern via logCardConfirmation.
    func extractLogsFromConversation() async {
        guard let sessionId = currentSession?.id else { return }
        do {
            let resp = try await service.extractLogs(sessionId: sessionId)
            await logCardConfirmation(Self.extractLogsSummary(resp))
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? "Couldn't log from this conversation."
        }
    }

    /// Build a one-line confirmation from the extract-logs result (e.g. "Logged 2 symptoms,
    /// 1 medication · remembered 3 details"). Empty result → a gentle "nothing new" note.
    private static func extractLogsSummary(_ resp: ExtractLogsResponse) -> String {
        func phrase(_ count: Int, _ singular: String, _ plural: String) -> String? {
            count > 0 ? "\(count) \(count == 1 ? singular : plural)" : nil
        }
        let created = resp.created
        let logged = [
            phrase(created?.symptoms?.count ?? 0, "symptom", "symptoms"),
            phrase(created?.measurements?.count ?? 0, "measurement", "measurements"),
            phrase(created?.medications?.count ?? 0, "medication", "medications"),
            phrase(created?.periods?.count ?? 0, "period", "periods"),
        ].compactMap { $0 }

        var parts: [String] = []
        if !logged.isEmpty { parts.append("Logged " + logged.joined(separator: ", ")) }
        let remembered = resp.memoriesAdded?.count ?? 0
        if remembered > 0 { parts.append("remembered \(remembered) \(remembered == 1 ? "detail" : "details")") }

        if parts.isEmpty { return "Nothing new to log from this conversation." }
        return parts.joined(separator: " · ")
    }

    private func handleCardError(_ error: Error, card: HealthCardVM) {
        guard let apiErr = error as? APIError else {
            card.validationError = error.localizedDescription
            return
        }
        switch apiErr {
        case .limitReached, .notAllowed:
            showPaywall = true
        default:
            card.validationError = apiErr.userMessage
        }
    }

    func deleteSession(_ session: ChatSessionDTO) async {
        _ = try? await service.deleteSession(sessionId: session.id)
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id { startNewChat() }
    }

    // ── Save / unsave ─────────────────────────────────────────────────────────

    func toggleSaved(message: ChatMessage) async {
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[idx].isSaved.toggle()
        do {
            try await service.toggleSaved(messageId: message.id)
        } catch {
            messages[idx].isSaved.toggle()
        }
    }
}
