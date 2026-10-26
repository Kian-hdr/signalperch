import Foundation
struct StatusClient: Sendable {
    func fetch(_ provider: Provider) async throws -> Snapshot {
        let data = try await StatusFeed.data(from: provider.feedURL)
        return try Snapshot(summary: JSONDecoder().decode(StatusSummary.self, from: data))
    }
}
struct StatusAlert: Equatable {
    let title: String
    let body: String
}
enum AlertPolicy {
    static func alert(provider: String, previous: Snapshot?, current: Snapshot, recoveries: Bool) -> StatusAlert? {
        if current.health == .operational {
            guard let previous, previous.health > .operational, recoveries else { return nil }
            return StatusAlert(title: "\(provider) recovered", body: current.description)
        }
        let newIDs = Set(current.incidents.filter { $0.impact != "none" }.map(\.id)).subtracting(previous?.incidents.map(\.id) ?? [])
        guard previous == nil || current.health > previous!.health || !newIDs.isEmpty else { return nil }
        let incident = current.incidents.first { newIDs.contains($0.id) }
        return StatusAlert(title: "\(provider): \(current.health.title)", body: incident?.name ?? current.description)
    }
}
