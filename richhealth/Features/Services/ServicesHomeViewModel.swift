import Foundation
import Observation
import CoreLocation

// MARK: - Sheet routing

enum ServicesSheet: Identifiable {
    case nutriCheck, feed, workouts, doctor, healthAnalysis

    var id: String {
        switch self {
        case .nutriCheck:     "nutriCheck"
        case .feed:           "feed"
        case .workouts:       "workouts"
        case .doctor:         "doctor"
        case .healthAnalysis: "healthAnalysis"
        }
    }
}

// MARK: - AQI status

enum AQILoadStatus {
    case idle       // Never attempted
    case requesting // Waiting for location permission / GPS fix
    case loaded     // Data successfully fetched
    case denied     // Location permission denied
    case noData     // Location OK but no AQI data for this city
}

// MARK: - ViewModel

@Observable
@MainActor
final class ServicesHomeViewModel {

    // MARK: Data

    var briefingCards: [BriefingCard] = []
    var briefingSource: String?
    var briefingGeneratedAt: String?
    var digest: DailyDigestResponse?
    var dietaryInsights: DietaryInsightsResponse?
    var feedItems: [FeedItem] = []
    var feedTotalPages: Int = 1
    var workouts: [WorkoutRecord] = []
    var connectedDoctors: [DoctorSearchResult] = []
    var incomingDoctorRequests: [IncomingDoctorRequest] = []

    // Health Analysis
    var healthAnalysis: HealthAnalysis?
    var isGeneratingAnalysis = false

    // Daily Check-In
    var checkIn: CheckInHomeCardResponse?

    // AQI
    var aqiData: AQIData?
    var aqiHistory: [AQIData] = []
    var locationCity: String?
    var locationState: String?
    var aqiStatus: AQILoadStatus = .idle

    // MARK: UI state

    var isLoading = false
    // Per-card loading flags — each clears when THAT card's data lands, so a fast card (workouts)
    // isn't stuck behind the slowest call (dietary can take ~45s). Drives inline card spinners.
    var isLoadingBriefing = false
    var isLoadingDigest = false
    var isLoadingDietary = false
    var isLoadingFeed = false
    var isLoadingWorkouts = false
    var isLoadingDoctors = false
    var isLoadingAnalysis = false
    var isLoadingCheckIn = false
    var showPaywall = false
    var activeSheet: ServicesSheet?

    // MARK: Services

    private let insightsService = InsightsService()
    private let feedService = FeedService()
    private let aqiService = AQIService()
    private let workoutService = WorkoutService()
    private let doctorService = DoctorService()
    private let analysisService = HealthAnalysisService()
    private let api = APIClient()

    private var hasLoaded = false

    // MARK: - Load

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        // Mark every card as loading up front so each shows its inline spinner until its data lands.
        isLoadingBriefing = true; isLoadingDigest = true; isLoadingDietary = true
        isLoadingFeed = true; isLoadingWorkouts = true; isLoadingDoctors = true
        isLoadingAnalysis = true; isLoadingCheckIn = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadBriefing() }
            group.addTask { await self.loadDigest() }
            group.addTask { await self.loadDietary() }
            group.addTask { await self.loadFeed() }
            group.addTask { await self.loadWorkouts() }
            group.addTask { await self.loadDoctors() }
            group.addTask { await self.loadHealthAnalysis() }
            group.addTask { await self.loadCheckIn() }
        }
    }

    /// Explicit pull-to-refresh: bust all session caches so user gets truly fresh data.
    func reload() async {
        hasLoaded = false
        SessionCache.clearAll()
        await load()
        await loadAQI()
    }

    // MARK: - AQI + location (called from view's own .task — runs concurrently with load())

    func loadAQI() async {
        // Bundle type for caching city + AQI together (1-hour TTL).
        struct AQIBundle: Codable {
            let city: String; let state: String
            let aqiData: AQIData?; let aqiHistory: [AQIData]
        }

        // Cache hit: show instantly and skip the entire location + geocode + API flow.
        if let cached = SessionCache.load(AQIBundle.self, key: "aqi", maxAge: 3600) {
            rhLog("← AQI cache hit: \(cached.city), aqi=\(cached.aqiData?.aqius ?? -1)")
            locationCity = cached.city; locationState = cached.state
            aqiData = cached.aqiData; aqiHistory = cached.aqiHistory
            aqiStatus = cached.aqiData != nil ? .loaded : .noData
            return
        }

        // Cache miss: request fresh location, geocode, then hit the AQI API.
        // locationServicesEnabled() blocks — run it off the main actor to avoid the UI-hang warning.
        let servicesEnabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard servicesEnabled else {
            rhLog("✗ AQI: location services disabled")
            aqiStatus = .denied
            return
        }
        rhLog("→ AQI: requesting location...")
        aqiStatus = .requesting
        do {
            // CLLocationUpdate.liveUpdates() handles authorization automatically (iOS 17+).
            var attempts = 0
            for try await update in CLLocationUpdate.liveUpdates() {
                if let loc = update.location {
                    rhLog("← AQI: got location \(loc.coordinate.latitude),\(loc.coordinate.longitude)")
                    if let place = await aqiService.reverseGeocode(
                        latitude:  loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude
                    ) {
                        rhLog("← AQI: geocoded to \(place.city), \(place.state)")
                        locationCity = place.city; locationState = place.state
                        let fetched  = try? await aqiService.fetchLatest(city: place.city, state: place.state)
                        let history  = (try? await aqiService.fetchHistory(city: place.city)) ?? []
                        aqiData = fetched; aqiHistory = history
                        aqiStatus = fetched != nil ? .loaded : .noData
                        rhLog("← AQI: fetch result aqi=\(fetched?.aqius ?? -1) status=\(aqiStatus)")
                        if fetched != nil {
                            SessionCache.save(AQIBundle(city: place.city, state: place.state,
                                                        aqiData: fetched, aqiHistory: history), key: "aqi")
                        }
                    } else {
                        rhLog("✗ AQI: reverseGeocode returned nil for \(loc.coordinate.latitude),\(loc.coordinate.longitude)")
                        aqiStatus = .noData
                    }
                    break
                }
                attempts += 1
                rhLog("→ AQI: location update \(attempts) had no fix (update.location == nil)")
                if attempts >= 10 { rhLog("✗ AQI: gave up after 10 nil updates"); aqiStatus = .noData; break }
            }
            if aqiStatus == .requesting { aqiStatus = .noData }
        } catch {
            rhLog("✗ AQI: liveUpdates threw — \(error.localizedDescription)")
            aqiStatus = .denied
        }
    }

    // MARK: - Private loaders

    /// Stale-while-revalidate: show today's cached briefing immediately, then refresh silently.
    /// Briefing is generated once per day by the backend; no value in re-fetching more often.
    // Cache-first: a fresh cache entry (warmed on splash, or from earlier today) is authoritative —
    // the backend regenerates the briefing/digest once per day and dietary changes at most a few
    // times a day. Showing cache instantly and SKIPPING the slow re-fetch (briefing ~26s, dietary
    // ~46s) is the whole point of the splash warmup. Pull-to-refresh (reload) clears the cache first.
    private func loadBriefing() async {
        defer { isLoadingBriefing = false }
        if let cached = SessionCache.loadToday(BriefingResponse.self, key: "briefing") {
            briefingCards = cached.cards; briefingSource = cached.source
            briefingGeneratedAt = cached.generatedAt
            return
        }
        if let r = try? await insightsService.fetchBriefing() {
            SessionCache.save(r, key: "briefing")
            briefingCards = r.cards; briefingSource = r.source
            briefingGeneratedAt = r.generatedAt
        }
    }

    /// Same-day cache for the daily digest (daily rhythm content).
    private func loadDigest() async {
        defer { isLoadingDigest = false }
        if let cached = SessionCache.loadToday(DailyDigestResponse.self, key: "digest") {
            digest = cached
            return
        }
        if let r = try? await insightsService.fetchDailyDigest(city: locationCity) {
            SessionCache.save(r, key: "digest")
            digest = r
        }
    }

    /// 8-hour cache for dietary insights — changes when user adds new health data.
    private func loadDietary() async {
        defer { isLoadingDietary = false }
        if let cached = SessionCache.load(DietaryInsightsResponse.self, key: "dietary", maxAge: 8 * 3600) {
            dietaryInsights = cached
            return
        }
        do {
            let fresh = try await insightsService.fetchDietaryInsights()
            SessionCache.save(fresh, key: "dietary")
            dietaryInsights = fresh
        } catch let err as APIError {
            if case .limitReached = err { showPaywall = true }
        } catch {}
    }

    /// Force a fresh dietary fetch (tapping the Dietary card, e.g. to clear a stale state).
    func refreshDietary() async {
        isLoadingDietary = true
        defer { isLoadingDietary = false }
        do {
            let fresh = try await insightsService.fetchDietaryInsights()
            SessionCache.save(fresh, key: "dietary")
            dietaryInsights = fresh
        } catch let err as APIError {
            if case .limitReached = err { showPaywall = true }
        } catch {}
    }

    private func loadFeed() async {
        defer { isLoadingFeed = false }
        guard let r = try? await feedService.fetchFeed(page: 1, limit: 20) else { return }
        feedItems      = r.items
        feedTotalPages = r.totalPages
    }

    private func loadWorkouts() async {
        defer { isLoadingWorkouts = false }
        workouts = (try? await workoutService.fetchWorkouts()) ?? []
    }

    private func loadDoctors() async {
        defer { isLoadingDoctors = false }
        async let connected = doctorService.fetchConnectedDoctors()
        async let incoming  = doctorService.fetchIncomingRequests()
        connectedDoctors       = (try? await connected) ?? []
        incomingDoctorRequests = (try? await incoming) ?? []
    }

    // MARK: - Actions

    private func loadHealthAnalysis() async {
        defer { isLoadingAnalysis = false }
        healthAnalysis = (try? await analysisService.fetch())?.analysis
    }

    private func loadCheckIn() async {
        defer { isLoadingCheckIn = false }
        // showsLoader:false — shown inline on the dashboard card, not via the global overlay.
        checkIn = try? await api.send(Endpoint(path: "/api/checkin/home-card", showsLoader: false, loaderMessage: "Loading your check-in…"), as: CheckInHomeCardResponse.self)
    }

    func generateAnalysis() async {
        isGeneratingAnalysis = true
        defer { isGeneratingAnalysis = false }
        do {
            let result = try await analysisService.generate()
            healthAnalysis = result.analysis
        } catch let err as APIError {
            // §10.6: a backend limit must surface the paywall, not be swallowed.
            if case .limitReached = err { showPaywall = true }
            else if case .notAllowed = err { showPaywall = true }
        } catch { /* transient/network — leave the card as-is */ }
    }

    func deleteWorkout(id: String) async {
        try? await workoutService.deleteWorkout(id: id)
        workouts.removeAll { $0.id == id }
    }

    func respondToDoctor(email: String, accept: Bool) async {
        try? await doctorService.respondToRequest(email: email, accept: accept)
        incomingDoctorRequests.removeAll { $0.email == email }
        if accept { await loadDoctors() }
    }
}
