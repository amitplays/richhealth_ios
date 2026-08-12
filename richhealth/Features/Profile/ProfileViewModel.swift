import Foundation

@Observable @MainActor final class ProfileViewModel {
    var isLoading = false
    var isSaving = false
    var proAccess: ProAccess?
    var usageData: UserUsageResponse?
    var showEditSheet = false
    var showPaywall = false
    var showMemorySheet = false
    var showChangePassword = false
    var showFullUsage = false
    var saveError: String?
    var aiSaveError: String?
    var isAISaving = false

    // Family / Membership — mirrors Android Plan tab "MEMBERSHIP" section
    var relationships: [RelationshipRecord] = []
    var isFamilyPlanOwner = false
    var familyProMemberCount = 0
    var maxFamilyMembers = 5

    /// Number of pending incoming family requests → drives the Profile header/toolbar badge.
    var pendingRequestCount = 0

    // AQI from SessionCache shown in header "At a Glance".
    var cachedAQI: Int? = nil

    // AI Memory management
    var memories: [AIMemory] = []
    var isLoadingMemories = false

    // UserDefaults-persisted display preferences (local only, not synced to server).
    var isMetric: Bool = UserDefaults.standard.object(forKey: "rh.isMetric") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isMetric, forKey: "rh.isMetric") }
    }
    var biometricEnabled: Bool = UserDefaults.standard.bool(forKey: "rh.biometricEnabled") {
        didSet { UserDefaults.standard.set(biometricEnabled, forKey: "rh.biometricEnabled") }
    }
    // Master switch for local (on-device) reminders — the app's `receiveNotifications` intent.
    var notificationsEnabled: Bool = UserDefaults.standard.bool(forKey: "rh.notificationsEnabled") {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "rh.notificationsEnabled") }
    }

    private let api = APIClient()

    // ── Edit-form state ────────────────────────────────────────────────────────

    // Account
    var editName = ""
    var editEmail = ""
    var editPhone = ""
    var editGender = ""
    var editDOB: Date = .now
    var editDOBEnabled = false
    var editLocation = ""
    var editEthnicity = ""

    // Physical
    var editHeight: Double = 0           // cm
    var editWeight: Double = 0           // kg
    var editWaist: Double = 0            // cm
    var editBloodType = ""

    // Fitness
    var editGoal = ""
    var editActivityLevel = 3
    var editDietType = ""

    // Medical
    var editConditions = ""              // comma-separated
    var editAllergies = ""
    var editFamilyHistory = ""           // comma-separated

    // Lifestyle
    var editSleepHours: Double = 7
    var editWaterIntake: Int = 8         // glasses
    var editMealsPerDay: Int = 3
    var editStressLevel: Int = 2         // 1–4
    var editScreenTime = ""              // "low"|"moderate"|"high"|"very_high"
    var editSunExposure = ""             // "low"|"moderate"|"high"
    var editOccupationType = ""

    // Habits
    var editSmokingStatus = "never"      // "never"|"ex"|"social"|"occasional"|"regular"
    var editAlcohol = "None"             // "None"|"Rarely"|...|"Frequently"
    var editCaffeine = "none"            // "none"|"tea"|"coffee"|"both"|"energy_drinks"

    // Reproductive health
    var editMenstrualStatus = ""
    var editPregnancyStatus = ""
    var editCycleLength: Int = 28
    var editPeriodLength: Int = 5
    var editContraception = ""
    var editMenstrualSymptoms = ""       // comma-separated

    // ── AI-preference state ────────────────────────────────────────────────────

    var aiTone = "balanced"
    var aiReplyLength = "balanced"
    var aiCustomInstructions = ""
    var aiSaveMemories = true
    var aiShowThinking = false
    var aiImproveModel = true
    var aiAutofillCards = false

    // ── Options ───────────────────────────────────────────────────────────────

    let smokingOptions   = [("Never", "never"), ("I quit", "ex"), ("Only socially", "social"),
                            ("Sometimes", "occasional"), ("Daily habit", "regular")]
    let alcoholOptions   = ["None", "Rarely", "Special Occasions", "Socially", "Regularly", "Frequently"]
    let caffeineOptions  = [("No caffeine", "none"), ("Tea", "tea"), ("Coffee", "coffee"),
                            ("Tea & coffee", "both"), ("Energy drinks", "energy_drinks")]
    let screenTimeOptions = [("Not set", ""), ("Low (stops 1hr+ before)", "low"),
                             ("Moderate (~30 min)", "moderate"),
                             ("High (right until sleep)", "high"),
                             ("Very high (falls asleep with screen)", "very_high")]
    let sunOptions       = [("Not set", ""), ("Low (mostly indoors)", "low"),
                            ("Moderate (some outdoor time)", "moderate"),
                            ("High (mostly outdoors)", "high")]
    let menstrualStatusOptions = [("Not set", ""), ("Regular", "regular"), ("Irregular", "irregular"),
                                  ("Perimenopause", "perimenopause"), ("Menopause", "menopause"),
                                  ("Not applicable", "not_applicable"),
                                  ("Prefer not to say", "prefer_not_to_say")]
    let pregnancyStatusOptions = [("Not set", ""), ("Not pregnant", "not_pregnant"),
                                  ("Pregnant", "pregnant"), ("Postpartum", "postpartum"),
                                  ("Trying to conceive", "trying_to_conceive"),
                                  ("Not applicable", "not_applicable")]
    let stressOptions    = [(1, "Rarely"), (2, "Sometimes"), (3, "Often"), (4, "Almost always")]

    // ── Load ──────────────────────────────────────────────────────────────────

    // Guard against re-runs on tab switches (§4: one fresh fetch per session).
    private var hasLoaded = false

    func load(auth: AuthManager) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        await auth.refreshProfile(showsLoader: true)   // Profile tab: show the branded loader while user values load
        syncAIPrefs(from: auth.currentUser)
        loadCachedAQI()
        async let proFetch  = auth.fetchProAccess()
        async let usageFetch = auth.fetchUsage()
        async let relFetch  = api.send(Endpoint(path: "/api/users/relationships", showsLoader: false, loaderMessage: "Loading your family…"),
                                       as: RelationshipsResponse.self)
        proAccess = try? await proFetch
        usageData = try? await usageFetch
        if let rel = try? await relFetch {
            relationships       = rel.relationships.filter { $0.status == "accepted" || $0.status == "dependent" }
            isFamilyPlanOwner   = rel.isFamilyPlanOwner   ?? false
            familyProMemberCount = rel.familyProMemberCount ?? 0
            maxFamilyMembers    = rel.maxFamilyMembers     ?? 5
        }
        await loadPendingRequests()
    }

    /// Refresh the count of pending incoming family requests (badge). Silent on failure.
    func loadPendingRequests() async {
        pendingRequestCount = (try? await FamilyService().fetchIncomingRequests())?.count ?? 0
    }

    func reload(auth: AuthManager) async {
        hasLoaded = false
        await load(auth: auth)
    }

    func removeFamilyMember(userId: String) async {
        struct RemoveBody: Encodable { let memberId: String }
        let body = try? JSONEncoder().encode(RemoveBody(memberId: userId))
        _ = try? await api.send(
            Endpoint(path: "/api/payment/family-member/remove", method: .post, body: body, showsLoader: false, loaderMessage: "Removing member…")
        )
        relationships.removeAll { $0.userId == userId }
        familyProMemberCount = max(0, familyProMemberCount - 1)
    }

    private func syncAIPrefs(from user: UserProfile?) {
        guard let prefs = user?.aiPreferences else { return }
        aiTone = prefs.tone ?? "balanced"
        aiReplyLength = prefs.replyLength ?? "balanced"
        aiCustomInstructions = prefs.customInstructions ?? ""
        aiSaveMemories = prefs.saveMemories ?? true
        aiShowThinking = prefs.showThinking ?? false
        aiImproveModel = prefs.improveModel ?? true
        aiAutofillCards = prefs.autofillCards ?? false
    }

    private func loadCachedAQI() {
        // AQI is cached by ServicesHomeViewModel under key "aqi".
        // AQIBundle is a local struct there; we decode the compatible shape here.
        struct AQICacheBundle: Codable { let aqiData: AQICacheData? }
        struct AQICacheData: Codable { let aqius: Int }
        if let b = SessionCache.load(AQICacheBundle.self, key: "aqi", maxAge: 3600) {
            cachedAQI = b.aqiData?.aqius
        }
    }

    func loadMemories(auth: AuthManager) async {
        isLoadingMemories = true
        if let resp = try? await api.send(Endpoint(path: "/api/user/memories", showsLoader: false, loaderMessage: "Loading your memories…"),
                                          as: AIMemoriesResponse.self) {
            memories = resp.memories
        }
        isLoadingMemories = false
    }

    func deleteMemory(id: String, auth: AuthManager) async {
        _ = try? await api.send(Endpoint(path: "/api/user/memories/\(id)", method: .delete, showsLoader: false, loaderMessage: "Deleting memory…"))
        memories.removeAll { $0.id == id }
    }

    // ── Edit profile ──────────────────────────────────────────────────────────

    func prepareEditForm(from user: UserProfile?) {
        editName = user?.name ?? ""
        editEmail = user?.email ?? ""
        editPhone = user?.phoneNumber ?? ""
        editGender = user?.gender ?? ""
        editLocation = user?.location ?? ""
        editEthnicity = user?.ethnicity ?? ""
        editHeight = user?.height ?? 0
        editWeight = user?.weight ?? 0
        editWaist = user?.waistCircumference ?? 0
        editGoal = user?.primaryGoal ?? ""
        editActivityLevel = user?.activityLevel ?? 3
        editDietType = user?.dietType ?? ""
        editBloodType = user?.bloodType ?? ""
        editConditions = user?.medicalConditions?.joined(separator: ", ") ?? ""
        editAllergies = user?.allergies?.joined(separator: ", ") ?? ""
        editFamilyHistory = user?.familyHistory?.joined(separator: ", ") ?? ""
        editSleepHours = user?.sleepHours ?? 7
        editWaterIntake = user?.waterIntake ?? 8
        editMealsPerDay = user?.mealsPerDay ?? 3
        editStressLevel = user?.stressLevel ?? 2
        editScreenTime = user?.screenTimeBeforeBed ?? ""
        editSunExposure = user?.sunExposure ?? ""
        editOccupationType = user?.occupationType ?? ""
        editSmokingStatus = user?.smokingStatus ?? "never"
        editAlcohol = user?.alcoholConsumption ?? "None"
        editCaffeine = user?.caffeineHabit ?? "none"
        editMenstrualStatus = user?.menstrualStatus ?? ""
        editPregnancyStatus = user?.pregnancyStatus ?? ""
        editCycleLength = user?.averageCycleLength ?? 28
        editPeriodLength = user?.averagePeriodLength ?? 5
        editContraception = user?.contraceptionMethod ?? ""
        editMenstrualSymptoms = user?.menstrualSymptoms?.joined(separator: ", ") ?? ""

        if let dobStr = user?.dateOfBirth, let dob = UserProfile.parseDOB(dobStr) {
            editDOB = dob
            editDOBEnabled = true
        } else {
            editDOB = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
            editDOBEnabled = false
        }
        saveError = nil
    }

    func saveProfile(auth: AuthManager) async {
        isSaving = true
        defer { isSaving = false }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"

        func nonEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        func csv(_ s: String) -> [String]? {
            let arr = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return arr.isEmpty ? nil : arr
        }

        var request = UpdateProfileRequest()
        request.name = nonEmpty(editName)
        request.email = nonEmpty(editEmail)
        request.phoneNumber = nonEmpty(editPhone)
        request.dateOfBirth = editDOBEnabled ? df.string(from: editDOB) : nil
        request.gender = nonEmpty(editGender)
        request.location = nonEmpty(editLocation)
        request.ethnicity = nonEmpty(editEthnicity)
        request.height = editHeight > 0 ? editHeight : nil
        request.weight = editWeight > 0 ? editWeight : nil
        request.waistCircumference = editWaist > 0 ? editWaist : nil
        request.bloodType = nonEmpty(editBloodType)
        request.activityLevel = editActivityLevel
        request.primaryGoal = nonEmpty(editGoal)
        request.dietType = nonEmpty(editDietType)
        request.medicalConditions = csv(editConditions)
        request.allergies = csv(editAllergies)
        request.familyHistory = csv(editFamilyHistory)
        request.sleepHours = editSleepHours
        request.waterIntake = editWaterIntake
        request.mealsPerDay = editMealsPerDay
        request.stressLevel = editStressLevel
        request.screenTimeBeforeBed = nonEmpty(editScreenTime)
        request.sunExposure = nonEmpty(editSunExposure)
        request.occupationType = nonEmpty(editOccupationType)
        request.smokingStatus = editSmokingStatus
        request.alcoholConsumption = editAlcohol
        request.caffeineHabit = editCaffeine
        request.menstrualStatus = nonEmpty(editMenstrualStatus)
        request.pregnancyStatus = nonEmpty(editPregnancyStatus)
        request.averageCycleLength = editCycleLength > 0 ? editCycleLength : nil
        request.averagePeriodLength = editPeriodLength > 0 ? editPeriodLength : nil
        request.contraceptionMethod = nonEmpty(editContraception)
        request.menstrualSymptoms = csv(editMenstrualSymptoms)

        do {
            try await auth.updateProfile(request)
            showEditSheet = false
            saveError = nil
        } catch {
            saveError = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }

    // ── AI preferences ─────────────────────────────────────────────────────────

    func saveAIPreferences(auth: AuthManager) async {
        isAISaving = true
        defer { isAISaving = false }
        var request = UpdateProfileRequest()
        request.aiPreferences = AIPreferences(
            tone: aiTone,
            replyLength: aiReplyLength,
            customInstructions: aiCustomInstructions,
            saveMemories: aiSaveMemories,
            showThinking: aiShowThinking,
            improveModel: aiImproveModel,
            autofillCards: aiAutofillCards
        )
        do {
            try await auth.updateProfile(request)
            syncAIPrefs(from: auth.currentUser)
        } catch {
            aiSaveError = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}
