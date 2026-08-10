import Foundation

// ── Local display model ──────────────────────────────────────────────────────

struct ChatMessage: Identifiable {
    enum Kind { case user, ai, log }
    let id: String
    let text: String
    let kind: Kind
    let reasoning: String?   // AI thinking trace — nil when absent or empty
    var isSaved: Bool
    // Mutable so send() can set it from the response's memoriesAdded (badge shows on fresh replies,
    // not only after reload). Persisted value still arrives via ChatMessageDTO.memorySaved on reload.
    var memorySaved: Bool
    // Quick-log cards attached to an AI reply (Android dataCards). Ephemeral — never persisted.
    var cards: [HealthCardDTO] = []
}

// ── Quick-log cards (Android dataCards — POST /api/chat/sessions/:id/messages) ─
// Present only when the user's aiPreferences.autofillCards is ON (backend-gated — no client gate).
// Cards are ephemeral: never persisted, don't reappear on session reload.

enum HealthCardKind: String, Decodable { case symptom, measurement, medication, period }

/// One AI-suggested quick-log card. Discriminated by `kind`. Missing fields defaulted on decode,
/// enums enforced (severity/painLevel clamped 1–5, flowIntensity normalized, frequency non-empty).
struct HealthCardDTO: Decodable, Identifiable {
    let id = UUID()
    let kind: HealthCardKind
    // symptom + measurement
    let title: String
    let severity: Int        // symptom
    let duration: String     // symptom
    let description: String  // symptom/measurement notes
    let value: String        // measurement (string — "120/80" allowed)
    let unit: String         // measurement
    // medication
    let name: String
    let dosage: String
    let frequency: String    // one of the fixed enum values; display-only
    let purpose: String
    // shared suggested time
    let dateTime: String
    // period
    let startDate: String
    let flowIntensity: String
    let painLevel: Int
    let notes: String

    enum CodingKeys: String, CodingKey {
        case kind, title, severity, duration, description, value, unit
        case name, dosage, frequency, purpose, dateTime
        case startDate, flowIntensity, painLevel, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind          = (try? c.decode(HealthCardKind.self, forKey: .kind)) ?? .symptom
        title         = (try? c.decode(String.self, forKey: .title)) ?? ""
        severity      = HealthCardDTO.clamp((try? c.decode(Int.self, forKey: .severity)) ?? 3)
        duration      = (try? c.decode(String.self, forKey: .duration)) ?? ""
        description   = (try? c.decode(String.self, forKey: .description)) ?? ""
        value         = (try? c.decode(String.self, forKey: .value)) ?? ""
        unit          = (try? c.decode(String.self, forKey: .unit)) ?? ""
        name          = (try? c.decode(String.self, forKey: .name)) ?? ""
        dosage        = (try? c.decode(String.self, forKey: .dosage)) ?? ""
        let freq      = (try? c.decode(String.self, forKey: .frequency)) ?? ""
        frequency     = freq.isEmpty ? "As needed" : freq
        purpose       = (try? c.decode(String.self, forKey: .purpose)) ?? ""
        dateTime      = (try? c.decode(String.self, forKey: .dateTime)) ?? ""
        startDate     = (try? c.decode(String.self, forKey: .startDate)) ?? ""
        flowIntensity = HealthCardDTO.normalizeFlow((try? c.decode(String.self, forKey: .flowIntensity)) ?? "medium")
        painLevel     = HealthCardDTO.clamp((try? c.decode(Int.self, forKey: .painLevel)) ?? 3)
        notes         = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    private static func clamp(_ v: Int) -> Int { min(5, max(1, v)) }
    private static func normalizeFlow(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("light") || s.contains("spot") { return "light" }
        if s.contains("heavy") { return "heavy" }
        return "medium"
    }
}

// ── Server DTOs (match backend JSON exactly) ─────────────────────────────────

/// Returned by POST /api/chat/sessions and GET /api/chat/sessions.
/// `id` maps to the `sessionId` UUID field used in all API paths.
struct ChatSessionDTO: Identifiable, Decodable {
    let id: String           // "sessionId" UUID — used as path param
    let title: String
    let lastMessage: String?
    let messageCount: Int?
    let isLimitReached: Bool?
    let timestamp: String?   // ISO 8601 date string

    enum CodingKeys: String, CodingKey {
        case id = "sessionId"
        case title, lastMessage, messageCount, isLimitReached, timestamp
    }
}

/// Returned by GET /api/chat/sessions/:sessionId/messages and nested in SendMessageResponse.
struct ChatMessageDTO: Decodable {
    let id: String           // MongoDB "_id" — used for toggleSaved
    let message: String
    let isFromAI: Bool
    let type: String?        // "log" for quick-log confirmation entries
    let reasoning: String?   // thinking trace (showThinking mode)
    let isSaved: Bool?
    let memorySaved: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case message, isFromAI, type, reasoning, isSaved, memorySaved
    }

    func toLocal() -> ChatMessage {
        let kind: ChatMessage.Kind
        if !isFromAI { kind = .user }
        else if type == "log" { kind = .log }
        else { kind = .ai }
        return ChatMessage(
            id: id,
            text: message,
            kind: kind,
            reasoning: reasoning.flatMap { $0.isEmpty ? nil : $0 },
            isSaved: isSaved ?? false,
            memorySaved: memorySaved ?? false
        )
    }
}

/// Body for POST /api/chat/sessions/:sessionId/messages.
/// sessionId is a PATH parameter — NOT in this body.
/// modelType: optional override; nil → backend uses session default ("auto").
struct SendMessageRequest: Encodable {
    let message: String
    let modelType: String?
}

/// Body for POST /api/chat/sessions.
struct CreateSessionRequest: Encodable {
    let title: String?
    let dependentId: String?  // nil = chatting as self; set at session creation, not per-message
}

/// A family member / dependent the user can chat on behalf of.
/// Returned by GET /api/dependents/users (active dependents only).
struct DependentEntry: Identifiable, Decodable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

struct DependentsListResponse: Decodable {
    let dependents: [DependentEntry]
}

/// One saved memory as returned by POST .../messages — the backend sends objects
/// ({_id, fact, category}), NOT plain strings, so we decode the object and read `fact`.
struct MemoryFactDTO: Decodable { let fact: String? }

/// Response from POST /api/chat/sessions/:sessionId/messages.
struct SendMessageResponse: Decodable {
    let userMessage: ChatMessageDTO
    let aiMessage: ChatMessageDTO
    let messagesUsed: Int?
    let messageLimit: Int?
    let isLimitReached: Bool?
    let sessionsUsed: Int?
    let sessionLimit: Int?
    // Quick-log cards for the AI reply — absent or [] is normal (feature off / nothing detected).
    let dataCards: [HealthCardDTO]?
    // Memories the backend saved from this turn (array of objects). Non-empty → show the
    // "Remembered" badge on the fresh AI reply. `memorySaved` is a fallback for a bool shape.
    let memoriesAdded: [MemoryFactDTO]?
    let memorySaved: Bool?
}

// ── Extract logs (POST /api/chat/sessions/:sessionId/extract-logs) ─────────────
// Scans the conversation and creates health records the user mentioned, then reports what
// was created / remembered / skipped. All fields optional — the backend omits empty groups.

/// Response from POST /api/chat/sessions/:sessionId/extract-logs.
struct ExtractLogsResponse: Decodable {
    /// One created record. `title` is used by symptoms/measurements; `name` by medications;
    /// periods carry only `id`. All optional so a single type covers every group.
    struct CreatedItem: Decodable {
        let id: String?
        let title: String?
        let name: String?
    }

    struct Created: Decodable {
        let symptoms: [CreatedItem]?
        let measurements: [CreatedItem]?
        let medications: [CreatedItem]?
        let periods: [CreatedItem]?
    }

    struct SkippedItem: Decodable {
        let type: String?
        let title: String?
        let reason: String?
    }

    let created: Created?
    let memoriesAdded: [String]?
    let skipped: [SkippedItem]?
}

/// A tap-to-ask starter question from GET /api/chat/suggestions.
struct ChatSuggestion: Identifiable, Decodable {
    let id = UUID()
    let q: String    // question text
    let why: String  // one-line reason personalised to the user

    enum CodingKeys: String, CodingKey { case q, why }
}

/// Progressive data nudge returned alongside suggestions.
struct ChatNudge: Decodable {
    let text: String
    let type: String
    let action: String
}

/// Response from GET /api/chat/suggestions.
struct ChatSuggestionsResponse: Decodable {
    let suggestions: [ChatSuggestion]
    let nudge: ChatNudge?
}
