import Foundation
import Observation

// ─── Step model ─────────────────────────────────────────────────────────────
// Mirrors Android OnboardingActivity's fragment list (allFragments) + isStepActive().
// Declaration order == on-screen order. Conditional cases are filtered out of
// `activeSteps` when their gating answer doesn't apply.

enum SignupStep: CaseIterable {
    case account          // 0  account + phone
    case personal         // 1  DOB + gender + location
    case menstrual        // 2  menstrual health          (conditional: Female/Other)
    case body             // 3  height, weight, waist
    case goal             // 4  primary goal + recent weight change
    case activity         // 5  activity level
    case occupation       // 6  occupation
    case diet             // 7  diet type
    case mealsWater       // 8  meals per day + water
    case sleep            // 9  sleep
    case stress           // 10 stress
    case screenTime       // 11 screen time before bed
    case habits           // 12 smoking + alcohol + caffeine
    case smokingDetail    // 13 smoking detail            (conditional: smoker/ex)
    case alcoholDetail    // 14 alcohol detail            (conditional: drinks)
    case familyHistory    // 15 family history + relatives
    case allergies        // 16 allergies
    case sunExposure      // 17 sun exposure
    case medical          // 18 blood type + conditions + medications
    case conditionDetail  // 19 condition detail          (conditional: conditions picked)
    case ancestry         // 20 ethnicity

    var title: String {
        switch self {
        case .account:         return "Your account"
        case .personal:        return "Personal info"
        case .menstrual:       return "Menstrual health"
        case .body:            return "Your body"
        case .goal:            return "Your goal"
        case .activity:        return "Activity level"
        case .occupation:      return "Occupation"
        case .diet:            return "Your diet"
        case .mealsWater:      return "Meals & water"
        case .sleep:           return "Sleep"
        case .stress:          return "Stress"
        case .screenTime:      return "Screens before bed"
        case .habits:          return "Lifestyle habits"
        case .smokingDetail:   return "About your smoking"
        case .alcoholDetail:   return "About your drinking"
        case .familyHistory:   return "Family history"
        case .allergies:       return "Allergies"
        case .sunExposure:     return "Sun exposure"
        case .medical:         return "Medical info"
        case .conditionDetail: return "Your condition(s)"
        case .ancestry:        return "Your ancestry"
        }
    }

    var caption: String {
        switch self {
        case .account:         return "Secure your account"
        case .personal:        return "Tell us about yourself"
        case .menstrual:       return "Personalised around your cycle"
        case .body:            return "Your body metrics"
        case .goal:            return "What you want to focus on"
        case .activity:        return "How active are you?"
        case .occupation:      return "What do you do?"
        case .diet:            return "How you eat"
        case .mealsWater:      return "Two quick ones"
        case .sleep:           return "How much you sleep"
        case .stress:          return "How often you feel stressed"
        case .screenTime:      return "Screens & sleep"
        case .habits:          return "Honest answers help us"
        case .smokingDetail:   return "A few smoking details"
        case .alcoholDetail:   return "One quick detail"
        case .familyHistory:   return "Your family's health story"
        case .allergies:       return "Safety-critical"
        case .sunExposure:     return "Sun drives vitamin D & mood"
        case .medical:         return "Optional — skip anything"
        case .conditionDetail: return "About what you're managing"
        case .ancestry:        return "Sharpens our predictions"
        }
    }

    var systemImage: String {
        switch self {
        case .account:         return "person.badge.key.fill"
        case .personal:        return "person.fill"
        case .menstrual:       return "drop.fill"
        case .body:            return "figure.stand"
        case .goal:            return "target"
        case .activity:        return "figure.walk"
        case .occupation:      return "briefcase.fill"
        case .diet:            return "fork.knife"
        case .mealsWater:      return "cup.and.saucer.fill"
        case .sleep:           return "bed.double.fill"
        case .stress:          return "brain.head.profile"
        case .screenTime:      return "iphone"
        case .habits:          return "wineglass.fill"
        case .smokingDetail:   return "smoke.fill"
        case .alcoholDetail:   return "wineglass"
        case .familyHistory:   return "figure.2.and.child.holdinghands"
        case .allergies:       return "allergens"
        case .sunExposure:     return "sun.max.fill"
        case .medical:         return "cross.case.fill"
        case .conditionDetail: return "stethoscope"
        case .ancestry:        return "globe"
        }
    }
}

@Observable @MainActor final class SignupViewModel {

    // ─── Step 0: Account ─────────────────────────────────────────────────────
    var name = ""
    var email = ""
    var phoneNumber = ""
    var password = ""
    var confirmPassword = ""

    // ─── Step 1: Personal ────────────────────────────────────────────────────
    var gender = ""
    var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var location = ""

    // ─── Step 2: Menstrual (conditional — Female/Other) ──────────────────────
    var menstrualStatus = "not_applicable"   // regular|irregular|perimenopause|menopause|prefer_not_to_say
    var menstrualSymptoms: Set<String> = []
    var pregnancyStatus = "not_applicable"   // not_pregnant|pregnant|postpartum|trying_to_conceive
    var cycleLengthSel = ""                   // maps to Int (empty until picked; falls back at submit)
    var periodLengthSel = ""                  // maps to Int (empty until picked; falls back at submit)
    var contraceptionMethod = ""             // none|pill|iud|condom|implant|<other>
    var contraceptionOther = ""

    // ─── Step 3: Body ────────────────────────────────────────────────────────
    var heightCm: Double = 170
    var weightKg: Double = 70
    var waistCircumferenceCm: Double = 80
    var waistUnknown = true                  // true → not provided (Android's cb_waist_unknown)

    // ─── Step 4: Goal ────────────────────────────────────────────────────────
    var primaryGoal = ""                      // empty until picked (progressive reveal)
    var primaryGoalOther = ""
    var recentWeightChange = ""              // Gained|Lost|Stable|Not sure

    // ─── Step 5: Activity ────────────────────────────────────────────────────
    var activityLevel = 3                    // 1–5

    // ─── Step 6: Occupation ──────────────────────────────────────────────────
    var occupationType = ""                  // desk|physical|healthcare|student|remote|retired|<other>
    var occupationOther = ""

    // ─── Step 7: Diet ────────────────────────────────────────────────────────
    var dietType = "Regular"
    var dietTypeOther = ""

    // ─── Step 8: Meals + Water ───────────────────────────────────────────────
    var mealsPerDaySel = ""                   // maps to Int (2|3|4|6); empty until picked
    var waterIntakeSel = ""                   // maps to Int glasses (2|5|8|10); empty until picked

    // ─── Step 9: Sleep ───────────────────────────────────────────────────────
    var sleepHours: Double = 7

    // ─── Step 10: Stress ─────────────────────────────────────────────────────
    var stressSel = "2"                      // maps to Int 1–4

    // ─── Step 11: Screen time ────────────────────────────────────────────────
    var screenTimeBeforeBed = "moderate"     // low|moderate|high|very_high

    // ─── Step 12: Habits ─────────────────────────────────────────────────────
    var smokingStatus = ""                    // never|ex|social|occasional|regular (empty until picked)
    var alcoholConsumption = ""               // None|Special Occasions|Socially|Regularly|Frequently (empty until picked)
    var caffeineHabit = ""                    // none|tea|coffee|energy_drinks|<other> (empty until picked)
    var caffeineOther = ""

    // ─── Step 13: Smoking detail (conditional) ───────────────────────────────
    var smokingDuration = ""                 // <1 year|1-5 years|5-10 years|10+ years
    var cigarettesPerDay = ""                // <5|5-10|10-20|20+
    var lastSmoked = ""                      // This week|This month|This year|Over a year ago

    // ─── Step 14: Alcohol detail (conditional) ───────────────────────────────
    var drinksPerWeek = ""                   // 1-2|3-5|6-10|10+

    // ─── Step 15: Family history ─────────────────────────────────────────────
    var familyHistory: Set<String> = []
    var familyHistoryOther = ""
    var familyHistoryRelatives: Set<String> = []

    // ─── Step 16: Allergies ──────────────────────────────────────────────────
    var allergies: Set<String> = []
    var allergiesOther = ""

    // ─── Step 17: Sun exposure ───────────────────────────────────────────────
    var sunExposure = "moderate"             // low|moderate|high

    // ─── Step 18: Medical ────────────────────────────────────────────────────
    var bloodType = ""                       // "" = don't know
    var medicalConditions: Set<String> = []
    var medicalConditionsOther = ""
    var medicationCategories: Set<String> = []
    var medicationOther = ""

    // ─── Step 19: Condition detail (conditional) ─────────────────────────────
    var conditionsDiagnosed = ""             // <1 year|1-5 years|5-10 years|10+ years
    var conditionsMedicated = ""             // Yes|Some|No

    // ─── Step 20: Ancestry ───────────────────────────────────────────────────
    var ethnicity = ""

    // ─── Navigation ──────────────────────────────────────────────────────────
    var stepIndex = 0

    /// Dynamic step list — conditional steps drop out when their gate doesn't apply.
    /// Mirrors Android rebuildActiveSteps()/isStepActive().
    var activeSteps: [SignupStep] {
        SignupStep.allCases.filter { isStepActive($0) }
    }

    var totalSteps: Int { activeSteps.count }

    var currentStep: SignupStep {
        let steps = activeSteps
        guard steps.indices.contains(stepIndex) else { return steps.first ?? .account }
        return steps[stepIndex]
    }

    var isLastStep: Bool { stepIndex >= totalSteps - 1 }

    private func isStepActive(_ step: SignupStep) -> Bool {
        switch step {
        case .menstrual:
            return gender == "Female" || gender == "Other"
        case .smokingDetail:
            return !smokingStatus.isEmpty && smokingStatus != "never"
        case .alcoholDetail:
            return !alcoholConsumption.isEmpty && alcoholConsumption != "None"
        case .conditionDetail:
            return !resolveList(medicalConditions, other: medicalConditionsOther).isEmpty
        default:
            return true
        }
    }

    // ─── State ───────────────────────────────────────────────────────────────
    var isLoading = false
    var errorMessage: String?
    var isAccountCreated = false

    // ─── OTP ─────────────────────────────────────────────────────────────────
    var otpCode = ""
    var isOTPLoading = false
    var otpMessage: String?

    // ─── Options (mirror Android OnboardingActivity.initCardStepConfigs) ──────

    let genderOptions   = ["Male", "Female", "Other"]
    let activityOptions = ["Mostly Sitting", "Light Activity", "Moderately Active", "Very Active", "Athlete"]

    let goalOptions: [SelectableCardOption] = [
        .init("Weight Loss",                title: "Lose Weight",      systemImage: "arrow.down.circle"),
        .init("Muscle Gain",                title: "Build Muscle",     systemImage: "dumbbell"),
        .init("Improve Fitness",            title: "Stay Fit",         systemImage: "figure.run"),
        .init("Manage a Health Condition",  title: "Manage Condition", systemImage: "heart.text.square"),
        .init("Boost Energy",               title: "Boost Energy",     systemImage: "bolt.fill"),
        .init("Improve Sleep",              title: "Sleep Better",     systemImage: "bed.double"),
        .init("Eat Healthier",              title: "Eat Healthier",    systemImage: "leaf"),
        .init("Improve Mental Health",      title: "Mental Health",    systemImage: "brain.head.profile"),
        .other()
    ]

    let recentWeightChangeOptions: [SelectableCardOption] = [
        .init("Gained",   title: "Gained",   systemImage: "arrow.up"),
        .init("Lost",     title: "Lost",     systemImage: "arrow.down"),
        .init("Stable",   title: "Stable",   systemImage: "equal"),
        .init("Not sure", title: "Not sure", systemImage: "questionmark")
    ]

    let occupationOptions: [SelectableCardOption] = [
        .init("desk",       title: "Desk / Office",   systemImage: "desktopcomputer"),
        .init("physical",   title: "Physical Labour", systemImage: "hammer"),
        .init("healthcare", title: "Healthcare",      systemImage: "cross.case"),
        .init("student",    title: "Student",         systemImage: "graduationcap"),
        .init("remote",     title: "Work from Home",  systemImage: "house"),
        .init("retired",    title: "Retired / Home",  systemImage: "sofa"),
        .other()
    ]

    let dietOptions: [SelectableCardOption] = [
        .init("Regular",       title: "Everything",    systemImage: "fork.knife"),
        .init("Vegetarian",    title: "Vegetarian",    systemImage: "carrot"),
        .init("Vegan",         title: "Vegan",         systemImage: "leaf"),
        .init("Keto",          title: "Keto",          systemImage: "flame"),
        .init("Mediterranean", title: "Mediterranean", systemImage: "fish"),
        .init("Gluten-Free",   title: "Gluten-Free",   systemImage: "allergens"),
        .other()
    ]

    let mealsOptions: [SelectableCardOption] = [
        .init("2", title: "1–2 meals", systemImage: "1.circle"),
        .init("3", title: "3 meals",   systemImage: "3.circle"),
        .init("4", title: "4–5 meals", systemImage: "4.circle"),
        .init("6", title: "6+ meals",  systemImage: "6.circle")
    ]

    let waterOptions: [SelectableCardOption] = [
        .init("2",  title: "I forget to drink",  systemImage: "drop"),
        .init("5",  title: "4–6 glasses",        systemImage: "drop.fill"),
        .init("8",  title: "7–9 glasses",        systemImage: "waterbottle"),
        .init("10", title: "10+ (champ!)",       systemImage: "drop.triangle.fill")
    ]

    let stressOptions: [SelectableCardOption] = [
        .init("1", title: "Rarely",        systemImage: "face.smiling"),
        .init("2", title: "Sometimes",     systemImage: "face.dashed"),
        .init("3", title: "Often",         systemImage: "exclamationmark.bubble"),
        .init("4", title: "Almost Always", systemImage: "exclamationmark.triangle")
    ]

    let screenTimeOptions: [SelectableCardOption] = [
        .init("low",       title: "I stop 1hr+ before",     systemImage: "moon.zzz"),
        .init("moderate",  title: "About 30 mins",          systemImage: "clock"),
        .init("high",      title: "Right until I sleep",    systemImage: "iphone"),
        .init("very_high", title: "I fall asleep with it",  systemImage: "iphone.radiowaves.left.and.right")
    ]

    let smokingOptions: [SelectableCardOption] = [
        .init("never",      title: "Never, not even once", systemImage: "hand.raised"),
        .init("ex",         title: "I quit — proud of it", systemImage: "checkmark.seal"),
        .init("social",     title: "Only socially",        systemImage: "person.2"),
        .init("occasional", title: "Sometimes",            systemImage: "smoke"),
        .init("regular",    title: "Daily habit",          systemImage: "smoke.fill")
    ]

    let alcoholOptions: [SelectableCardOption] = [
        .init("None",              title: "I don't drink",       systemImage: "nosign"),
        .init("Special Occasions", title: "Special occasions",   systemImage: "gift"),
        .init("Socially",          title: "Socially / weekends", systemImage: "person.2"),
        .init("Regularly",         title: "Few times a week",    systemImage: "calendar"),
        .init("Frequently",        title: "Almost daily",        systemImage: "wineglass.fill")
    ]

    let caffeineOptions: [SelectableCardOption] = [
        .init("none",          title: "No caffeine",   systemImage: "nosign"),
        .init("tea",           title: "Tea person",    systemImage: "cup.and.saucer"),
        .init("coffee",        title: "Coffee lover",  systemImage: "mug"),
        .init("energy_drinks", title: "Energy drinks", systemImage: "bolt"),
        .other()
    ]

    let smokingDurationOptions: [SelectableCardOption] = [
        .init("<1 year",    title: "Under a year"),
        .init("1-5 years",  title: "1–5 years"),
        .init("5-10 years", title: "5–10 years"),
        .init("10+ years",  title: "10+ years")
    ]

    let cigarettesPerDayOptions: [SelectableCardOption] = [
        .init("<5",    title: "Under 5"),
        .init("5-10",  title: "5–10"),
        .init("10-20", title: "10–20"),
        .init("20+",   title: "20+")
    ]

    let lastSmokedOptions: [SelectableCardOption] = [
        .init("This week",       title: "This week"),
        .init("This month",      title: "This month"),
        .init("This year",       title: "This year"),
        .init("Over a year ago", title: "Over a year ago")
    ]

    let drinksPerWeekOptions: [SelectableCardOption] = [
        .init("1-2",  title: "1–2"),
        .init("3-5",  title: "3–5"),
        .init("6-10", title: "6–10"),
        .init("10+",  title: "10+")
    ]

    let familyHistoryOptions: [SelectableCardOption] = [
        .init("Diabetes",             title: "Diabetes",       systemImage: "drop"),
        .init("Heart Disease",        title: "Heart Disease",  systemImage: "heart"),
        .init("Hypertension",         title: "Hypertension",   systemImage: "waveform.path.ecg"),
        .init("Cancer",               title: "Cancer",         systemImage: "cross.case"),
        .init("Stroke",               title: "Stroke",         systemImage: "brain"),
        .init("Thyroid Issues",       title: "Thyroid Issues", systemImage: "bolt.heart"),
        .init("Kidney Disease",       title: "Kidney Disease", systemImage: "cross.case.fill"),
        .init("Mental Health Issues", title: "Mental Health",  systemImage: "brain.head.profile"),
        .other(),
        .init("__none__", title: "None / Not Sure", systemImage: "xmark.circle", isNone: true)
    ]

    let familyRelativeOptions: [SelectableCardOption] = [
        .init("Parent",      title: "Parent(s)",      systemImage: "figure.2"),
        .init("Grandparent", title: "Grandparent(s)", systemImage: "figure.2.and.child.holdinghands"),
        .init("Sibling",     title: "Sibling(s)",     systemImage: "person.2"),
        .init("__none__",    title: "Not sure",       systemImage: "questionmark", isNone: true)
    ]

    let allergyOptions: [SelectableCardOption] = [
        .init("Peanuts/Tree Nuts", title: "Peanuts & Nuts",   systemImage: "leaf"),
        .init("Dairy",             title: "Dairy",            systemImage: "drop"),
        .init("Eggs",              title: "Eggs",             systemImage: "oval.portrait"),
        .init("Gluten",            title: "Gluten / Wheat",   systemImage: "allergens"),
        .init("Seafood",          title: "Seafood",          systemImage: "fish"),
        .init("Soy",               title: "Soy",              systemImage: "leaf.circle"),
        .init("Pollen",            title: "Pollen",           systemImage: "camera.macro"),
        .init("Dust",              title: "Dust",             systemImage: "wind"),
        .init("Pet Dander",        title: "Pet Dander",       systemImage: "pawprint"),
        .init("Penicillin",        title: "Penicillin",       systemImage: "pills"),
        .init("NSAIDs",            title: "NSAIDs / Aspirin", systemImage: "cross.vial"),
        .init("Latex",             title: "Latex",            systemImage: "hand.raised"),
        .other(),
        .init("__none__", title: "None", systemImage: "xmark.circle", isNone: true)
    ]

    let conditionOptions: [SelectableCardOption] = [
        .init("Diabetes",             title: "Diabetes",         systemImage: "drop"),
        .init("Hypertension",         title: "Hypertension",     systemImage: "waveform.path.ecg"),
        .init("Heart Disease",        title: "Heart Disease",    systemImage: "heart"),
        .init("Asthma",               title: "Asthma",           systemImage: "lungs"),
        .init("Thyroid Issues",       title: "Thyroid",          systemImage: "bolt.heart"),
        .init("Arthritis",            title: "Arthritis",        systemImage: "figure.walk"),
        .init("High Cholesterol",     title: "High Cholesterol", systemImage: "heart.circle"),
        .init("PCOS/Hormonal Issues", title: "PCOS/Hormonal",    systemImage: "drop.circle"),
        .init("Anxiety/Depression",   title: "Anxiety/Depression", systemImage: "brain.head.profile"),
        .init("Digestive Issues",     title: "Digestive Issues", systemImage: "fork.knife.circle"),
        .init("Kidney Issues",        title: "Kidney Issues",    systemImage: "cross.case.fill"),
        .other(),
        .init("__none__", title: "None of the above", systemImage: "xmark.circle", isNone: true)
    ]

    let medicationOptions: [SelectableCardOption] = [
        .init("Blood pressure", title: "Blood pressure", systemImage: "waveform.path.ecg"),
        .init("Diabetes",       title: "Diabetes",       systemImage: "drop"),
        .init("Cholesterol",    title: "Cholesterol",    systemImage: "heart.circle"),
        .init("Thyroid",        title: "Thyroid",        systemImage: "bolt.heart"),
        .init("Heart",          title: "Heart",          systemImage: "heart"),
        .init("Mental health",  title: "Mental health",  systemImage: "brain.head.profile"),
        .other(),
        .init("__none__", title: "None", systemImage: "xmark.circle", isNone: true)
    ]

    let menstrualStatusOptions: [SelectableCardOption] = [
        .init("regular",           title: "Regular",           systemImage: "circle"),
        .init("irregular",         title: "Irregular",         systemImage: "circle.dotted"),
        .init("perimenopause",     title: "Perimenopause",     systemImage: "clock.arrow.circlepath"),
        .init("menopause",         title: "Menopause",         systemImage: "checkmark.circle"),
        .init("prefer_not_to_say", title: "Prefer Not to Say", systemImage: "hand.raised")
    ]

    let menstrualSymptomOptions: [SelectableCardOption] = [
        .init("Cramps",            title: "Cramps",            systemImage: "bolt"),
        .init("Bloating",          title: "Bloating",          systemImage: "circle.circle"),
        .init("Mood Changes",      title: "Mood Changes",      systemImage: "face.dashed"),
        .init("Headaches",         title: "Headaches",         systemImage: "brain.head.profile"),
        .init("Fatigue",           title: "Fatigue",           systemImage: "battery.25"),
        .init("Breast Tenderness", title: "Breast Tenderness", systemImage: "heart"),
        .init("Acne",              title: "Acne",              systemImage: "face.smiling"),
        .init("Heavy Flow",        title: "Heavy Flow",        systemImage: "drop.fill"),
        .init("__none__", title: "None", systemImage: "xmark.circle", isNone: true)
    ]

    let pregnancyOptions: [SelectableCardOption] = [
        .init("not_pregnant",       title: "Not Pregnant",       systemImage: "xmark.circle"),
        .init("pregnant",           title: "Pregnant",           systemImage: "figure.stand"),
        .init("postpartum",         title: "Postpartum",         systemImage: "figure.and.child.holdinghands"),
        .init("trying_to_conceive", title: "Trying to Conceive", systemImage: "leaf")
    ]

    let cycleLengthOptions: [SelectableCardOption] = [
        .init("23", title: "21–25 days"),
        .init("28", title: "26–30 days"),
        .init("33", title: "31–35 days"),
        .init("0",  title: "Irregular")
    ]

    let periodLengthOptions: [SelectableCardOption] = [
        .init("2", title: "1–3 days"),
        .init("5", title: "4–5 days"),
        .init("6", title: "6–7 days"),
        .init("8", title: "8+ days")
    ]

    let contraceptionOptions: [SelectableCardOption] = [
        .init("none",    title: "None",              systemImage: "nosign"),
        .init("pill",    title: "Pill",              systemImage: "pills"),
        .init("iud",     title: "IUD",               systemImage: "cross.case"),
        .init("condom",  title: "Condom",            systemImage: "shield"),
        .init("implant", title: "Implant/Injection", systemImage: "syringe"),
        .other()
    ]

    let ethnicityOptions: [SelectableCardOption] = [
        .init("South Asian",       title: "South Asian"),
        .init("East Asian",        title: "East Asian"),
        .init("Southeast Asian",   title: "Southeast Asian"),
        .init("Middle Eastern",    title: "Middle Eastern"),
        .init("White/European",    title: "White/European"),
        .init("Black/African",     title: "Black/African"),
        .init("Hispanic/Latino",   title: "Hispanic/Latino"),
        .init("Mixed/Other",       title: "Mixed/Other"),
        .init("Prefer not to say", title: "Prefer not to say", systemImage: "hand.raised")
    ]

    let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
    let sunExposureOptions: [SelectableCardOption] = [
        .init("low",      title: "Mostly indoors",           systemImage: "house"),
        .init("moderate", title: "Some outdoor time",        systemImage: "sun.haze"),
        .init("high",     title: "Outdoors most of the day", systemImage: "sun.max")
    ]

    // ─── Value resolution helpers ─────────────────────────────────────────────

    /// Single-select: swap the "Other" sentinel for the typed free text.
    private func resolveSingle(_ value: String, other: String) -> String {
        value == SelectableCardOption.otherValue
            ? other.trimmingCharacters(in: .whitespaces)
            : value
    }

    /// Multi-select: drop "None"/"Other" sentinels, append the typed free text.
    private func resolveList(_ set: Set<String>, other: String) -> [String] {
        var list = set
            .filter { $0 != "__none__" && $0 != SelectableCardOption.otherValue }
            .sorted()
        let trimmed = other.trimmingCharacters(in: .whitespaces)
        if set.contains(SelectableCardOption.otherValue), !trimmed.isEmpty {
            list.append(trimmed)
        }
        return list
    }

    // ─── Validation ──────────────────────────────────────────────────────────

    private func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    var validationError: String? {
        switch currentStep {
        case .account:
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Please enter your name." }
            let e = email.trimmingCharacters(in: .whitespaces)
            if e.isEmpty                    { return "Please enter your email." }
            if !isValidEmail(e)             { return "Invalid email format." }
            if password.count < 6           { return "Password must be at least 6 characters." }
            if password != confirmPassword  { return "Passwords do not match." }
        case .personal:
            if gender.isEmpty               { return "Please select your gender." }
        case .body:
            if heightCm <= 0                { return "Please enter a valid height." }
            if weightKg <= 0                { return "Please enter a valid weight." }
        default:
            break
        }
        return nil
    }

    // ─── Navigation ──────────────────────────────────────────────────────────

    func next() {
        errorMessage = validationError
        guard errorMessage == nil else { return }
        // activeSteps recomputes on read, so an answer that reveals/hides a later
        // conditional step is reflected immediately (mirrors rebuildActiveSteps()).
        if stepIndex < totalSteps - 1 { stepIndex += 1 }
    }

    func back() {
        errorMessage = nil
        if stepIndex > 0 { stepIndex -= 1 }
    }

    // ─── Submit ───────────────────────────────────────────────────────────────
    // POST /api/auth/signup — keys mirror Android OnboardingActivity.buildPayload().

    func submit(auth: AuthManager) async {
        if let err = validationError { errorMessage = err; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        // These card questions start empty (for progressive reveal); if the user skipped
        // the step entirely, fall back to sensible defaults so the payload stays valid.
        let finalSmoking  = smokingStatus.isEmpty ? "never" : smokingStatus
        let finalAlcohol  = alcoholConsumption.isEmpty ? "None" : alcoholConsumption
        let finalCaffeine = caffeineHabit.isEmpty ? "none" : caffeineHabit

        // Derived smoking fields (mirror Android's habits collector switch).
        let smoker: Bool
        let smokingLevel: Int
        let smokingFrequency: String
        switch finalSmoking {
        case "social":     smoker = false; smokingLevel = 1; smokingFrequency = "Social"
        case "occasional": smoker = true;  smokingLevel = 2; smokingFrequency = "Occasional"
        case "regular":    smoker = true;  smokingLevel = 3; smokingFrequency = "Regular"
        default:           smoker = false; smokingLevel = 0; smokingFrequency = "Non-smoker" // never|ex
        }

        // Derived alcohol level (mirror Android).
        let alcoholLevel: Int
        switch finalAlcohol {
        case "Special Occasions": alcoholLevel = 1
        case "Socially":          alcoholLevel = 2
        case "Regularly":         alcoholLevel = 3
        case "Frequently":        alcoholLevel = 4
        default:                  alcoholLevel = 0
        }

        let resolvedGoal        = resolveSingle(primaryGoal, other: primaryGoalOther)
        let resolvedOccupation  = resolveSingle(occupationType, other: occupationOther)
        let resolvedDiet        = resolveSingle(dietType, other: dietTypeOther)
        let resolvedCaffeine    = resolveSingle(finalCaffeine, other: caffeineOther)
        let resolvedContra      = resolveSingle(contraceptionMethod, other: contraceptionOther)
        let resolvedConditions  = resolveList(medicalConditions, other: medicalConditionsOther)

        // Menstrual block only when applicable (Android: not "not_applicable").
        let menstrualApplicable = (gender == "Female" || gender == "Other")
            && menstrualStatus != "not_applicable"

        // Argument order MUST match SignupRequest's property declaration order
        // (Swift's synthesised memberwise initializer).
        let request = SignupRequest(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            confirmPassword: confirmPassword,
            name: name,
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
            gender: gender,
            dateOfBirth: formatter.string(from: dateOfBirth),
            location: location.isEmpty ? nil : location,
            ethnicity: ethnicity.isEmpty ? nil : ethnicity,
            height: heightCm,
            weight: weightKg,
            waistCircumference: waistUnknown ? nil : waistCircumferenceCm,
            primaryGoal: resolvedGoal.isEmpty ? nil : resolvedGoal,
            recentWeightChange: recentWeightChange.isEmpty ? nil : recentWeightChange,
            activityLevel: activityLevel,
            occupationType: resolvedOccupation.isEmpty ? nil : resolvedOccupation,
            dietType: resolvedDiet,
            mealsPerDay: Int(mealsPerDaySel) ?? 3,
            waterIntake: Int(waterIntakeSel) ?? 6,
            sleepHours: sleepHours > 0 ? sleepHours : nil,
            stressLevel: Int(stressSel) ?? 2,
            screenTimeBeforeBed: screenTimeBeforeBed,
            sunExposure: sunExposure,
            smoker: smoker,
            smokingLevel: smokingLevel,
            smokingFrequency: smokingFrequency,
            smokingStatus: finalSmoking,
            alcoholConsumption: finalAlcohol,
            alcoholLevel: alcoholLevel,
            caffeineHabit: resolvedCaffeine,
            smokingDuration: smokingDuration.isEmpty ? nil : smokingDuration,
            cigarettesPerDay: cigarettesPerDay.isEmpty ? nil : cigarettesPerDay,
            lastSmoked: lastSmoked.isEmpty ? nil : lastSmoked,
            drinksPerWeek: drinksPerWeek.isEmpty ? nil : drinksPerWeek,
            conditionsDiagnosed: conditionsDiagnosed.isEmpty ? nil : conditionsDiagnosed,
            conditionsMedicated: conditionsMedicated.isEmpty ? nil : conditionsMedicated,
            familyHistory: resolveList(familyHistory, other: familyHistoryOther),
            familyHistoryRelatives: resolveList(familyHistoryRelatives, other: ""),
            allergies: resolveList(allergies, other: allergiesOther),
            medicalConditions: resolvedConditions,
            medicationCategories: resolveList(medicationCategories, other: medicationOther),
            menstrualStatus: menstrualApplicable ? menstrualStatus : nil,
            averageCycleLength: menstrualApplicable ? (Int(cycleLengthSel) ?? 28) : nil,
            averagePeriodLength: menstrualApplicable ? (Int(periodLengthSel) ?? 5) : nil,
            menstrualSymptoms: menstrualApplicable ? resolveList(menstrualSymptoms, other: "") : nil,
            contraceptionMethod: menstrualApplicable ? (resolvedContra.isEmpty ? nil : resolvedContra) : nil,
            pregnancyStatus: menstrualApplicable ? pregnancyStatus : nil,
            bloodType: bloodType.isEmpty ? nil : bloodType,
            weeklyGoal: 0.5
        )

        do {
            try await auth.signup(request)
            isAccountCreated = true
            await sendOTP(auth: auth)
        } catch let err as APIError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Signup failed. Please try again."
        }
    }

    // ─── OTP ─────────────────────────────────────────────────────────────────

    func sendOTP(auth: AuthManager) async {
        isOTPLoading = true
        otpMessage = nil
        defer { isOTPLoading = false }
        do {
            let response = try await auth.sendOTP(email: email)
            if response.alreadyVerified == true {
                await auth.activateSession()
            } else {
                otpMessage = response.emailSent == true
                    ? "Code sent to \(email)."
                    : "Couldn't email the code — enter it manually or skip."
            }
        } catch let err as APIError {
            otpMessage = err.userMessage
        } catch {
            otpMessage = "Could not send code. You can skip verification for now."
        }
    }

    func verifyOTP(auth: AuthManager) async {
        guard !otpCode.isEmpty else { otpMessage = "Please enter the 6-digit code."; return }
        isOTPLoading = true
        otpMessage = nil
        defer { isOTPLoading = false }
        do {
            let response = try await auth.verifyOTP(email: email, otp: otpCode)
            if response.verified == true {
                await auth.activateSession()
            } else {
                otpMessage = response.message ?? "Incorrect code. Please try again."
            }
        } catch let err as APIError {
            otpMessage = err.userMessage
        } catch {
            otpMessage = "Verification failed. Please try again."
        }
    }

    func skipOTP(auth: AuthManager) async {
        await auth.activateSession()
    }
}
