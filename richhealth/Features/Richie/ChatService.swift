import Foundation

/// Network layer for Richie chat. All paths confirmed against ../richhealthbackend/routes/chatRoutes.js.
struct ChatService {
    private let api = APIClient()

    // POST /api/chat/sessions
    // dependentId: pass the dependent's _id to chat on their behalf; nil = chat as self
    func createSession(title: String? = nil, dependentId: String? = nil) async throws -> ChatSessionDTO {
        let body = try JSONEncoder().encode(CreateSessionRequest(title: title, dependentId: dependentId))
        return try await api.send(
            // No global loader — part of the send flow, which shows its own thinking bubble.
            Endpoint(path: "/api/chat/sessions", method: .post, body: body, showsLoader: false),
            as: ChatSessionDTO.self
        )
    }

    // Dependents come from TWO backend sources: user-as-dependent accounts
    // (/api/dependents/users) and embedded child/deceased profiles (/api/dependents).
    // Android merges both; iOS must too, or embedded-profile relatives never appear in the
    // chat picker. Resilient: if one source fails, the other still populates the picker.
    func getDependents() async throws -> [DependentEntry] {
        async let usersResp    = api.send(Endpoint(path: "/api/dependents/users", showsLoader: false), as: DependentsListResponse.self)
        async let embeddedResp = api.send(Endpoint(path: "/api/dependents",       showsLoader: false), as: DependentsListResponse.self)
        let users    = (try? await usersResp)?.dependents ?? []
        let embedded = (try? await embeddedResp)?.dependents ?? []
        var seen = Set<String>()
        return (users + embedded).filter { seen.insert($0.id).inserted }   // de-dupe, keep order
    }

    // GET /api/chat/sessions (sorted newest-first, max 20 — backend enforced)
    func getSessions() async throws -> [ChatSessionDTO] {
        return try await api.send(
            Endpoint(path: "/api/chat/sessions", showsLoader: false, loaderMessage: "Loading your chats…"),
            as: [ChatSessionDTO].self
        )
    }

    // GET /api/chat/sessions/:sessionId/messages
    func getMessages(sessionId: String) async throws -> [ChatMessageDTO] {
        return try await api.send(
            Endpoint(path: "/api/chat/sessions/\(sessionId)/messages", showsLoader: false, loaderMessage: "Loading conversation…"),
            as: [ChatMessageDTO].self
        )
    }

    // POST /api/chat/sessions/:sessionId/messages
    // model: pass nil or "auto" to use session default; pass a specific model id to override.
    func sendMessage(_ text: String, sessionId: String, model: String = "auto") async throws -> SendMessageResponse {
        let modelType: String? = (model.isEmpty || model == "auto") ? nil : model
        let body = try JSONEncoder().encode(SendMessageRequest(message: text, modelType: modelType))
        return try await api.send(
            // No global loader — the chat UI shows its own thinking bubble while awaiting the reply.
            Endpoint(path: "/api/chat/sessions/\(sessionId)/messages", method: .post, body: body, showsLoader: false),
            as: SendMessageResponse.self
        )
    }

    // DELETE /api/chat/sessions/:sessionId
    func deleteSession(sessionId: String) async throws {
        try await api.send(
            Endpoint(path: "/api/chat/sessions/\(sessionId)", method: .delete, showsLoader: false, loaderMessage: "Deleting chat…")
        )
    }

    // GET /api/user/usage — plan tier + per-feature counts/limits (usage.chatSessions.limitReached).
    // Used to know the monthly chat-session limit BEFORE the first send, so we can block it up front.
    func fetchUsage() async throws -> UserUsageResponse {
        return try await api.send(
            Endpoint(path: "/api/user/usage", showsLoader: false),
            as: UserUsageResponse.self
        )
    }

    // GET /api/chat/suggestions
    func getSuggestions() async throws -> ChatSuggestionsResponse {
        return try await api.send(
            Endpoint(path: "/api/chat/suggestions", showsLoader: false, loaderMessage: "Loading suggestions…"),
            as: ChatSuggestionsResponse.self
        )
    }

    // POST /api/chat/sessions/:sessionId/log
    // Persists a quick-log confirmation as a type="log" message (Android logCardToChat).
    // Returns the created log message so it can be appended locally with its real _id.
    func logDataEntry(sessionId: String, text: String) async throws -> ChatMessageDTO {
        let body = try JSONEncoder().encode(["text": text])
        return try await api.send(
            Endpoint(path: "/api/chat/sessions/\(sessionId)/log", method: .post, body: body, showsLoader: false),
            as: ChatMessageDTO.self
        )
    }

    // POST /api/chat/sessions/:sessionId/extract-logs
    // Scans the conversation, creates the health records the user mentioned, and reports what was
    // created / remembered / skipped. User-initiated only (never auto-fired) to avoid surprise logging.
    func extractLogs(sessionId: String) async throws -> ExtractLogsResponse {
        return try await api.send(
            Endpoint(path: "/api/chat/sessions/\(sessionId)/extract-logs", method: .post, showsLoader: false, loaderMessage: "Logging from your chat…"),
            as: ExtractLogsResponse.self
        )
    }

    // PUT /api/chat/messages/:messageId/saved
    func toggleSaved(messageId: String) async throws {
        try await api.send(
            Endpoint(path: "/api/chat/messages/\(messageId)/saved", method: .put, showsLoader: false, loaderMessage: "Saving…")
        )
    }
}
