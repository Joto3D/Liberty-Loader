import XCTest
@testable import LibertyCore

final class MemoryWatchTests: XCTestCase {
    let gb: UInt64 = 1_073_741_824

    func testLevels() {
        XCTAssertEqual(MemoryLevel(footprint: 14 * gb, physical: 16 * gb), .normal)
        XCTAssertEqual(MemoryLevel(footprint: 24 * gb, physical: 16 * gb), .high)
        XCTAssertEqual(MemoryLevel(footprint: 43 * gb, physical: 16 * gb), .critical)
        XCTAssertEqual(MemoryLevel(footprint: 43 * gb, physical: 32 * gb), .normal)
    }

    func testAlertsOncePerLevel() {
        var state = MemoryAlertState()
        XCTAssertNil(state.next(.normal))
        XCTAssertEqual(state.next(.high), .high)
        XCTAssertNil(state.next(.high))
        XCTAssertEqual(state.next(.critical), .critical)
        XCTAssertNil(state.next(.high))
        XCTAssertNil(state.next(.critical))
        state.reset()
        XCTAssertEqual(state.next(.critical), .critical)
    }

    func testFormat() {
        XCTAssertTrue(GameMemory.format(43 * gb).hasSuffix(" GB"))
    }
}
