import XCTest
@testable import Signalperch

final class StatusTests: XCTestCase {
    private func summary(indicator: String = "none", incidents: String = "[]", component: String = "operational") throws -> StatusSummary {
        let json = """
        {"status":{"indicator":"\(indicator)","description":"Reported status"},"components":[{"id":"a","name":"API","status":"\(component)"}],"incidents":\(incidents)}
        """
        return try JSONDecoder().decode(StatusSummary.self, from: Data(json.utf8))
    }
    private func incident(_ id: String, status: String = "monitoring") -> Incident {
        Incident(id: id, name: "API errors", status: status, impact: "minor", shortlink: nil, incident_updates: nil)
    }
    func testMissingIncidentArrayPreservesReportedAndComponentHealth() throws {
        // OpenAI summary currently omits incidents and scheduled_maintenances
        // altogether in the observed operational response.
        let clearJSON = #"{"status":{"indicator":"none","description":"All Systems Operational"},"components":[{"id":"responses","name":"Responses","status":"operational"}]}"#
        let clear = try JSONDecoder().decode(StatusSummary.self, from: Data(clearJSON.utf8))
        XCTAssertTrue(clear.incidents.isEmpty)
        XCTAssertNil(clear.scheduled_maintenances)
        XCTAssertEqual(try Snapshot(summary: clear).health, .operational)
        let outageJSON = #"{"status":{"indicator":"major","description":"Outage"},"components":[],"incidents":null}"#
        let outage = try JSONDecoder().decode(StatusSummary.self, from: Data(outageJSON.utf8))
        XCTAssertEqual(try Snapshot(summary: outage).health, .outage)
        let componentJSON = #"{"status":{"indicator":"none","description":"OK"},"components":[{"id":"api","name":"API","status":"partial_outage"}]}"#
        let component = try JSONDecoder().decode(StatusSummary.self, from: Data(componentJSON.utf8))
        XCTAssertEqual(try Snapshot(summary: component).health, .outage)
    }
    func testInvalidSummaryDoesNotDecodeAsHealthy() throws {
        for json in [
            #"{"components":[]}"#,
            #"{"status":{"description":"OK"},"components":[]}"#,
            #"{"status":{"indicator":"none","description":"OK"}}"#,
            #"{"status":{"indicator":"none","description":"OK"},"components":[],"incidents":{}}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(StatusSummary.self, from: Data(json.utf8)))
        }
        let unknownJSON = #"{"status":{"indicator":"unexpected","description":"OK"},"components":[]}"#
        let unknown = try JSONDecoder().decode(StatusSummary.self, from: Data(unknownJSON.utf8))
        XCTAssertThrowsError(try Snapshot(summary: unknown))
    }
    func testOpenAIIncidentWithOperationalComponents() throws {
        let s = try summary(indicator: "minor", incidents: "[{\"id\":\"1\",\"name\":\"Space errors\",\"status\":\"monitoring\",\"impact\":\"minor\"}]")
        XCTAssertEqual(try s.health(), .degraded)
        XCTAssertEqual(try Snapshot(summary: s).incidents.count, 1)
    }
    func testUnresolvedIncidentWinsOverGreenIndicator() throws {
        let s = try summary(incidents: "[{\"id\":\"1\",\"name\":\"Errors\",\"status\":\"investigating\",\"impact\":\"major\"}]")
        XCTAssertEqual(try s.health(), .outage)
    }
    func testInformationalIncidentStaysGreen() throws {
        let s = try summary(incidents: "[{\"id\":\"1\",\"name\":\"Information\",\"status\":\"monitoring\",\"impact\":\"none\"}]")
        XCTAssertEqual(try s.health(), .operational)
    }
    func testFiveMinutePollAllowsItsInterval() {
        let now = Date()
        let snapshot = Snapshot(health: .operational, description: "OK", checkedAt: now.addingTimeInterval(-240))
        XCTAssertFalse(ServiceReading(snapshot: snapshot).unavailable(at: now, maxAge: 345))
        XCTAssertTrue(ServiceReading(snapshot: snapshot).unavailable(at: now.addingTimeInterval(106), maxAge: 345))
    }
    func testResolvedIncidentDoesNotImplyOutage() throws {
        let s = try summary(incidents: "[{\"id\":\"1\",\"name\":\"Old issue\",\"status\":\"resolved\",\"impact\":\"major\"}]")
        XCTAssertEqual(try s.health(), .operational)
        XCTAssertTrue(s.activeIncidents.isEmpty)
    }
    func testComponentOutageAndMaintenance() throws {
        XCTAssertEqual(try summary(component: "partial_outage").health(), .outage)
        XCTAssertEqual(try summary(component: "under_maintenance").health(), .maintenance)
    }
    func testUnknownIndicatorFailsInsteadOfGreen() throws {
        XCTAssertThrowsError(try summary(indicator: "surprise").health())
    }
    func testInitialOutageAndNoDuplicateOnRestart() throws {
        let current = Snapshot(health: .degraded, description: "Issue", incidents: [incident("1")])
        XCTAssertNotNil(AlertPolicy.alert(provider: "OpenAI", previous: nil, current: current, recoveries: true))
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(current))
        XCTAssertNil(AlertPolicy.alert(provider: "OpenAI", previous: restored, current: current, recoveries: true))
    }
    func testNewIncidentAtSameSeverityAndEscalation() {
        let previous = Snapshot(health: .degraded, description: "Issue", incidents: [incident("1")])
        let new = Snapshot(health: .degraded, description: "Issue", incidents: [incident("1"), incident("2")])
        XCTAssertNotNil(AlertPolicy.alert(provider: "Claude", previous: previous, current: new, recoveries: true))
        let escalated = Snapshot(health: .outage, description: "Outage", incidents: previous.incidents)
        XCTAssertNotNil(AlertPolicy.alert(provider: "Claude", previous: previous, current: escalated, recoveries: true))
    }
    func testRecoveryAndRecoveryPreference() {
        let issue = Snapshot(health: .outage, description: "Outage")
        let clear = Snapshot(health: .operational, description: "All clear")
        XCTAssertNotNil(AlertPolicy.alert(provider: "Claude", previous: issue, current: clear, recoveries: true))
        XCTAssertNil(AlertPolicy.alert(provider: "Claude", previous: issue, current: clear, recoveries: false))
        XCTAssertNil(AlertPolicy.alert(provider: "Claude", previous: nil, current: clear, recoveries: true))
    }
    func testFailedAndStaleChecksAreUnavailable() {
        let now = Date()
        let good = Snapshot(health: .operational, description: "OK", checkedAt: now)
        XCTAssertFalse(ServiceReading(snapshot: good).unavailable(at: now))
        XCTAssertTrue(ServiceReading(snapshot: good, error: "Offline").unavailable(at: now))
        XCTAssertTrue(ServiceReading(snapshot: good).unavailable(at: now.addingTimeInterval(181)))
        XCTAssertTrue(ServiceReading().unavailable(at: now))
    }
    func testLiveProviderDecoding() async throws {
        for provider in Provider.all {
            let snapshot = try await StatusClient().fetch(provider)
            XCTAssertLessThan(abs(snapshot.checkedAt.timeIntervalSinceNow), 30, provider.name)
        }
    }
}
