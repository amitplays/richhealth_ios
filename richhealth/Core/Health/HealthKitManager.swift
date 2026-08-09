import Foundation
import HealthKit

/// Reads Apple Health / Apple Watch data (read-only) and auto-saves it to the RichHealth
/// backend as measurements. Native replacement for Android's Google Fit "Connect a Device".
///
/// Shared singleton so the Services card, the sync sheet, and the Profile header all show
/// the same live state (connection, latest heart rate, last-sync). Sync is automatic and
/// throttled — the user never has to tap "save".
@MainActor @Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    /// A single fetched value, saved to the backend as a "measurement".
    struct Reading: Identifiable {
        let id = UUID()
        let metric: Metric
        let date: Date
        /// Stable dedup identity: the HealthKit sample UUID for point-in-time metrics, or a
        /// per-day key for aggregates (steps/energy/sleep have no single sample UUID).
        let dedupID: String
        let backendValue: String
        let display: String
    }

    enum Metric: String, CaseIterable, Identifiable {
        case steps, heartRate, restingHeartRate, bloodOxygen, bloodPressure
        case temperature, weight, activeEnergy, sleep

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steps:            "Steps"
            case .heartRate:        "Heart Rate"
            case .restingHeartRate: "Resting Heart Rate"
            case .bloodOxygen:      "Oxygen Saturation"
            case .bloodPressure:    "Blood Pressure"
            case .temperature:      "Temperature"
            case .weight:           "Weight"
            case .activeEnergy:     "Active Energy"
            case .sleep:            "Sleep"
            }
        }

        var unit: String {
            switch self {
            case .steps:                        "count"
            case .heartRate, .restingHeartRate: "bpm"
            case .bloodOxygen:                  "%"
            case .bloodPressure:                "mmHg"
            case .temperature:                  "°C"
            case .weight:                       "kg"
            case .activeEnergy:                 "kcal"
            case .sleep:                        "hr"
            }
        }

        var icon: String {
            switch self {
            case .steps:            "figure.walk"
            case .heartRate:        "heart.fill"
            case .restingHeartRate: "heart.text.square"
            case .bloodOxygen:      "lungs.fill"
            case .bloodPressure:    "waveform.path.ecg"
            case .temperature:      "thermometer.medium"
            case .weight:           "scalemass.fill"
            case .activeEnergy:     "flame.fill"
            case .sleep:            "bed.double.fill"
            }
        }
    }

    private static let connectedKey = "healthKitConnected"
    private static let lastSyncKey  = "healthKitLastSync"
    private static let syncedKeysKey = "healthKitSyncedKeys"

    /// Identities (HK sample UUIDs / per-day keys) already posted to the backend. Persisted so
    /// duplicates never get created across syncs — no backend unique key or schema change needed.
    private var syncedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.syncedKeysKey) ?? []) }
        set {
            // Cap to avoid unbounded UserDefaults growth over the app's lifetime.
            let arr = Array(newValue)
            UserDefaults.standard.set(arr.count > 2000 ? Array(arr.suffix(2000)) : arr, forKey: Self.syncedKeysKey)
        }
    }

    /// Clear the dedup ledger — call on logout so identities don't carry across accounts.
    func clearSyncState() { UserDefaults.standard.removeObject(forKey: Self.syncedKeysKey) }

    private let store = HKHealthStore()
    private let bpm = HKUnit.count().unitDivided(by: .minute())
    private var isSyncing = false
    private var didRequestAuth = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private(set) var readings: [Reading] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// Latest heart rate — the headline metric shown on the card + Profile.
    private(set) var latestHeartRate: Int?
    private(set) var latestHeartRateAt: Date?

    /// Persisted so the "Connected" pill and last-sync survive relaunches. Backed by UserDefaults.
    private(set) var isConnected: Bool { didSet { UserDefaults.standard.set(isConnected, forKey: Self.connectedKey) } }
    private(set) var lastSyncTS: Double { didSet { UserDefaults.standard.set(lastSyncTS, forKey: Self.lastSyncKey) } }

    private init() {
        isConnected = UserDefaults.standard.bool(forKey: Self.connectedKey)
        lastSyncTS  = UserDefaults.standard.double(forKey: Self.lastSyncKey)
    }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let quantities: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .oxygenSaturation,
            .bloodPressureSystolic, .bloodPressureDiastolic,
            .bodyTemperature, .appleSleepingWristTemperature, .bodyMass, .activeEnergyBurned
        ]
        for id in quantities {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }

    // MARK: - Public entry points

    /// Full sync: silent auth → read latest → auto-save to backend. Safe to call anytime
    /// (the system only shows the permission sheet the first time).
    /// Full sync: silent auth → read latest → save to backend. Used by the detail sheet.
    func sync() async {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await ensureAuthorized()
        await fetch()
        await saveAll()
    }

    /// Auto-sync on app foreground / screen appear. ALWAYS re-reads the on-device values
    /// (cheap) so the UI is current; only the backend save is throttled to once per interval.
    func autoSyncIfNeeded(minInterval: TimeInterval = 900) async {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await ensureAuthorized()
        await fetch()
        let elapsed = Date().timeIntervalSince1970 - lastSyncTS
        if lastSyncTS == 0 || elapsed >= minInterval {
            await saveAll()
        }
    }

    /// Requests read authorization once per launch (the system only shows the sheet the first time ever).
    private func ensureAuthorized() async {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        do { try await store.requestAuthorization(toShare: [], read: readTypes) }
        catch { errorMessage = "Couldn't access Apple Health. \(error.localizedDescription)" }
    }

    /// Re-reads the latest value for every metric (no save). Used by the detail sheet's refresh.
    func fetch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var out: [Reading] = []

        if let (v, d) = await todaySum(.stepCount, unit: .count()) {
            out.append(.init(metric: .steps, date: d, dedupID: Self.dayKey(.steps, d),
                             backendValue: "\(Int(v))", display: "\(Int(v)) steps"))
        }
        if let (v, d, uid) = await latestQuantity(.heartRate, unit: bpm) {
            out.append(.init(metric: .heartRate, date: d, dedupID: uid,
                             backendValue: "\(Int(v))", display: "\(Int(v)) bpm"))
            latestHeartRate = Int(v)
            latestHeartRateAt = d
        }
        if let (v, d, uid) = await latestQuantity(.restingHeartRate, unit: bpm) {
            out.append(.init(metric: .restingHeartRate, date: d, dedupID: uid,
                             backendValue: "\(Int(v))", display: "\(Int(v)) bpm"))
        }
        if let (v, d, uid) = await latestQuantity(.oxygenSaturation, unit: .percent()) {
            let pct = v * 100
            out.append(.init(metric: .bloodOxygen, date: d, dedupID: uid,
                             backendValue: String(format: "%.0f", pct), display: String(format: "%.0f%%", pct)))
        }
        if let (sys, d, uid) = await latestQuantity(.bloodPressureSystolic, unit: .millimeterOfMercury()),
           let (dia, _, _) = await latestQuantity(.bloodPressureDiastolic, unit: .millimeterOfMercury()) {
            out.append(.init(metric: .bloodPressure, date: d, dedupID: uid,
                             backendValue: "\(Int(sys))/\(Int(dia))", display: "\(Int(sys))/\(Int(dia)) mmHg"))
        }
        // Body temperature is manual/thermometer only; the Apple Watch records wrist temperature
        // overnight — fall back to that so the Temp card populates from the watch.
        var temp = await latestQuantity(.bodyTemperature, unit: .degreeCelsius())
        if temp == nil { temp = await latestQuantity(.appleSleepingWristTemperature, unit: .degreeCelsius()) }
        if let (v, d, uid) = temp {
            out.append(.init(metric: .temperature, date: d, dedupID: uid,
                             backendValue: String(format: "%.1f", v), display: String(format: "%.1f °C", v)))
        }
        if let (v, d, uid) = await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo)) {
            out.append(.init(metric: .weight, date: d, dedupID: uid,
                             backendValue: String(format: "%.1f", v), display: String(format: "%.1f kg", v)))
        }
        if let (v, d) = await todaySum(.activeEnergyBurned, unit: .kilocalorie()) {
            out.append(.init(metric: .activeEnergy, date: d, dedupID: Self.dayKey(.activeEnergy, d),
                             backendValue: "\(Int(v))", display: "\(Int(v)) kcal"))
        }
        if let (v, d) = await lastNightSleepHours() {
            out.append(.init(metric: .sleep, date: d, dedupID: Self.dayKey(.sleep, d),
                             backendValue: String(format: "%.1f", v), display: String(format: "%.1f hr", v)))
        }

        readings = out
        if !out.isEmpty { isConnected = true }   // reading data means access is granted
    }

    /// The latest reading for a given metric (nil if not present / not authorized).
    func reading(_ metric: Metric) -> Reading? { readings.first { $0.metric == metric } }

    // MARK: - Save

    private func saveAll() async {
        guard !readings.isEmpty else { return }
        // Core → data layer: reuse the existing measurement service (single app module).
        let service = HealthDataService()
        let iso = ISO8601DateFormatter()

        // Reconcile against the backend (the source of truth — no schema change). Fetch existing
        // Apple imports, DELETE duplicate rows (same metric + timestamp; aggregates keyed per-day),
        // and skip re-posting anything already present. This both cleans up historical duplicates
        // AND survives a lost local ledger (reinstall/logout) — the server decides what exists.
        var existingKeys = Set<String>()
        if let existing = try? await service.list(type: "measurement", limit: 200) {
            // Newest first (by createdAt) so we keep the freshest copy and delete older duplicates.
            let apple = existing.data
                .filter { $0.isFromAppleWatch }
                .sorted { ($0.createdAt ?? $0.dateTime ?? "") > ($1.createdAt ?? $1.dateTime ?? "") }
            for rec in apple {
                guard let key = Self.backendKey(title: rec.title, isoDate: rec.dateTime) else { continue }
                if existingKeys.insert(key).inserted == false {
                    try? await service.delete(rec.id)   // older duplicate → remove it
                }
            }
        }

        var synced = syncedKeys
        var ok = 0
        for r in readings {
            let key = Self.backendKey(title: r.metric.title, date: r.date)
            // Already on the server, or already posted this session → don't create another row.
            if existingKeys.contains(key) || synced.contains(r.dedupID) {
                synced.insert(r.dedupID)
                continue
            }
            let req = CreateMedicalDataRequest(
                type: "measurement", title: r.metric.title, value: r.backendValue,
                unit: r.metric.unit, description: MedicalDataRecord.appleWatchSourceTag,
                dateTime: iso.string(from: r.date)
            )
            if (try? await service.create(req)) != nil {
                ok += 1
                synced.insert(r.dedupID)
                existingKeys.insert(key)
            }
        }
        syncedKeys = synced

        lastSyncTS = Date().timeIntervalSince1970   // mark the attempt so the throttle advances even when all deduped
        isConnected = true
        if ok > 0 { Analytics.shared.track(.watchSynced, ["count": String(ok)]) }
    }

    /// Per-day dedup key for aggregate metrics (steps/energy/sleep) that have no single sample UUID.
    private static func dayKey(_ metric: Metric, _ date: Date) -> String {
        "\(metric.rawValue)|\(Int(date.timeIntervalSince1970))"
    }

    // Aggregate metrics have no single sample — historical rows were posted with a moving "now"
    // timestamp, so they must be de-duped per calendar day, not per second.
    private static let aggregateTitles: Set<String> = [
        Metric.steps.title, Metric.activeEnergy.title, Metric.sleep.title
    ]

    /// Backend dedup key: point metrics on the exact second (distinct readings in a day are NOT
    /// duplicates); aggregates on the calendar day.
    private static func backendKey(title: String, date: Date) -> String {
        if aggregateTitles.contains(title) {
            let day = Calendar.current.startOfDay(for: date)
            return "\(title)|day|\(Int(day.timeIntervalSince1970))"
        }
        return "\(title)|\(Int(date.timeIntervalSince1970))"
    }

    private static func backendKey(title: String, isoDate: String?) -> String? {
        guard let isoDate, let d = parseISO(isoDate) else { return nil }
        return backendKey(title: title, date: d)
    }

    /// Tolerant ISO 8601 parse — backend timestamps may or may not carry fractional seconds.
    private static func parseISO(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter(); withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    // MARK: - Queries

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> (Double, Date, String)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                // sample.uuid is HealthKit's stable per-sample identity — our dedup key.
                cont.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate, sample.uuid.uuidString))
            }
            store.execute(query)
        }
    }

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> (Double, Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                guard let sum = stats?.sumQuantity() else { cont.resume(returning: nil); return }
                // Use start-of-day (not now) so a day's total keeps one stable timestamp → dedups.
                cont.resume(returning: (sum.doubleValue(for: unit), start))
            }
            store.execute(query)
        }
    }

    private func lastNightSleepHours() async -> (Double, Date)? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let asleep = (samples as? [HKCategorySample])?.filter { asleepValues.contains($0.value) } ?? []
                let seconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                guard seconds > 0 else { cont.resume(returning: nil); return }
                // Stable per-day timestamp (start of today) so repeated syncs dedup to one row.
                let dayStart = Calendar.current.startOfDay(for: Date())
                cont.resume(returning: (seconds / 3600.0, dayStart))
            }
            store.execute(query)
        }
    }
}
