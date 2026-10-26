import Foundation

/// Reopening a card can show imported history immediately while refreshing it.
/// This cache contains historical public provider data, never current live health.
enum UptimeHistoryCache {
    private struct Entry: Codable {
        let savedAt: Date
        let components: [ComponentUptime]
    }
    static func load(_ provider: Provider, defaults: UserDefaults = .standard) -> [ComponentUptime] {
        guard let data = defaults.data(forKey: key(provider)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date().timeIntervalSince(entry.savedAt) < 6 * 3600 else { return [] }
        return entry.components
    }
    static func save(_ components: [ComponentUptime], for provider: Provider, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Entry(savedAt: Date(), components: components)) else { return }
        defaults.set(data, forKey: key(provider))
    }
    private static func key(_ provider: Provider) -> String { "uptimeHistory-" + provider.id }
}
