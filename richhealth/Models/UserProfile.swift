import Foundation

/// Subset of the backend User model (all fields minus password).
/// Confirmed against User.js mongoose schema in ../richhealthbackend/models/User.js.
struct UserProfile: Codable, Identifiable {
    let id: String
    let name: String?
    let email: String?
    let phoneNumber: String?
    let dateOfBirth: String?            // ISO 8601 from backend
    let gender: String?                 // "Male" | "Female" | "Other"
    let location: String?
    let height: Double?                 // cm
    let weight: Double?                 // kg
    let waistCircumference: Double?     // cm
    let activityLevel: Int?             // 1–5
    let primaryGoal: String?
    let dietType: String?
    let bloodType: String?
    let medicalConditions: [String]?
    let allergies: [String]?
    let familyHistory: [String]?

    // Lifestyle / daily habits
    let sleepHours: Double?
    let waterIntake: Int?               // glasses per day
    let mealsPerDay: Int?
    let stressLevel: Int?               // 1–4: Rarely → Almost Always
    let screenTimeBeforeBed: String?    // "low"|"moderate"|"high"|"very_high"
    let sunExposure: String?            // "low"|"moderate"|"high"
    let occupationType: String?

    // Habits
    let smokingStatus: String?          // "never"|"ex"|"social"|"occasional"|"regular"
    let smoker: Bool?
    let smokingLevel: Int?              // 0–4
    let smokingFrequency: String?       // "Non-smoker"|"Social"|"Occasional"|"Regular"|...
    let alcoholConsumption: String?     // "None"|"Special Occasions"|"Socially"|"Regularly"|"Frequently"
    let alcoholLevel: Int?              // 0–4
    let caffeineHabit: String?          // "none"|"tea"|"coffee"|"both"|"energy_drinks"

    // Habit / condition follow-ups (conditional at signup)
    let smokingDuration: String?
    let cigarettesPerDay: String?
    let lastSmoked: String?
    let drinksPerWeek: String?
    let conditionsDiagnosed: String?
    let conditionsMedicated: String?

    // Reproductive health (conditional for female users)
    let menstrualStatus: String?        // "regular"|"irregular"|"perimenopause"|"menopause"|"not_applicable"|"prefer_not_to_say"
    let pregnancyStatus: String?        // "not_pregnant"|"pregnant"|"postpartum"|"trying_to_conceive"|"not_applicable"
    let averageCycleLength: Int?
    let averagePeriodLength: Int?
    let contraceptionMethod: String?
    let menstrualSymptoms: [String]?
    let ethnicity: String?
    let familyHistoryRelatives: [String]?   // affected relatives for family conditions
    let medicationCategories: [String]?     // medication type categories (e.g. "Antibiotic", "Antihypertensive")
    let weeklyGoal: Int?                    // weekly workout goal count — Number in backend schema
    let recentWeightChange: String?         // narrative weight change (e.g. "Lost 2 kg this month")

    // Auth / plan
    let isPro: Bool?
    let emailVerified: Bool?
    let proSubscriptionPlan: String?    // "pro"|"plus"|"ultra"|"family"
    let proGrantedBy: String?
    let aiPreferences: AIPreferences?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, email, phoneNumber, dateOfBirth, gender, location
        case height, weight, waistCircumference, activityLevel, primaryGoal, dietType, bloodType
        case medicalConditions, allergies, familyHistory
        case sleepHours, waterIntake, mealsPerDay, stressLevel
        case screenTimeBeforeBed, sunExposure, occupationType
        case smokingStatus, smoker, smokingLevel, smokingFrequency
        case alcoholConsumption, alcoholLevel, caffeineHabit
        case smokingDuration, cigarettesPerDay, lastSmoked, drinksPerWeek
        case conditionsDiagnosed, conditionsMedicated
        case menstrualStatus, pregnancyStatus, averageCycleLength, averagePeriodLength
        case contraceptionMethod, menstrualSymptoms, ethnicity
        case familyHistoryRelatives, medicationCategories, weeklyGoal, recentWeightChange
        case isPro, emailVerified, proSubscriptionPlan, proGrantedBy
        case aiPreferences
    }

    // Custom decoder: one field type mismatch must never kill the whole decode.
    // Uses try? c.decode so missing keys AND type mismatches both produce nil.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(String.self,         forKey: .id)          // required
        name                 = try? c.decode(String.self,         forKey: .name)
        email                = try? c.decode(String.self,         forKey: .email)
        phoneNumber          = try? c.decode(String.self,         forKey: .phoneNumber)
        dateOfBirth          = try? c.decode(String.self,         forKey: .dateOfBirth)
        gender               = try? c.decode(String.self,         forKey: .gender)
        location             = try? c.decode(String.self,         forKey: .location)
        height               = try? c.decode(Double.self,         forKey: .height)
        weight               = try? c.decode(Double.self,         forKey: .weight)
        waistCircumference   = try? c.decode(Double.self,         forKey: .waistCircumference)
        // activityLevel stored as Number — try Int first, fall back via Double
        if let i = try? c.decode(Int.self,    forKey: .activityLevel) { activityLevel = i }
        else if let d = try? c.decode(Double.self, forKey: .activityLevel) { activityLevel = Int(d) }
        else { activityLevel = nil }
        primaryGoal          = try? c.decode(String.self,         forKey: .primaryGoal)
        dietType             = try? c.decode(String.self,         forKey: .dietType)
        bloodType            = try? c.decode(String.self,         forKey: .bloodType)
        medicalConditions    = try? c.decode([String].self,       forKey: .medicalConditions)
        allergies            = try? c.decode([String].self,       forKey: .allergies)
        familyHistory        = try? c.decode([String].self,       forKey: .familyHistory)
        sleepHours           = try? c.decode(Double.self,         forKey: .sleepHours)
        if let i = try? c.decode(Int.self,    forKey: .waterIntake)  { waterIntake  = i }
        else if let d = try? c.decode(Double.self, forKey: .waterIntake)  { waterIntake  = Int(d) }
        else { waterIntake = nil }
        if let i = try? c.decode(Int.self,    forKey: .mealsPerDay)  { mealsPerDay  = i }
        else if let d = try? c.decode(Double.self, forKey: .mealsPerDay)  { mealsPerDay  = Int(d) }
        else { mealsPerDay = nil }
        if let i = try? c.decode(Int.self,    forKey: .stressLevel)  { stressLevel  = i }
        else if let d = try? c.decode(Double.self, forKey: .stressLevel)  { stressLevel  = Int(d) }
        else { stressLevel = nil }
        screenTimeBeforeBed  = try? c.decode(String.self,         forKey: .screenTimeBeforeBed)
        sunExposure          = try? c.decode(String.self,         forKey: .sunExposure)
        occupationType       = try? c.decode(String.self,         forKey: .occupationType)
        smokingStatus        = try? c.decode(String.self,         forKey: .smokingStatus)
        smoker               = try? c.decode(Bool.self,           forKey: .smoker)
        if let i = try? c.decode(Int.self,    forKey: .smokingLevel) { smokingLevel = i }
        else if let d = try? c.decode(Double.self, forKey: .smokingLevel) { smokingLevel = Int(d) }
        else { smokingLevel = nil }
        smokingFrequency     = try? c.decode(String.self,         forKey: .smokingFrequency)
        alcoholConsumption   = try? c.decode(String.self,         forKey: .alcoholConsumption)
        if let i = try? c.decode(Int.self,    forKey: .alcoholLevel) { alcoholLevel = i }
        else if let d = try? c.decode(Double.self, forKey: .alcoholLevel) { alcoholLevel = Int(d) }
        else { alcoholLevel = nil }
        caffeineHabit        = try? c.decode(String.self,         forKey: .caffeineHabit)
        smokingDuration      = try? c.decode(String.self,         forKey: .smokingDuration)
        cigarettesPerDay     = try? c.decode(String.self,         forKey: .cigarettesPerDay)
        lastSmoked           = try? c.decode(String.self,         forKey: .lastSmoked)
        drinksPerWeek        = try? c.decode(String.self,         forKey: .drinksPerWeek)
        conditionsDiagnosed  = try? c.decode(String.self,         forKey: .conditionsDiagnosed)
        conditionsMedicated  = try? c.decode(String.self,         forKey: .conditionsMedicated)
        menstrualStatus      = try? c.decode(String.self,         forKey: .menstrualStatus)
        pregnancyStatus      = try? c.decode(String.self,         forKey: .pregnancyStatus)
        if let i = try? c.decode(Int.self,    forKey: .averageCycleLength)  { averageCycleLength  = i }
        else if let d = try? c.decode(Double.self, forKey: .averageCycleLength)  { averageCycleLength  = Int(d) }
        else { averageCycleLength = nil }
        if let i = try? c.decode(Int.self,    forKey: .averagePeriodLength) { averagePeriodLength = i }
        else if let d = try? c.decode(Double.self, forKey: .averagePeriodLength) { averagePeriodLength = Int(d) }
        else { averagePeriodLength = nil }
        contraceptionMethod  = try? c.decode(String.self,         forKey: .contraceptionMethod)
        menstrualSymptoms    = try? c.decode([String].self,       forKey: .menstrualSymptoms)
        ethnicity            = try? c.decode(String.self,         forKey: .ethnicity)
        familyHistoryRelatives = try? c.decode([String].self,     forKey: .familyHistoryRelatives)
        medicationCategories = try? c.decode([String].self,       forKey: .medicationCategories)
        if let i = try? c.decode(Int.self,    forKey: .weeklyGoal) { weeklyGoal = i }
        else if let d = try? c.decode(Double.self, forKey: .weeklyGoal) { weeklyGoal = Int(d) }
        else { weeklyGoal = nil }
        recentWeightChange   = try? c.decode(String.self,         forKey: .recentWeightChange)
        isPro                = try? c.decode(Bool.self,           forKey: .isPro)
        emailVerified        = try? c.decode(Bool.self,           forKey: .emailVerified)
        proSubscriptionPlan  = try? c.decode(String.self,         forKey: .proSubscriptionPlan)
        // proGrantedBy is an ObjectId ref in the backend — decode as String (unpopulated ObjectId)
        proGrantedBy         = try? c.decode(String.self,         forKey: .proGrantedBy)
        aiPreferences        = try? c.decode(AIPreferences.self,  forKey: .aiPreferences)
    }

    // MARK: - Computed helpers

    var completionPercent: Double {
        let checks: [Bool] = [
            name?.isEmpty == false,
            phoneNumber?.isEmpty == false,
            dateOfBirth != nil,
            gender?.isEmpty == false,
            location?.isEmpty == false,
            (height ?? 0) > 0,
            (weight ?? 0) > 0,
            activityLevel != nil,
            primaryGoal?.isEmpty == false,
            dietType?.isEmpty == false,
            bloodType?.isEmpty == false,
            medicalConditions?.isEmpty == false,
            sleepHours != nil,
            smokingStatus?.isEmpty == false
        ]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }

    var activityLevelLabel: String? {
        switch activityLevel {
        case 1: return "Mostly Sitting"
        case 2: return "Lightly Active"
        case 3: return "Moderately Active"
        case 4: return "Very Active"
        case 5: return "Athlete"
        default: return nil
        }
    }

    var age: Int? {
        guard let str = dateOfBirth, let dob = Self.parseDOB(str) else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: .now).year
    }

    var smokingLabel: String? {
        switch smokingStatus {
        case "never":      return "Non-smoker"
        case "ex":         return "Ex-smoker"
        case "social":     return "Social smoker"
        case "occasional": return "Occasional smoker"
        case "regular":    return "Daily smoker"
        default:           return nil
        }
    }

    var stressLabel: String? {
        switch stressLevel {
        case 1: return "Rarely stressed"
        case 2: return "Sometimes"
        case 3: return "Often stressed"
        case 4: return "Almost always"
        default: return nil
        }
    }

    var screenTimeLabel: String? {
        switch screenTimeBeforeBed {
        case "low":       return "Stops 1hr+ before bed"
        case "moderate":  return "~30 min before bed"
        case "high":      return "Right until sleep"
        case "very_high": return "Falls asleep with screen"
        default:          return nil
        }
    }

    var caffeineLabel: String? {
        switch caffeineHabit {
        case "none":          return "No caffeine"
        case "tea":           return "Tea"
        case "coffee":        return "Coffee"
        case "both":          return "Tea & coffee"
        case "energy_drinks": return "Energy drinks"
        default:              return nil
        }
    }

    var menstrualStatusLabel: String? {
        switch menstrualStatus {
        case "regular":          return "Regular"
        case "irregular":        return "Irregular"
        case "perimenopause":    return "Perimenopause"
        case "menopause":        return "Menopause"
        case "prefer_not_to_say": return "Prefer not to say"
        case "not_applicable":   return nil
        default:                 return nil
        }
    }

    var showReproductiveHealth: Bool {
        guard let g = gender else { return false }
        if g == "Female" || g == "Other" { return true }
        if let status = menstrualStatus, status != "not_applicable" { return true }
        return false
    }

    static func parseDOB(_ str: String) -> Date? {
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let d = df.date(from: str) { return d }
        }
        return nil
    }
}

// MARK: - AI Memory

/// A fact Richie has remembered about the user. Confirmed against GET /api/user/memories.
struct AIMemory: Codable, Identifiable {
    let id: String
    let fact: String
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case fact, category
    }
}

struct AIMemoriesResponse: Decodable {
    let memories: [AIMemory]
}

// MARK: - AI Preferences

/// Nested AI chat settings on the user profile.
/// Custom encode uses encodeIfPresent so nil fields are omitted from PUT /api/user/profile body.
struct AIPreferences: Codable {
    let tone: String?           // "balanced" | "warm" | "direct"
    let replyLength: String?    // "concise" | "balanced" | "detailed"
    let customInstructions: String?
    let saveMemories: Bool?
    let showThinking: Bool?
    let improveModel: Bool?
    let autofillCards: Bool?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(tone, forKey: .tone)
        try c.encodeIfPresent(replyLength, forKey: .replyLength)
        try c.encodeIfPresent(customInstructions, forKey: .customInstructions)
        try c.encodeIfPresent(saveMemories, forKey: .saveMemories)
        try c.encodeIfPresent(showThinking, forKey: .showThinking)
        try c.encodeIfPresent(improveModel, forKey: .improveModel)
        try c.encodeIfPresent(autofillCards, forKey: .autofillCards)
    }

    enum CodingKeys: String, CodingKey {
        case tone, replyLength, customInstructions
        case saveMemories, showThinking, improveModel, autofillCards
    }
}
