import XCTest
@testable import Signalperch

final class DetailTests: XCTestCase {
    func testFullTimelineDatesComponentsAndMaintenanceDecode() throws {
        let json = #"""
        {"id":"01UUID-STYLE","name":"API outage","status":"resolved","impact":"major","created_at":"2026-10-01T18:46:17Z","resolved_at":"2026-10-01T19:39:30Z","scheduled_for":"2026-10-03T01:00:00.000Z","scheduled_until":"2026-10-03T02:00:00.000Z","components":[{"id":"api","name":"API","status":"operational"}],"incident_updates":[{"id":"u2","status":"resolved","body":"Recovered","display_at":"2026-10-01T19:39:30.123Z","affected_components":[{"code":"api","name":"API","old_status":"partial_outage","new_status":"operational"}]},{"id":"u1","body":"Investigating","created_at":"2026-10-01T18:46:17Z"}]}
        """#
        let incident = try JSONDecoder().decode(Incident.self, from: Data(json.utf8))
        XCTAssertEqual(incident.incident_updates?.count, 2)
        XCTAssertNotNil(incident.incident_updates?[0].timestamp)
        XCTAssertNotNil(incident.incident_updates?[1].timestamp)
        XCTAssertNil(incident.incident_updates?[1].status)
        XCTAssertEqual(incident.affectedComponentNames, ["API"])
        XCTAssertNotNil(StatusDate.parse(incident.scheduled_until))
        XCTAssertFalse(incident.active)
    }
    func testMissingOptionalTimelineFieldsRemainCompatible() throws {
        let json = #"{"id":"a","name":"API","status":"investigating","incident_updates":[{"body":"Checking"}]}"#
        let incident = try JSONDecoder().decode(Incident.self, from: Data(json.utf8))
        XCTAssertNil(incident.incident_updates?.first?.timestamp)
        XCTAssertNil(incident.shortlink)
        XCTAssertTrue(incident.active)
        let restored = try JSONDecoder().decode(Incident.self, from: JSONEncoder().encode(incident))
        XCTAssertEqual(restored, incident)
    }
    func testOfficialIncidentLinkRejectsUnexpectedHostAndScheme() {
        let provider = Provider.all[0]
        let unsafe = Incident(id: "a", name: "API", status: "resolved", impact: nil, shortlink: "https://example.com/incidents/a", incident_updates: nil)
        XCTAssertEqual(unsafe.officialURL(for: provider), provider.pageURL)
        let official = Incident(id: "a", name: "API", status: "resolved", impact: nil, shortlink: "https://stspg.io/abcd", incident_updates: nil)
        XCTAssertEqual(official.officialURL(for: provider).host, "stspg.io")
    }
    func testUpcomingMaintenanceDoesNotTriggerOutageButInProgressIsMaintenance() throws {
        func decode(_ status: String) throws -> StatusSummary {
            let json = """
            {"status":{"indicator":"none","description":"OK"},"components":[],"incidents":[],"scheduled_maintenances":[{"id":"m","name":"Network maintenance","status":"\(status)","impact":"maintenance"}]}
            """
            return try JSONDecoder().decode(StatusSummary.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("scheduled").health(), .operational)
        XCTAssertEqual(try decode("in_progress").health(), .maintenance)
        XCTAssertTrue(try Snapshot(summary: decode("scheduled")).incidents.isEmpty)
    }
    func testNewerSummaryPreservesWholeTimeline() throws {
        let oldJSON = #"{"id":"issue","name":"API","status":"investigating","updated_at":"2026-10-01T10:00:00Z","incident_updates":[{"id":"u1","body":"Investigating","created_at":"2026-10-01T10:00:00Z"}]}"#
        let newJSON = #"{"id":"issue","name":"API","status":"resolved","updated_at":"2026-10-01T11:00:00Z","incident_updates":[{"id":"u2","body":"Recovered","created_at":"2026-10-01T11:00:00Z"}]}"#
        let decoder = JSONDecoder()
        let old = try decoder.decode(Incident.self, from: Data(oldJSON.utf8))
        let new = try decoder.decode(Incident.self, from: Data(newJSON.utf8))
        let merged = IncidentClient.mergeIncident(old, with: new)
        XCTAssertEqual(merged.status, "resolved")
        XCTAssertEqual(merged.incident_updates?.map(\.id), ["u2", "u1"])
        XCTAssertEqual(IncidentClient.mergeIncident(merged, with: new).incident_updates?.count, 2)
    }
    func testLiveDetailFeedsRetainHistoryAndUpdates() async throws {
        for provider in Provider.all {
            let details = try await IncidentClient().fetch(provider)
            XCTAssertFalse(details.incidents.isEmpty, provider.name)
            XCTAssertTrue(details.limitations.isEmpty, "\(provider.name): \(details.limitations)")
            XCTAssertTrue(details.incidents.contains { !($0.incident_updates ?? []).isEmpty }, provider.name)
        }
    }

}
