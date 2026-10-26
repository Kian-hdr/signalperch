import Foundation

// Shared transport for summary polling and optional, on-demand detail loading.
// Detail requests never mutate monitoring state or notification baselines.
enum StatusFeed {
    static func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Signalperch/0.2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.http(0) }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        return data
    }
}

struct IncidentClient: Sendable {
    private struct History: Decodable, Sendable { let incidents: [Incident] }
    private struct Maintenance: Decodable, Sendable { let scheduled_maintenances: [Incident] }
    private struct OptionalFeed<Value: Sendable>: Sendable {
        let value: Value?
        let failure: String?
    }
    private func optional<Value: Decodable & Sendable>(_ type: Value.Type, url: URL) async -> OptionalFeed<Value> {
        do {
            let data = try await StatusFeed.data(from: url)
            return OptionalFeed(value: try JSONDecoder().decode(type, from: data), failure: nil)
        } catch {
            return OptionalFeed(value: nil, failure: error.localizedDescription)
        }
    }
    func fetch(_ provider: Provider) async throws -> ServiceDetails {
        async let summaryData = StatusFeed.data(from: provider.feedURL)
        async let historyResult = optional(History.self, url: provider.pageURL.appendingPathComponent("api/v2/incidents.json"))
        // OpenAI's incident.io compatibility API returns 404 for maintenance.
        async let maintenanceResult: OptionalFeed<Maintenance> = provider.id == "openai"
            ? OptionalFeed(value: nil, failure: nil)
            : optional(Maintenance.self, url: provider.pageURL.appendingPathComponent("api/v2/scheduled-maintenances.json"))
        let summary = try JSONDecoder().decode(StatusSummary.self, from: await summaryData)
        let snapshot = try Snapshot(summary: summary)
        let history = await historyResult
        let maintenance = await maintenanceResult
        let incidents = Self.merging(history.value?.incidents ?? [], with: summary.incidents)
        let maintenances = Self.merging(maintenance.value?.scheduled_maintenances ?? [], with: summary.scheduled_maintenances ?? [])
        var limitations: [String] = []
        if let failure = history.failure { limitations.append("Recent incident history could not be loaded: \(failure)") }
        if let failure = maintenance.failure { limitations.append("Maintenance history could not be loaded: \(failure)") }
        return ServiceDetails(snapshot: snapshot, incidents: incidents, scheduledMaintenances: maintenances, fetchedAt: Date(), limitations: limitations)
    }
    static func mergeIncident(_ history: Incident, with current: Incident) -> Incident {
        let currentDate = StatusDate.parse(current.updated_at) ?? current.timestamp ?? .distantPast
        let historyDate = StatusDate.parse(history.updated_at) ?? history.timestamp ?? .distantPast
        var result = currentDate >= historyDate ? current : history
        var updates: [String: Incident.Update] = [:]
        for update in (history.incident_updates ?? []) + (current.incident_updates ?? []) {
            let key = update.id ?? [update.created_at ?? "", update.display_at ?? "", update.status ?? "", update.body].joined(separator: "|")
            if let existing = updates[key], (StatusDate.parse(existing.updated_at) ?? existing.timestamp ?? .distantPast) > (StatusDate.parse(update.updated_at) ?? update.timestamp ?? .distantPast) { continue }
            updates[key] = update
        }
        result = result.withUpdates(Array(updates.values).sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) })
        return result
    }
    private static func merging(_ history: [Incident], with current: [Incident]) -> [Incident] {
        var combined = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        for incident in current {
            combined[incident.id] = combined[incident.id].map { mergeIncident($0, with: incident) } ?? incident
        }
        return combined.values.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }
}

typealias DetailClient = IncidentClient
