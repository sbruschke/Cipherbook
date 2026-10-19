import XCTest
@testable import JournalCore

final class WrapGeometryTests: XCTestCase {
    private let ex = PageRect(minX: 100, minY: 50, maxX: 160, maxY: 120)

    func testNoExclusionIsFullWidth() {
        XCTAssertEqual(WrapGeometry.segments(top: 0, bottom: 20, width: 200, exclusion: nil, minSegment: 10), [0...200])
    }
    func testRowsAboveAndBelowAreFullWidth() {
        XCTAssertEqual(WrapGeometry.segments(top: 0, bottom: 49, width: 200, exclusion: ex, minSegment: 10), [0...200])
        XCTAssertEqual(WrapGeometry.segments(top: 120, bottom: 140, width: 200, exclusion: ex, minSegment: 10), [0...200])
    }
    func testOverlappingRowSplitsIntoTwoSegments() {
        XCTAssertEqual(WrapGeometry.segments(top: 60, bottom: 80, width: 200, exclusion: ex, minSegment: 10), [0...100, 160...200])
    }
    func testPartialVerticalOverlapStillSplits() {
        XCTAssertEqual(WrapGeometry.segments(top: 110, bottom: 130, width: 200, exclusion: ex, minSegment: 10).count, 2)
    }
    func testNarrowSliversAreDropped() {
        let e = PageRect(minX: 5, minY: 0, maxX: 190, maxY: 50)
        XCTAssertEqual(WrapGeometry.segments(top: 0, bottom: 10, width: 200, exclusion: e, minSegment: 12), [])
        let e2 = PageRect(minX: 5, minY: 0, maxX: 150, maxY: 50)
        XCTAssertEqual(WrapGeometry.segments(top: 0, bottom: 10, width: 200, exclusion: e2, minSegment: 12), [150...200])
    }
    func testExclusionOutsideTheBoxIsClamped() {
        let e = PageRect(minX: -50, minY: 0, maxX: 80, maxY: 50)
        XCTAssertEqual(WrapGeometry.segments(top: 0, bottom: 10, width: 200, exclusion: e, minSegment: 10), [80...200])
    }
}
