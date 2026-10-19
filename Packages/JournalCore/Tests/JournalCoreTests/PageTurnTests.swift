import XCTest
@testable import JournalCore

final class PageTurnTests: XCTestCase {
    func testShortDragDoesNotTurn() {
        XCTAssertNil(PageTurn.direction(dx: 30, dy: 2, predictedDx: 40))
        XCTAssertNil(PageTurn.direction(dx: -30, dy: 2, predictedDx: -40))
    }

    func testLongDragTurnsInItsDirection() {
        XCTAssertEqual(PageTurn.direction(dx: 120, dy: 5, predictedDx: 130), 1)
        XCTAssertEqual(PageTurn.direction(dx: -120, dy: 5, predictedDx: -130), -1)
    }

    func testFlickTurnsEvenIfShort() {
        XCTAssertEqual(PageTurn.direction(dx: 40, dy: 3, predictedDx: 260), 1)
        XCTAssertEqual(PageTurn.direction(dx: -40, dy: 3, predictedDx: -260), -1)
    }

    func testMostlyVerticalDragNeverTurns() {
        XCTAssertNil(PageTurn.direction(dx: 100, dy: 220, predictedDx: 400))
    }

    func testTopPageGoesToTheBottomAndRevealsTheNext() {
        // Sliding the top page of a 4-page pile: it travels to the bottom and the one beneath becomes the top.
        let pages = (0..<4).map { Page(id: "p\($0)", entryId: "e", order: $0, text: "", lookSeed: "1",
                                       deleted: false, updatedAt: 1, updatedBy: "dev-a") }
        let turned = StackOps.move(pages, from: pages.count - 1, to: 0)
        XCTAssertEqual(turned.map(\.id), ["p3", "p0", "p1", "p2"])
        XCTAssertEqual(turned.last?.id, "p2")                       // the page under the old top is now on top
        // Doing it four times cycles back to the start.
        var cur = pages
        for _ in 0..<4 { cur = StackOps.move(cur, from: cur.count - 1, to: 0) }
        XCTAssertEqual(cur.map(\.id), pages.map(\.id))
    }
}
