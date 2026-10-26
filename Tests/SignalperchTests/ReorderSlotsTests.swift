import XCTest
@testable import Signalperch
final class ReorderSlotsTests: XCTestCase {
    func testNeighborsOpenGapWhileDraggingDown() {
        XCTAssertEqual((0..<6).map { ReorderSlots.slot(for: $0, origin: 1, destination: 4, dragging: true) }, [0, 1, 1, 2, 3, 5])
    }
    func testNeighborsOpenGapWhileDraggingUp() {
        XCTAssertEqual((0..<6).map { ReorderSlots.slot(for: $0, origin: 4, destination: 1, dragging: true) }, [0, 2, 3, 4, 4, 5])
    }
    func testDestinationTracksPointerAndClampsAtEdges() {
        XCTAssertEqual(ReorderSlots.destination(origin: 2, translation: 29, pitch: 60, count: 6), 2)
        XCTAssertEqual(ReorderSlots.destination(origin: 2, translation: 31, pitch: 60, count: 6), 3)
        XCTAssertEqual(ReorderSlots.destination(origin: 2, translation: -1000, pitch: 60, count: 6), 0)
        XCTAssertEqual(ReorderSlots.destination(origin: 2, translation: 1000, pitch: 60, count: 6), 5)
        XCTAssertEqual(ReorderSlots.slot(for: 3, origin: 1, destination: 4, dragging: false), 3)
    }
}
