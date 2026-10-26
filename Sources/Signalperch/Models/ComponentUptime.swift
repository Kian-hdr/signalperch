import Foundation

struct ComponentUptime: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let days: [UptimeDay]
    /// The provider's reported sixty-day percentage, never calculated from incidents.
    let uptime60: String?
    var reportedUptime: String? = nil
    var reportedPeriodDays: Int? = nil
    var componentID: String { id }
}

struct UptimeDay: Identifiable, Codable, Sendable {
    let date: Date
    let dateString: String
    let health: Health?
    let downtimeDescription: String
    let incidentTitles: [String]
    var id: String { dateString }
    var description: String { ([downtimeDescription] + incidentTitles).joined(separator: "\n") }
}

struct UptimeShowcase: Decodable, Sendable {
    struct Timeline: Decodable, Sendable {
        struct Metadata: Decodable, Sendable {
            let code: String
            let name: String
            let startDate: String?
            let isGroup: Bool?
        }
        struct Day: Decodable, Sendable {
            struct RelatedEvent: Decodable, Sendable { let name: String }
            let date: String
            let outages: [String: Double]?
            let related_events: [RelatedEvent]?
        }
        let component: Metadata
        let days: [Day]
    }
    struct Value: Decodable, Sendable {
        let component: String
        let sixty: Double?
    }
    let timelines: [String: Timeline]
    let values: [Value]

    func components(orderedIDs: [String]) -> [ComponentUptime] {
        orderedIDs.compactMap { id in
            guard let timeline = timelines[id], timeline.component.code == id else { return nil }
            let days = timeline.days.compactMap { day -> UptimeDay? in
                guard let date = Self.date(day.date) else { return nil }
                let beforeStart = timeline.component.startDate.flatMap(Self.date).map { date < $0 } ?? false
                let known = !beforeStart && timeline.component.isGroup != true && day.outages != nil
                    && day.outages!.allSatisfy { ["p", "m"].contains($0.key) && $0.value.isFinite && $0.value >= 0 }
                let partial = day.outages?["p"] ?? 0
                let major = day.outages?["m"] ?? 0
                let health: Health? = known ? (major > 0 ? .outage : partial > 0 ? .degraded : .operational) : nil
                var descriptions: [String] = []
                if !known { descriptions.append("No uptime data reported") }
                else {
                    if major > 0 { descriptions.append("Major outage: \(Self.duration(major))") }
                    if partial > 0 { descriptions.append("Partial outage: \(Self.duration(partial))") }
                    if descriptions.isEmpty { descriptions.append("No downtime reported") }
                }
                return UptimeDay(date: date, dateString: day.date, health: health,
                                 downtimeDescription: descriptions.joined(separator: "\n"),
                                 incidentTitles: day.related_events?.map(\.name) ?? [])
            }.sorted { $0.date < $1.date }
            let percentage = values.first { $0.component == id }?.sixty
            let uptime = percentage.flatMap { value -> String? in
                guard value.isFinite, (0...100).contains(value) else { return nil }
                return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
            }
            var result = ComponentUptime(id: id, name: timeline.component.name, days: Array(days.suffix(60)), uptime60: uptime)
            result.reportedUptime = uptime
            result.reportedPeriodDays = uptime == nil ? nil : 60
            return result
        }
    }
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    static func duration(_ seconds: Double) -> String {
        // Preserve seconds instead of rounding short provider outages to zero minutes.
        let total = Int(min(seconds, Double(Int.max / 2)))
        let hours = total / 3600, minutes = (total % 3600) / 60, remainder = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(total)s"
    }
}

/// OpenAI's official incident.io chart data embedded in its server-rendered page.
/// The reported percentage belongs to its full history window, not our sixty bars.
struct OpenAIUptimeData: Decodable {
    struct Impact: Decodable {
        let component_id: String
        let start_at: String
        let end_at: String?
        let status: String
        let status_page_incident_id: String
    }
    struct Metric: Decodable {
        let component_id: String
        let data_available_since: String?
        let uptime: String
    }
    struct RelatedIncident: Decodable { let id: String; let name: String }
    let component_impacts: [Impact]
    let component_uptimes: [Metric]
    let incident_links: [RelatedIncident]

    func components(_ components: [Component], sourceNow: Date, periodDays: Int) -> [ComponentUptime] {
        guard periodDays >= 60 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: sourceNow)
        return components.compactMap { component in
            guard let metric = component_uptimes.first(where: { $0.component_id == component.id }),
                  let availableSince = StatusDate.parse(metric.data_available_since) else { return nil }
            let impacts = component_impacts.filter { $0.component_id == component.id }
            let days = (-59...0).compactMap { offset -> UptimeDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                      let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
                let end = min(next, sourceNow)
                let available = end > availableSince
                var health: Health? = available ? .operational : nil
                var descriptions: [String] = []
                var names: [String] = []
                for impact in impacts {
                    guard let start = StatusDate.parse(impact.start_at), start < end else { continue }
                    let finish: Date
                    if impact.end_at == nil || impact.end_at == "$undefined" { finish = sourceNow }
                    else if let parsed = StatusDate.parse(impact.end_at) { finish = parsed }
                    else { health = nil; continue }
                    guard finish > date else { continue }
                    let severity: Health?
                    switch impact.status {
                    case "operational": severity = .operational
                    case "degraded_performance": severity = .degraded
                    case "partial_outage", "major_outage", "full_outage": severity = .outage
                    case "under_maintenance": severity = .maintenance
                    default: severity = nil
                    }
                    if let severity, let current = health { health = max(current, severity) }
                    else { health = nil }
                    let seconds = max(0, min(finish, end).timeIntervalSince(max(start, date)))
                    descriptions.append("\(impact.status.replacingOccurrences(of: "_", with: " ").capitalized): \(UptimeShowcase.duration(seconds))")
                    if let name = incident_links.first(where: { $0.id == impact.status_page_incident_id })?.name, !names.contains(name) { names.append(name) }
                }
                if !available { descriptions = ["No uptime data reported"] }
                else if descriptions.isEmpty { descriptions = ["No downtime reported"] }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                return UptimeDay(date: date, dateString: formatter.string(from: date), health: health,
                                 downtimeDescription: descriptions.joined(separator: "\n"), incidentTitles: names)
            }
            var result = ComponentUptime(id: component.id, name: component.name, days: days, uptime60: nil)
            if let value = Double(metric.uptime), value.isFinite, (0...100).contains(value) {
                result.reportedUptime = metric.uptime
                result.reportedPeriodDays = periodDays
            }
            return result
        }
    }
}
