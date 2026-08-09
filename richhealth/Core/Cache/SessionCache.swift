import Foundation

/// Lightweight UserDefaults TTL cache for session data that is expensive to re-fetch.
/// This is NOT a database — it has no schema, no migrations, and no relational integrity.
/// It is the iOS equivalent of SharedPreferences with expiry timestamps.
///
/// Rules (CLAUDE.md §16):
///   - Cache only API responses that don't change more than once per hour/day.
///   - Cacheable: briefing (same-day), digest (same-day), dietary insights (8 h), AQI (1 h).
///   - Not cacheable: health records, chat, feed, workouts, doctors — always fetch fresh.
///   - Call clearAll() on logout to prevent stale data leaking between accounts.
struct SessionCache {

    // MARK: - Write

    /// Persist a Codable value alongside its save timestamp.
    static func save<T: Codable>(_ value: T, key: String) {
        let envelope = Envelope(value: value, savedAt: Date())
        if let data = try? JSONEncoder().encode(envelope) {
            UserDefaults.standard.set(data, forKey: cacheKey(key))
        }
    }

    // MARK: - Read (time-to-live)

    /// Return the cached value if it exists and was saved within `maxAge` seconds.
    /// Returns nil if missing, corrupt, or expired — caller falls through to a network fetch.
    static func load<T: Codable>(_ type: T.Type, key: String, maxAge: TimeInterval) -> T? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey(key)),
            let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data),
            Date().timeIntervalSince(envelope.savedAt) < maxAge
        else { return nil }
        return envelope.value
    }

    // MARK: - Read (calendar-day boundary)

    /// Return the cached value only if it was saved on today's calendar date.
    /// Invalidates at midnight regardless of when the entry was written (same-day semantics).
    static func loadToday<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey(key)),
            let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data),
            Calendar.current.isDateInToday(envelope.savedAt)
        else { return nil }
        return envelope.value
    }

    // MARK: - Invalidation

    /// Remove a single cache entry.
    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(key))
    }

    /// Remove every entry under the "rh.cache." namespace.
    /// Call on logout so stale data never leaks to the next account session.
    static func clearAll() {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("rh.cache.") }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - Private

    private static func cacheKey(_ key: String) -> String { "rh.cache.\(key)" }

    private struct Envelope<T: Codable>: Codable {
        let value: T
        let savedAt: Date
    }
}
