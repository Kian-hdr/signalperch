import XCTest
@testable import Signalperch

final class UptimeTests: XCTestCase {
    func testActualOpenAIOfficialHTML() throws {
        guard let path = ProcessInfo.processInfo.environment["SIGNALPERCH_UPTIME_HTML"] else {
            throw XCTSkip("Set SIGNALPERCH_UPTIME_HTML to an inspected official HTML capture for source acceptance.")
        }
        let html = try String(contentsOfFile: path, encoding: .utf8)
        let components = [Component(id: "01JMXBRMFE6N2NNT7DG6XZQ6PW", name: "Chat Completions", status: "operational"),
                          Component(id: "01JNKS9D9S72PMP1938PVFFQN4", name: "ChatGPT", status: "operational")]
        let result = try XCTUnwrap(UptimeClient.openAIComponents(in: html, components: components), "Actual official HTML parser returned nil")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.days.count, 60)
        XCTAssertEqual(result.first?.days.last?.health, .operational)
        XCTAssertEqual(result.first?.reportedPeriodDays, 90)
    }
    func testSourceDaysPreserveNoDataDowntimeAndReportedPercentage() throws {
        let json = #"""
        {"timelines":{"test":{"component":{"code":"test","name":"API","startDate":"2026-10-05"},"days":[
          {"date":"2026-10-04","outages":{},"related_events":[]},
          {"date":"2026-10-05","outages":{},"related_events":[]},
          {"date":"2026-10-06","outages":{"p":69},"related_events":[{"name":"Partial interruption","code":"event"}]},
          {"date":"2026-10-07","outages":{"m":2141,"p":61},"related_events":[]},
          {"date":"2026-10-08","related_events":[]},
          {"date":"2026-10-09","outages":{"unrecognized":22},"related_events":[]}
        ]}},"values":[{"component":"test","sixty":99.64,"ninety":99.46,"thirty":99.82}]}
        """#
        let decoded = try JSONDecoder().decode(UptimeShowcase.self, from: Data(json.utf8))
        let component = try XCTUnwrap(decoded.components(orderedIDs: ["test"]).first)
        XCTAssertEqual(component.name, "API")
        XCTAssertEqual(component.uptime60, "99.64")
        XCTAssertEqual(component.days.map(\.health), [nil, .operational, .degraded, .outage, nil, nil])
        XCTAssertEqual(component.days[2].downtimeDescription, "Partial outage: 1m 9s")
        XCTAssertEqual(component.days[2].incidentTitles, ["Partial interruption"])
        XCTAssertEqual(component.days[3].downtimeDescription, "Major outage: 35m 41s\nPartial outage: 1m 1s")
        XCTAssertEqual(component.days[0].dateString, "2026-10-04")
    }

    func testOnlyOfficialLoaderDeclarationEnablesEndpoint() {
        XCTAssertEqual(UptimeClient.advertisedEndpoint(in: #"var ENDPOINT = "/uptime_showcase";"#), "/uptime_showcase")
        XCTAssertNil(UptimeClient.advertisedEndpoint(in: #"<a href="/uptime_showcase">History</a>"#))
        XCTAssertNil(UptimeClient.advertisedEndpoint(in: #"var ENDPOINT = "https://untrusted.invalid/uptime_showcase";"#))
    }

    func testOpenAIEmbeddedJSONUsesActualIntervalsAndPreservesNinetyDayMetric() throws {
        let record = #"""
        {"initialNow":{"isoDate":"2026-10-10T17:43:53.820Z"},"summary":{"history_window_days":90},"data":{
          "component_impacts":[{"component_id":"test","start_at":"2026-10-09T23:30:00Z","end_at":"2026-10-10T00:10:00Z","status":"partial_outage","status_page_incident_id":"event"}],
          "component_uptimes":[{"component_id":"test","data_available_since":"2026-10-01T00:00:00Z","uptime":"99.995"}],
          "incident_links":[{"id":"event","name":"API interruption"}]}}
        """#
        let chunk = "1:" + record.replacingOccurrences(of: "\n", with: "") + "\n"
        let encoded = try JSONSerialization.data(withJSONObject: [1, chunk])
        let html = "<script>self.__next_f.push(" + String(decoding: encoded, as: UTF8.self) + ")</script>"
        let result = try XCTUnwrap(UptimeClient.openAIComponents(in: html, components: [Component(id: "test", name: "API", status: "operational")])?.first)
        XCTAssertEqual(result.days.count, 60)
        XCTAssertNil(result.uptime60)
        XCTAssertEqual(result.reportedUptime, "99.995")
        XCTAssertEqual(result.reportedPeriodDays, 90)
        XCTAssertNil(result.days.first?.health)
        XCTAssertEqual(result.days.suffix(2).map(\.health), [.outage, .outage])
        XCTAssertEqual(result.days.last?.downtimeDescription, "Partial Outage: 10m 0s")
        XCTAssertEqual(result.days.last?.incidentTitles, ["API interruption"])
    }
}
