import Foundation

// MARK: - Shared

/// Usage quota returned by NutriCheck and DietaryInsights endpoints.
struct UsageStatus: Codable {
    let feature: String?
    let count: Int?
    let limit: Int?
    let remaining: Int?
    let limitReached: Bool?
    let resetAt: String?   // backend sends resetAt, not remaining

    enum CodingKeys: String, CodingKey {
        case feature, count, limit, remaining, limitReached, resetAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feature      = try c.decodeIfPresent(String.self, forKey: .feature)
        remaining    = try c.decodeIfPresent(Int.self,    forKey: .remaining)
        limitReached = try c.decodeIfPresent(Bool.self,   forKey: .limitReached)
        resetAt      = try c.decodeIfPresent(String.self, forKey: .resetAt)
        // MongoDB may encode integer counts as floats (e.g. 0.0); try Int first, fall back to Double→Int
        count = (try? c.decode(Int.self, forKey: .count))
             ?? (try? c.decode(Double.self, forKey: .count)).map(Int.init)
        limit = (try? c.decode(Int.self, forKey: .limit))
             ?? (try? c.decode(Double.self, forKey: .limit)).map(Int.init)
    }
}

// MARK: - Briefing  /api/insights/briefing

struct BriefingResponse: Codable {
    let cards: [BriefingCard]
    let generatedAt: String?
    let source: String?   // "cache" | "fresh" | "empty"
}

struct BriefingCard: Codable, Identifiable {
    var id: String { title }
    let priority: String  // "urgent" | "high" | "medium" | "low"
    let title: String
    let points: [String]

    var statusLevel: StatusLevel {
        switch priority {
        case "urgent": return .red
        case "high":   return .orange
        case "medium": return .yellow
        default:       return .green
        }
    }
}

// MARK: - Daily Digest  /api/insights/daily-digest

struct DailyDigestResponse: Codable {
    let content: String
    let city: String?
    let aqiValue: Int?
    let aqiLabel: String?
    let aqiColor: String?
    let showAqi: Bool?
    let generatedAt: String?   // when this advisory was generated → "Updated X ago" date
    let stale: Bool?           // health data changed after it was generated → attention chevron
}

// MARK: - Dietary Insights  /api/insights/dietary-insights

struct DietaryInsightsResponse: Codable {
    let foodsToEat: [String]
    let foodsToAvoid: [String]
    let usageStatus: UsageStatus?
    let lastUpdated: String?   // when these insights were generated → "Updated X ago" date
    let stale: Bool?           // health data changed after they were generated → attention chevron

    // Lenient: the backend occasionally returns 200 without the arrays (AI warming up / degraded).
    // Decode defensively so the card falls back to its empty state instead of throwing a decode error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodsToEat   = (try? c.decode([String].self, forKey: .foodsToEat)) ?? []
        foodsToAvoid = (try? c.decode([String].self, forKey: .foodsToAvoid)) ?? []
        usageStatus  = try? c.decode(UsageStatus.self, forKey: .usageStatus)
        lastUpdated  = try? c.decode(String.self, forKey: .lastUpdated)
        stale        = try? c.decode(Bool.self,   forKey: .stale)
    }
}

struct DietaryInsightsHistoryResponse: Decodable {
    let history: [DietaryInsightsEntry]
    let usageStatus: UsageStatus?
}

struct DietaryInsightsEntry: Decodable, Identifiable {
    var id: String { generatedAt }
    let generatedAt: String
    let foodsToEat: [String]
    let foodsToAvoid: [String]
    let trigger: String?
}

// MARK: - NutriCheck  /api/insights/nutri-check

struct NutriCheckRequest: Encodable {
    let foodItem: String
    let previousChecks: [PreviousCheck]

    struct PreviousCheck: Encodable {
        let foodItem: String
        let recommendation: String
        let reason: String
    }
}

struct NutriCheckResponse: Decodable {
    let recommendation: String  // "strong_yes" | "yes" | "moderate" | "no" | "strong_no"
    let reason: String
    let dataUsed: [String]
    let historyId: String
}

struct NutriCheckHistoryResponse: Decodable {
    let history: [NutriCheckEntry]
    let usageStatus: UsageStatus?
}

struct NutriCheckEntry: Decodable, Identifiable {
    let id: String
    let foodItem: String
    let recommendation: String
    let reason: String
    let checkedAt: String
    let userReaction: String?   // "up" | "down" | nil
    let dataChangesSince: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", foodItem, recommendation, reason
        case checkedAt, userReaction, dataChangesSince
    }

    var statusLevel: StatusLevel {
        switch recommendation {
        case "strong_yes", "yes": return .green
        case "moderate":          return .yellow
        case "no":                return .orange
        case "strong_no":         return .red
        default:                  return .yellow
        }
    }

    var recommendationLabel: String {
        switch recommendation {
        case "strong_yes": return "Highly Recommended"
        case "yes":        return "Good"
        case "moderate":   return "Moderate"
        case "no":         return "Avoid"
        case "strong_no":  return "Strongly Avoid"
        default:           return recommendation.capitalized
        }
    }
}

// MARK: - Feed  /api/feed

struct FeedResponse: Decodable {
    let items: [FeedItem]
    let page: Int
    let totalPages: Int
    let total: Int
}

struct FeedItem: Decodable, Identifiable {
    let id: String
    let type: String   // "podcast" | "article" | "news"
    let title: String
    let description: String
    let category: String
    let imageUrl: String
    let tags: [String]
    let isProOnly: Bool
    let publishedAt: String?
    let createdAt: String
    let reason: String?
    let aiReason: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", type, title, description, category, imageUrl
        case tags, isProOnly, publishedAt, createdAt, reason, aiReason
    }
}

// MARK: - AQI  /api/aqi

struct AQIData: Codable, Identifiable {
    let id: String
    let city: String
    let state: String
    let country: String
    let aqius: Int
    let aqicn: Int?
    let mainus: String?
    let temperature: Double?
    let humidity: Double?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case id = "_id", city, state, country
        case aqius, aqicn, mainus, temperature, humidity, timestamp
    }

    var statusLevel: StatusLevel {
        switch aqius {
        case ..<51:    return .green
        case 51..<101: return .yellow
        case 101..<201: return .orange
        default:       return .red
        }
    }

    var healthLabel: String {
        switch aqius {
        case ..<51:    return "Good"
        case 51..<101: return "Moderate"
        case 101..<151: return "Sensitive Groups"
        case 151..<201: return "Unhealthy"
        case 201..<301: return "Very Unhealthy"
        default:       return "Hazardous"
        }
    }
}

struct AQILatestResponse: Decodable { let aqi: AQIData }
struct AQIHistoryResponse: Decodable { let history: [AQIData]; let count: Int }

struct AQIStoreRequest: Encodable {
    let city: String
    let aqius: Int
    let latitude: Double
    let longitude: Double
    let state: String?
    let country: String?
}

// MARK: - Workout  /api/fitness/workouts

struct WorkoutRecord: Decodable, Identifiable {
    let id: String
    let name: String
    let date: String
    let exercises: [WorkoutExerciseRecord]

    enum CodingKeys: String, CodingKey {
        case id = "_id", name, date, exercises
    }
}

struct WorkoutExerciseRecord: Decodable, Identifiable {
    let id: String
    let exercise: ExerciseRecord
    let sets: Int
    let reps: Int
    let weight: Double

    enum CodingKeys: String, CodingKey {
        case id = "_id", exercise, sets, reps, weight
    }
}

struct ExerciseRecord: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let equipment: String?
    let difficulty: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", name, category, equipment, difficulty
    }
}

struct WorkoutCreateRequest: Encodable {
    let name: String
    let exercises: [WorkoutExerciseInput]
}

struct WorkoutExerciseInput: Encodable {
    let exercise: String  // Exercise catalogue ObjectId
    let sets: Int
    let reps: Int
    let weight: Double
}

// MARK: - Doctor  /api/users/doctor/doctor

struct DoctorSearchResult: Decodable, Identifiable {
    let id: String
    let name: String
    let email: String
    let specialty: String
    let specialization: String
    let licenseNumber: String
    let profilePicture: String
    let phoneNumber: String
    let hospitalAffiliation: String
    let experience: Int
    let doctorType: String
    let city: String
    let connectionStatus: String?  // "none" | "pending" | "accepted" | "rejected"

    enum CodingKeys: String, CodingKey {
        case id = "_id", name, email, specialty, specialization, licenseNumber
        case profilePicture, phoneNumber, hospitalAffiliation
        case experience, doctorType, city, connectionStatus
    }

    var connectionStatusLevel: StatusLevel? {
        switch connectionStatus {
        case "accepted": return .green
        case "pending":  return .yellow
        case "rejected": return .red
        default:         return nil
        }
    }
}

/// Returned by GET /api/users/doctor/doctor/pending — includes the connection record.
struct DoctorPendingRecord: Decodable, Identifiable {
    let id: String
    let doctor: DoctorSearchResult
    let status: String
    let message: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id = "_id", doctor, status, message, createdAt
    }
}

/// Lightweight entry returned by GET /api/users/doctor/doctor/requests (incoming).
struct IncomingDoctorRequest: Decodable, Identifiable {
    let email: String
    let name: String
    let status: String
    var id: String { email }
}

struct IncomingDoctorRequestsResponse: Decodable {
    let incomingDoctorRequests: [IncomingDoctorRequest]
}

// MARK: - Health Analysis  /api/health/analysis

struct HealthAnalysisResponse: Decodable {
    let analysis: HealthAnalysis?
}

struct HealthAnalysis: Decodable {
    let headline: String?
    let healthAnalysisStatus: HAStatus?
    let metrics: HAMetrics?
    let profileCompletion: HAProfileCompletion?
    let healthAnalysisCache: HACache?
    let lastUpdated: String?
    let dataChangesSinceAnalysis: HADataChanges?
    // Cross-feature staleness helpers (exposed by the analysis endpoint) used to drive the
    // NutriCheck launcher card's "Last checked" date + attention chevron.
    let lastNutriCheckAt: String?
    let lastHealthDataChange: String?

    struct HAStatus: Decodable {
        let level: String?   // "excellent"|"stable"|"attention"|"critical"
        let reason: String?

        var statusLevel: StatusLevel {
            switch level?.lowercased() {
            case "excellent", "stable": return .green
            case "attention":           return .orange
            case "critical":            return .red
            default:                    return .yellow
            }
        }
        var displayLabel: String { (level ?? "unknown").capitalized }
    }

    struct HAMetrics: Decodable {
        let location: String?
        let aqi: Int?
        let age: Int?
        let bmi: Double?
    }

    struct HAProfileCompletion: Decodable {
        let percent: Int?
        let missing: [String]?
    }

    struct HACache: Decodable {
        let overall: HACacheItem?
        let reports: HACacheItem?
        let symptoms: HACacheItem?
        let medications: HACacheItem?
        let measurements: HACacheItem?
        let genetics: HACacheItem?
    }

    struct HACacheItem: Decodable {
        let text: String?
        let generatedAt: String?

        // text is a JSON string; parse summary field from it.
        var summary: String? {
            guard let t = text, let data = t.data(using: .utf8) else { return text }
            struct S: Decodable { let summary: String? }
            return (try? JSONDecoder().decode(S.self, from: data))?.summary ?? t
        }
    }

    struct HADataChanges: Decodable {
        let symptoms: Int?
        let measurements: Int?
        let medications: Int?
        let reports: Int?

        var hasChanges: Bool {
            (symptoms ?? 0) + (measurements ?? 0) + (medications ?? 0) + (reports ?? 0) > 0
        }
        var changeSummary: String {
            var parts: [String] = []
            if let s = symptoms,   s > 0 { parts.append("\(s) symptom\(s > 1 ? "s" : "")") }
            if let m = measurements, m > 0 { parts.append("\(m) vital\(m > 1 ? "s" : "")") }
            if let med = medications, med > 0 { parts.append("\(med) medication\(med > 1 ? "s" : "")") }
            if let r = reports,    r > 0 { parts.append("\(r) report\(r > 1 ? "s" : "")") }
            return parts.joined(separator: ", ")
        }
    }
}

// MARK: - Check-In  /api/checkin/home-card

struct CheckInHomeCardResponse: Decodable {
    let canAccess: Bool?
    let tier: String?
    let pendingCount: Int?
    let inProgressCount: Int?
    let isDue: Bool?
    let lastCompletedAt: String?

    enum CheckInState { case inProgress, due, pending, allCaughtUp }

    var state: CheckInState {
        if (inProgressCount ?? 0) > 0 { return .inProgress }
        if isDue == true               { return .due }
        if (pendingCount ?? 0) > 0     { return .pending }
        return .allCaughtUp
    }
    var stateLabel: String {
        switch state {
        case .inProgress: return "In Progress"
        case .due:        return "Due Now"
        case .pending:    return "Pending"
        case .allCaughtUp: return "All Caught Up"
        }
    }
    var stateLevel: StatusLevel {
        switch state {
        case .inProgress: return .yellow
        case .due:        return .orange
        case .pending:    return .yellow
        case .allCaughtUp: return .green
        }
    }
    var actionLabel: String {
        switch state {
        case .inProgress: return "Continue"
        case .due, .pending: return "Start"
        case .allCaughtUp: return "View History"
        }
    }
    var subtitleText: String {
        switch state {
        case .inProgress:
            let n = inProgressCount ?? 1
            return "\(n) check-in\(n == 1 ? "" : "s") in progress"
        case .due:
            return "Today's check-in is ready"
        case .pending:
            let n = pendingCount ?? 1
            return "\(n) check-in\(n == 1 ? "" : "s") waiting"
        case .allCaughtUp:
            return "Nothing due right now"
        }
    }
}

// MARK: - Skeleton placeholders

extension FeedItem {
    static let placeholder = FeedItem(
        id: "placeholder",
        type: "article",
        title: "Loading article title here for skeleton",
        description: "",
        category: "Health",
        imageUrl: "",
        tags: [],
        isProOnly: false,
        publishedAt: nil,
        createdAt: "",
        reason: "Loading reason text",
        aiReason: nil
    )
}

// MARK: - Check-In List  /api/checkin/list

struct CheckInListResponse: Decodable {
    let canAccess: Bool
    let tier: String?
    let isDue: Bool?
    let nextDueDate: String?
    let sessions: [CheckInSessionRecord]
}

struct CheckInSessionRecord: Identifiable, Decodable {
    let id: String
    let period: String
    let status: String
    let scheduledFor: String?
    let periodDate: String?
    let totalQuestions: Int
    let answeredCount: Int
    let completedAt: String?
    let responses: [CheckInResponseRecord]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case period, status, scheduledFor, periodDate, totalQuestions, answeredCount, completedAt, responses
    }
}

struct CheckInResponseRecord: Decodable {
    let questionText: String?
    let selectedLabel: String?
    let selectedEmoji: String?
    let selectedValue: String?
    let category: String?
}

// MARK: - Check-In Start  /api/checkin/start

struct CheckInStartResponse: Decodable {
    let sessionId: String
    let questions: [CheckInQuestion]
    let resumed: Bool?
}

struct CheckInQuestion: Identifiable, Decodable {
    let id: String
    let text: String
    let options: [CheckInOption]

    enum CodingKeys: String, CodingKey {
        case id = "_id"; case text, options
    }
}

struct CheckInOption: Decodable {
    let emoji: String
    let label: String
    let value: String
}

// MARK: - Check-In Respond  /api/checkin/sessions/:id/respond

struct CheckInRespondRequest: Encodable {
    let questionId: String
    let selectedLabel: String
    let selectedEmoji: String
    let selectedValue: String
}

struct CheckInRespondSessionInfo: Decodable {
    let answeredCount: Int
    let totalQuestions: Int
    let status: String
}

struct CheckInRespondResponse: Decodable {
    let success: Bool?
    let session: CheckInRespondSessionInfo?
}
