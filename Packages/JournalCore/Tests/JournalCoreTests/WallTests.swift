import XCTest
@testable import JournalCore

final class WallTests: XCTestCase {
    private func e(_ id: String, _ x: Double, _ y: Double, created: Int64 = 1, deleted: Bool = false) -> Entry {
        Entry(id: id, createdAt: created, title: nil, x: x, y: y, rot: 0, freeX: nil, freeY: nil,
              fasteners: [], deleted: deleted, updatedAt: 1, updatedBy: "dev-a")
    }
    private func pg(_ id: String, _ order: Int, _ text: String = "t", deleted: Bool = false) -> Page {
        Page(id: id, entryId: "e", order: order, text: text, lookSeed: "1", deleted: deleted, updatedAt: 1, updatedBy: "dev-a")
    }

    // MARK: wall
    func testSnapMovesToCellCentersAndRemembersFreePosition() {
        let out = WallLayout.snapAll([e("a", 300, 100)])
        let c = WallLayout.center(of: WallLayout.cell(for: Pt(300, 100)))
        XCTAssertEqual(out[0].x, c.x); XCTAssertEqual(out[0].y, c.y)
        XCTAssertEqual(out[0].freeX, 300); XCTAssertEqual(out[0].freeY, 100)
    }

    func testTwoStacksNeverShareACell() {
        let out = WallLayout.snapAll([e("a", 10, 10, created: 1), e("b", 20, 15, created: 2), e("c", 5, 5, created: 3)])
        let cells = Set(out.map { WallLayout.cell(for: Pt($0.x, $0.y)) })
        XCTAssertEqual(cells.count, 3)
    }

    func testSnapIsDeterministicRegardlessOfInputOrder() {
        let a = WallLayout.snapAll([e("a", 10, 10, created: 1), e("b", 20, 15, created: 2)])
        let b = WallLayout.snapAll([e("b", 20, 15, created: 2), e("a", 10, 10, created: 1)])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: a.map { ($0.id, Pt($0.x, $0.y)) }),
                       Dictionary(uniqueKeysWithValues: b.map { ($0.id, Pt($0.x, $0.y)) }))
    }

    func testRestoreBringsBackFreePositions() {
        let start = [e("a", 313, 97), e("b", 330, 120)]
        let back = WallLayout.restoreAll(WallLayout.snapAll(start))
        XCTAssertEqual(back.map { Pt($0.x, $0.y) }, start.map { Pt($0.x, $0.y) })
        XCTAssertTrue(back.allSatisfy { $0.freeX == nil && $0.freeY == nil })
    }

    func testDropFreeAndSnapped() {
        let list = [e("a", 0, 0), e("b", 260, 0)]
        let free = WallLayout.drop("a", at: Pt(77, 91), snap: false, in: list)
        XCTAssertEqual(Pt(free[0].x, free[0].y), Pt(77, 91))
        let snapped = WallLayout.drop("a", at: Pt(250, 10), snap: true, in: list)   // wants b's cell
        XCTAssertNotEqual(WallLayout.cell(for: Pt(snapped[0].x, snapped[0].y)),
                          WallLayout.cell(for: Pt(snapped[1].x, snapped[1].y)))
        XCTAssertNil(snapped[0].freeX)
    }

    func testDeletedEntriesAreIgnored() {
        let out = WallLayout.snapAll([e("a", 10, 10), e("gone", 12, 12, deleted: true)])
        XCTAssertEqual(out[1].x, 12)                   // untouched
        XCTAssertEqual(WallLayout.cell(for: Pt(out[0].x, out[0].y)), WallLayout.cell(for: Pt(10, 10)))
    }

    // MARK: stack ops
    func testMoveRenumbers() {
        let pages = [pg("a", 0), pg("b", 1), pg("c", 2)]
        let m = StackOps.move(pages, from: 0, to: 2)
        XCTAssertEqual(m.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(m.map(\.order), [0, 1, 2])
        XCTAssertEqual(StackOps.move(pages, from: 1, to: 1).map(\.id), ["a", "b", "c"])
    }

    func testShufflePathRespectsPhysicalSpace() {
        let c = 280.0
        for (from, to) in [(0, 4), (2, 4), (3, 0), (1, 3), (4, 0)] {
            let path = StackOps.shufflePath(count: 5, from: from, to: to, clearance: c)
            XCTAssertEqual(path.first?.layer, from); XCTAssertEqual(path.last?.layer, to)
            XCTAssertEqual(path.first?.offsetX, 0); XCTAssertEqual(path.last?.offsetX, 0)
            XCTAssertEqual(path.last?.lift, 0)
            for (a, b) in zip(path, path.dropFirst()) {
                XCTAssertLessThan(a.t, b.t)
                if a.layer != b.layer {   // a page only changes layer while fully clear of the stack
                    XCTAssertGreaterThanOrEqual(a.offsetX, c); XCTAssertGreaterThanOrEqual(b.offsetX, c)
                }
            }
        }
        XCTAssertTrue(StackOps.shufflePath(count: 5, from: 2, to: 2, clearance: c).isEmpty)
        XCTAssertTrue(StackOps.shufflePath(count: 1, from: 0, to: 0, clearance: c).isEmpty)
    }

    // MARK: reflow
    private func ids() -> () -> String { var n = 0; return { n += 1; return "new\(n)" } }

    func testReflowOverflowAddsPageWithNewSeed() {
        let pages = [pg("a", 0, "hello ")]
        let out = EntryEditing.reflow(pages: pages, entryID: "e", from: 0, newText: "hello world foo bar",
                                      fits: { $0.count <= 10 }, now: 50, device: "dev-b", makeID: ids(), makeSeed: { 777 })
        let live = out.filter { !$0.deleted }.sorted { $0.order < $1.order }
        XCTAssertEqual(live.map(\.text), ["hello ", "world foo ", "bar"])
        XCTAssertEqual(live[0].updatedAt, 1)                       // unchanged page isn't re-stamped
        XCTAssertEqual(live[1].lookSeed, "777"); XCTAssertEqual(live[1].updatedBy, "dev-b")
        XCTAssertEqual(live.map(\.order), [0, 1, 2])
        XCTAssertEqual(live[1].entryId, "e")
    }

    func testReflowShrinkTombstonesExtraPages() {
        let pages = [pg("a", 0, "one "), pg("b", 1, "two "), pg("c", 2, "three")]
        let out = EntryEditing.reflow(pages: pages, entryID: "e", from: 0, newText: "x",
                                      fits: { $0.count <= 100 }, now: 9, device: "dev-b", makeID: ids(), makeSeed: { 1 })
        let byID = Dictionary(uniqueKeysWithValues: out.map { ($0.id, $0) })
        XCTAssertEqual(byID["a"]?.text, "xtwo three")
        XCTAssertEqual(byID["b"]?.deleted, true); XCTAssertEqual(byID["b"]?.updatedAt, 9)
        XCTAssertEqual(byID["c"]?.deleted, true)
    }

    func testReflowFromMiddleLeavesEarlierPagesAlone() {
        let pages = [pg("a", 0, "keep "), pg("b", 1, "old")]
        let out = EntryEditing.reflow(pages: pages, entryID: "e", from: 1, newText: "new",
                                      fits: { $0.count <= 10 }, now: 9, device: "dev-b", makeID: ids(), makeSeed: { 1 })
        XCTAssertEqual(out.first { $0.id == "a" }?.updatedAt, 1)
        XCTAssertEqual(out.first { $0.id == "b" }?.text, "new")
    }
}
