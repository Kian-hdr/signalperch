import Foundation

enum Health: Int, Codable, Comparable, Sendable {
    case operational = 0, maintenance = 1, degraded = 2, outage = 3
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var title: String {
        switch self { case .operational: "Operational"; case .maintenance: "Maintenance"; case .degraded: "Issues"; case .outage: "Outage" }
    }
}
struct Provider: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let host: String
    let symbol: String
    var pageURL: URL { URL(string: "https://\(host)")! }
    var feedURL: URL { pageURL.appendingPathComponent("api/v2/summary.json") }
    static let all: [Provider] = [
        .init(id: "openai", name: "OpenAI", host: "status.openai.com", symbol: "sparkles"),
        .init(id: "claude", name: "Claude", host: "status.claude.com", symbol: "asterisk"),
        .init(id: "github", name: "GitHub", host: "www.githubstatus.com", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "cloudflare", name: "Cloudflare", host: "www.cloudflarestatus.com", symbol: "cloud"),
        .init(id: "supabase", name: "Supabase", host: "status.supabase.com", symbol: "bolt"),
        .init(id: "vercel", name: "Vercel", host: "www.vercel-status.com", symbol: "triangle"),
        .init(id: "stripe", name: "Stripe", host: "www.stripestatus.com", symbol: "creditcard")
    ]
}
// Timestamps stay as optional source strings so older cached snapshots and providers
// with omitted timestamps continue to decode. Parse only when displaying dates.
enum StatusDate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
struct Incident: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let status: String
    let impact: String?
    let shortlink: String?
    var incident_updates: [Update]?
    var created_at: String? = nil
    var updated_at: String? = nil
    var started_at: String? = nil
    var resolved_at: String? = nil
    var postmortem_body: String? = nil
    var postmortem_body_last_updated_at: String? = nil
    var postmortem_published_at: String? = nil
    var scheduled_for: String? = nil
    var scheduled_until: String? = nil
    var components: [Component]? = nil
    struct Update: Codable, Equatable, Sendable {
        let body: String
        let status: String?
        var id: String? = nil
        var created_at: String? = nil
        var updated_at: String? = nil
        var display_at: String? = nil
        var affected_components: [AffectedComponent]? = nil
        var timestamp: Date? { StatusDate.parse(display_at) ?? StatusDate.parse(created_at) ?? StatusDate.parse(updated_at) }
    }
    struct AffectedComponent: Codable, Equatable, Sendable {
        var code: String? = nil
        var name: String? = nil
        var old_status: String? = nil
        var new_status: String? = nil
    }
    func withUpdates(_ updates: [Update]) -> Incident {
        var copy = self
        copy.incident_updates = updates
        return copy
    }
    var active: Bool { !["resolved", "postmortem", "completed", "scheduled"].contains(status.lowercased()) }
    var detail: String { incident_updates?.first?.body ?? status.capitalized }
    var timestamp: Date? { StatusDate.parse(started_at) ?? StatusDate.parse(created_at) }
    var affectedComponentNames: [String] {
        let names = (components?.map(\.name) ?? []) + (incident_updates ?? []).flatMap { $0.affected_components?.compactMap(\.name) ?? [] }
        return Array(Set(names)).sorted()
    }
    func officialURL(for provider: Provider) -> URL {
        // Follow only the provider's returned official URL or Statuspage shortlink.
        // OpenAI omits shortlink; its status homepage remains a safe fallback.
        guard let shortlink, let url = URL(string: shortlink), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == provider.host.lowercased() || host == "stspg.io" || host == "stspg.co"
        else {
            if provider.id == "openai" && shortlink == nil {
                return provider.pageURL.appendingPathComponent("incidents").appendingPathComponent(id)
            }
            return provider.pageURL
        }
        return url
    }
}
struct Component: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let status: String
    var description: String? = nil
    var group_id: String? = nil
    var group: Bool? = nil
    var position: Int? = nil
    var updated_at: String? = nil
}
struct ServiceDetails: Equatable, Sendable {
    let snapshot: Snapshot
    let incidents: [Incident]
    let scheduledMaintenances: [Incident]
    let fetchedAt: Date
    let limitations: [String]
    var components: [Component] { snapshot.components }
}
struct StatusSummary: Decodable, Sendable {
    struct Status: Decodable, Sendable { let indicator: String; let description: String }
    let status: Status
    let components: [Component]
    let incidents: [Incident]
    var scheduled_maintenances: [Incident]? = nil
    private enum CodingKeys: String, CodingKey { case status, components, incidents, scheduled_maintenances }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Status and components remain required. An invalid response must fail
        // rather than fabricate an operational observation.
        status = try values.decode(Status.self, forKey: .status)
        components = try values.decode([Component].self, forKey: .components)
        // OpenAI's operational compatibility summary can omit this collection.
        incidents = try values.decodeIfPresent([Incident].self, forKey: .incidents) ?? []
        scheduled_maintenances = try values.decodeIfPresent([Incident].self, forKey: .scheduled_maintenances)
    }
    var activeIncidents: [Incident] { incidents.filter(\.active) }
    func health() throws -> Health {
        let overall: Health
        switch status.indicator {
        case "none": overall = .operational
        case "maintenance": overall = .maintenance
        case "minor": overall = .degraded
        case "major", "critical": overall = .outage
        default: throw FeedError.unsupportedStatus
        }
        let componentHealth = components.map { component -> Health in
            switch component.status {
            case "major_outage", "partial_outage": .outage
            case "degraded_performance": .degraded
            case "under_maintenance": .maintenance
            default: .operational
            }
        }.max() ?? .operational
        let incidentHealth = activeIncidents.map { incident -> Health in
            switch incident.impact {
            case "critical", "major": .outage
            case "maintenance": .maintenance
            case "none": .operational
            default: .degraded
            }
        }.max() ?? .operational
        let maintenanceHealth: Health = scheduled_maintenances?.contains { ["in_progress", "verifying"].contains($0.status) } == true ? .maintenance : .operational
        return max(overall, componentHealth, incidentHealth, maintenanceHealth)
    }
}
struct Snapshot: Codable, Equatable, Sendable {
    let health: Health
    let description: String
    let incidents: [Incident]
    let components: [Component]
    let checkedAt: Date
    init(summary: StatusSummary, date: Date = Date()) throws {
        health = try summary.health(); description = summary.status.description
        incidents = summary.activeIncidents; components = summary.components; checkedAt = date
    }
    init(health: Health, description: String, incidents: [Incident] = [], components: [Component] = [], checkedAt: Date = Date()) {
        self.health = health; self.description = description; self.incidents = incidents; self.components = components; self.checkedAt = checkedAt
    }
}
struct ServiceReading: Equatable {
    var snapshot: Snapshot?
    var error: String?
    func unavailable(at now: Date, maxAge: TimeInterval = 180) -> Bool { error != nil || snapshot == nil || now.timeIntervalSince(snapshot!.checkedAt) > maxAge }
}
enum FeedError: LocalizedError {
    case http(Int), unsupportedStatus
    var errorDescription: String? {
        switch self { case .http(let code): "Status server returned HTTP \(code)."; case .unsupportedStatus: "The status feed uses an unrecognized status." }
    }
}
