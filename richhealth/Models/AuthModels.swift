import Foundation

// ── Login ─────────────────────────────────────────────────────────────────────

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// POST /api/auth/login and POST /api/auth/signup both return this shape.
/// Confirmed in authController.js: { token, userId }.
struct AuthResponse: Decodable {
    let token: String
    let userId: String?
}

// ── Signup ────────────────────────────────────────────────────────────────────

/// Body for POST /api/auth/signup.
/// Required fields confirmed in authController.js signup().
/// Optional fields from OnboardingActivity.java 21-step onboarding flow.
struct SignupRequest: Encodable {
    // Required
    let email: String
    let password: String
    let confirmPassword: String
    let name: String
    let gender: String              // "Male" | "Female" | "Other"
    let dateOfBirth: String         // "yyyy-MM-dd"
    let height: Double              // cm
    let weight: Double              // kg
    let activityLevel: Int          // 1–5
    let dietType: String
    // Optional — from extended onboarding
    let phoneNumber: String?
    let location: String?
    let primaryGoal: String?
    let bloodType: String?
    let sleepHours: Double?
    let smokingStatus: String?      // "never"|"ex"|"social"|"occasional"|"regular"
    let alcoholConsumption: String? // "None"|"Rarely"|"Special Occasions"|"Socially"|"Regularly"|"Frequently"
    let caffeineHabit: String?      // "none"|"tea"|"coffee"|"both"|"energy_drinks"
    let medicalConditions: [String]?
    let allergies: [String]?
}

// ── Profile wrapper ───────────────────────────────────────────────────────────

/// GET /api/user/profile returns `{ user: {...} }`. Confirmed in userController.getUserProfile.
struct ProfileResponse: Decodable {
    let user: UserProfile
}

// ── Email OTP ─────────────────────────────────────────────────────────────────

struct SendOTPRequest: Encodable { let email: String }
struct VerifyOTPRequest: Encodable { let email: String; let otp: String }

/// POST /api/auth/send-otp response.
struct OTPSentResponse: Decodable {
    let message: String?
    let emailSent: Bool?
    let expiresInSeconds: Int?
    let alreadyVerified: Bool?
}

/// POST /api/auth/verify-otp response.
struct OTPVerifyResponse: Decodable {
    let verified: Bool?
    let message: String?
}

// ── Pro access ────────────────────────────────────────────────────────────────

/// GET /api/user/pro-access — confirmed against userController.js.
/// Always fetched from server; never derived locally (CLAUDE.md §7).
struct ProAccess: Decodable {
    let isPro: Bool
    let tier: String            // "free"|"pro"|"plus"|"ultra"|"family"|"family_member"
    let expiresAt: Double?      // ms UTC

    var expiryDate: Date? {
        guard let ms = expiresAt, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    var displayName: String {
        switch tier {
        case "ultra":         return "RichHealth Ultra"
        case "family":        return "RichHealth Family"
        case "family_member": return "Family Member"
        case "plus":          return "RichHealth Plus"
        case "pro":           return "RichHealth Pro"
        default:              return "Free Plan"
        }
    }
}

// ── Usage summary ─────────────────────────────────────────────────────────────

/// GET /api/user/usage — confirmed against userController.js.
struct UserUsageResponse: Decodable {
    let tier: String
    let isPro: Bool
    let usage: UsageEntries

    struct UsageEntries: Decodable {
        let chatSessions: Entry?
        let medicalReports: Entry?
        let reportAnalysis: Entry?
        let nutricheck: Entry?
        let healthAnalysis: Entry?
        let dietaryInsights: Entry?
    }

    struct Entry: Decodable {
        let count: Int
        let limit: Int?
        let remaining: Int?
        let limitReached: Bool

        var fraction: Double {
            guard let lim = limit, lim > 0 else { return 0 }
            return min(Double(count) / Double(lim), 1.0)
        }

        var displayText: String {
            guard let lim = limit else { return "\(count) used" }
            return "\(count) / \(lim)"
        }
    }
}

// ── Profile update ────────────────────────────────────────────────────────────

/// PUT /api/user/profile — all fields optional; only non-nil fields are sent.
/// Confirmed against userController.js updateUserProfile(). encodeIfPresent skips nil.
struct UpdateProfileRequest: Encodable {
    // Account
    var name: String? = nil
    var email: String? = nil
    var phoneNumber: String? = nil
    var dateOfBirth: String? = nil      // "yyyy-MM-dd"
    var gender: String? = nil
    var location: String? = nil

    // Physical
    var height: Double? = nil           // cm
    var weight: Double? = nil           // kg
    var waistCircumference: Double? = nil // cm
    var bloodType: String? = nil

    // Fitness
    var activityLevel: Int? = nil
    var primaryGoal: String? = nil
    var dietType: String? = nil

    // Medical
    var medicalConditions: [String]? = nil
    var allergies: [String]? = nil
    var familyHistory: [String]? = nil

    // Lifestyle
    var sleepHours: Double? = nil
    var waterIntake: Int? = nil         // glasses
    var mealsPerDay: Int? = nil
    var stressLevel: Int? = nil         // 1–4
    var screenTimeBeforeBed: String? = nil  // "low"|"moderate"|"high"|"very_high"
    var sunExposure: String? = nil          // "low"|"moderate"|"high"
    var occupationType: String? = nil

    // Habits
    var smokingStatus: String? = nil    // "never"|"ex"|"social"|"occasional"|"regular"
    var alcoholConsumption: String? = nil
    var caffeineHabit: String? = nil    // "none"|"tea"|"coffee"|"both"|"energy_drinks"

    // Reproductive health
    var menstrualStatus: String? = nil
    var pregnancyStatus: String? = nil
    var averageCycleLength: Int? = nil
    var averagePeriodLength: Int? = nil
    var contraceptionMethod: String? = nil
    var menstrualSymptoms: [String]? = nil
    var ethnicity: String? = nil

    // AI / app
    var aiPreferences: AIPreferences? = nil
    var biometricEnabled: Bool? = nil

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try c.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(waistCircumference, forKey: .waistCircumference)
        try c.encodeIfPresent(bloodType, forKey: .bloodType)
        try c.encodeIfPresent(activityLevel, forKey: .activityLevel)
        try c.encodeIfPresent(primaryGoal, forKey: .primaryGoal)
        try c.encodeIfPresent(dietType, forKey: .dietType)
        try c.encodeIfPresent(medicalConditions, forKey: .medicalConditions)
        try c.encodeIfPresent(allergies, forKey: .allergies)
        try c.encodeIfPresent(familyHistory, forKey: .familyHistory)
        try c.encodeIfPresent(sleepHours, forKey: .sleepHours)
        try c.encodeIfPresent(waterIntake, forKey: .waterIntake)
        try c.encodeIfPresent(mealsPerDay, forKey: .mealsPerDay)
        try c.encodeIfPresent(stressLevel, forKey: .stressLevel)
        try c.encodeIfPresent(screenTimeBeforeBed, forKey: .screenTimeBeforeBed)
        try c.encodeIfPresent(sunExposure, forKey: .sunExposure)
        try c.encodeIfPresent(occupationType, forKey: .occupationType)
        try c.encodeIfPresent(smokingStatus, forKey: .smokingStatus)
        try c.encodeIfPresent(alcoholConsumption, forKey: .alcoholConsumption)
        try c.encodeIfPresent(caffeineHabit, forKey: .caffeineHabit)
        try c.encodeIfPresent(menstrualStatus, forKey: .menstrualStatus)
        try c.encodeIfPresent(pregnancyStatus, forKey: .pregnancyStatus)
        try c.encodeIfPresent(averageCycleLength, forKey: .averageCycleLength)
        try c.encodeIfPresent(averagePeriodLength, forKey: .averagePeriodLength)
        try c.encodeIfPresent(contraceptionMethod, forKey: .contraceptionMethod)
        try c.encodeIfPresent(menstrualSymptoms, forKey: .menstrualSymptoms)
        try c.encodeIfPresent(ethnicity, forKey: .ethnicity)
        try c.encodeIfPresent(aiPreferences, forKey: .aiPreferences)
        try c.encodeIfPresent(biometricEnabled, forKey: .biometricEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case name, email, phoneNumber, dateOfBirth, gender, location
        case height, weight, waistCircumference, bloodType
        case activityLevel, primaryGoal, dietType
        case medicalConditions, allergies, familyHistory
        case sleepHours, waterIntake, mealsPerDay, stressLevel
        case screenTimeBeforeBed, sunExposure, occupationType
        case smokingStatus, alcoholConsumption, caffeineHabit
        case menstrualStatus, pregnancyStatus, averageCycleLength, averagePeriodLength
        case contraceptionMethod, menstrualSymptoms, ethnicity
        case aiPreferences, biometricEnabled
    }
}
