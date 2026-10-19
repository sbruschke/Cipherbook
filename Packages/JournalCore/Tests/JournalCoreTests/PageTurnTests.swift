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

final class PileTests: XCTestCase {
    private func pages(_ n: Int) -> [Page] {
        (0..<n).map { Page(id: "p\($0)", entryId: "e", order: $0, text: "t\($0)", lookSeed: "1",
                           deleted: false, updatedAt: 1, updatedBy: "dev-a") }
    }
    private func data(pages n: Int) -> JournalData {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e"] = Entry(id: "e", createdAt: 1, title: nil, x: 0, y: 0, rot: 0, freeX: nil, freeY: nil,
                               fasteners: [], deleted: false, updatedAt: 1, updatedBy: "dev-a")
        for p in pages(n) { d.pages[p.id] = p }
        return d
    }

    func testPileIsReadingOrderWhenUnturned() {
        XCTAssertEqual(StackOps.pile(pages(3), turned: 0).map(\.id), ["p0", "p1", "p2"])
        XCTAssertEqual(StackOps.pile(pages(3), turned: nil).map(\.id), ["p0", "p1", "p2"])
    }

    func testEachTurnMovesTheTopPageToTheBottom() {
        XCTAssertEqual(StackOps.pile(pages(3), turned: 1).map(\.id), ["p2", "p0", "p1"])
        XCTAssertEqual(StackOps.pile(pages(3), turned: 2).map(\.id), ["p1", "p2", "p0"])
        XCTAssertEqual(StackOps.pile(pages(3), turned: 3).map(\.id), ["p0", "p1", "p2"])     // full cycle
        XCTAssertEqual(StackOps.pile(pages(3), turned: 4).map(\.id), ["p2", "p0", "p1"])
        XCTAssertEqual(StackOps.pile(pages(3), turned: -1).map(\.id), ["p1", "p2", "p0"])    // bottom to the front
        XCTAssertEqual(StackOps.pile(pages(1), turned: 5).map(\.id), ["p0"])
        XCTAssertTrue(StackOps.pile([], turned: 2).isEmpty)
    }

    func testTurningNeverChangesReadingOrder() {
        var d = data(pages: 4)
        d.turnPile(entryID: "e", by: 1, now: 50)
        d.turnPile(entryID: "e", by: 1, now: 51)
        XCTAssertEqual(d.livePages(of: "e").map(\.id), ["p0", "p1", "p2", "p3"])
        XCTAssertEqual(d.livePages(of: "e").map(\.order), [0, 1, 2, 3])
        XCTAssertEqual(d.entries["e"]!.turned, 2)
        XCTAssertEqual(StackOps.pile(d.livePages(of: "e"), turned: d.entries["e"]!.turned).last?.id, "p1")
    }

    func testTurnIsStampedQueuedAndWrapsBackwards() {
        var d = data(pages: 3)
        d.turnPile(entryID: "e", by: -1, now: 77)
        XCTAssertEqual(d.entries["e"]!.turned, 2)                    // one step back = two forward on a 3-page pile
        XCTAssertEqual(d.entries["e"]!.updatedAt, 77)
        XCTAssertEqual(d.pending, ["entry/e"])
    }

    func testTurningASinglePageOrUnknownEntryDoesNothing() {
        var one = data(pages: 1)
        one.turnPile(entryID: "e", by: 1, now: 9)
        XCTAssertTrue(one.pending.isEmpty)
        var d = data(pages: 3)
        d.turnPile(entryID: "nope", by: 1, now: 9)
        XCTAssertTrue(d.pending.isEmpty)
    }

    func testEntryTurnedSurvivesTheWireAndOldRecordsStillDecode() throws {
        var e = Entry(id: "e", createdAt: 1, title: nil, x: 0, y: 0, rot: 0, freeX: nil, freeY: nil,
                      fasteners: [], deleted: false, updatedAt: 1, updatedBy: "dev-a")
        e.turned = 2
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]
        XCTAssertEqual(json["turned"] as? Int, 2)
        var old = json; old.removeValue(forKey: "turned")
        let back = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(back.turned)
    }
}
