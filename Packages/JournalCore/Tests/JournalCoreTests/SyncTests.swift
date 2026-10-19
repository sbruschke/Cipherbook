import XCTest
@testable import JournalCore

final class SyncTests: XCTestCase {
    private func vectors() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("testdata/sync-vectors.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func entry(_ id: String, at: Int64, by: String = "dev-a") -> Entry {
        Entry(id: id, createdAt: 1, title: nil, x: 0, y: 0, rot: 0, freeX: nil, freeY: nil,
              fasteners: [], deleted: false, updatedAt: at, updatedBy: by)
    }

    func testNewerMatchesSharedVectors() throws {
        for c in try vectors()["newer"] as! [[String: Any]] {
            let inc = c["incoming"] as! [Any]
            let incoming = RecordVersion(updatedAt: Int64(inc[0] as! Int), updatedBy: inc[1] as! String)
            var stored: RecordVersion?
            if let s = c["stored"] as? [Any] {
                stored = RecordVersion(updatedAt: Int64(s[0] as! Int), updatedBy: s[1] as! String)
            }
            XCTAssertEqual(isNewer(incoming, than: stored), c["newer"] as! Bool, c["name"] as! String)
        }
    }

    func testBigSeedRoundTripsAsString() throws {
        let big = try vectors()["big_seed"] as! String
        let page = Page(id: "p1", entryId: "e1", order: 0, text: "hi", lookSeed: big,
                        deleted: false, updatedAt: 5, updatedBy: "dev-a")
        let data = try JSONEncoder().encode(SyncChange(record: .page(page)))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["table"] as? String, "page")
        XCTAssertEqual((json["record"] as! [String: Any])["look_seed"] as? String, big)
        let back = try JSONDecoder().decode(SyncChange.self, from: data)
        XCTAssertEqual(back.record, .page(page))
        XCTAssertEqual(page.lookSeedValue, UInt64.max)
    }

    func testEntryWireKeys() throws {
        let e = entry("e1", at: 9)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SyncChange(record: .entry(e)))) as! [String: Any]
        let rec = json["record"] as! [String: Any]
        for k in ["id", "created_at", "x", "y", "rot", "fasteners", "deleted", "updated_at", "updated_by"] {
            XCTAssertNotNil(rec[k], k)
        }
    }

    func testApplyPulledRespectsLWW() {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e1"] = entry("e1", at: 200)
        d.applyPulled([SyncChange(record: .entry(entry("e1", at: 100, by: "dev-b")))])
        XCTAssertEqual(d.entries["e1"]?.updatedAt, 200)          // older pull does not regress
        d.applyPulled([SyncChange(record: .entry(entry("e1", at: 300, by: "dev-b")))])
        XCTAssertEqual(d.entries["e1"]?.updatedAt, 300)
        XCTAssertFalse(d.pending.contains("entry/e1"))
    }

    func testPendingChangesAndSettle() {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e1"] = entry("e1", at: 5)
        d.pending = ["entry/e1", "page/gone"]                      // dangling key is dropped
        let changes = d.pendingChanges(limit: 10)
        XCTAssertEqual(changes.count, 1)
        d.settle(pushed: changes, results: [PushResult(table: "entry", id: "e1", status: "accepted", serverSeq: 1, reason: nil)])
        XCTAssertTrue(d.pending.isEmpty)
    }

    func testSettleKeepsPendingWhenResultMissing() {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e1"] = entry("e1", at: 5)
        d.pending = ["entry/e1"]
        d.settle(pushed: d.pendingChanges(limit: 10), results: [])   // network cut mid-response
        XCTAssertEqual(d.pending, ["entry/e1"])
    }

    func testRejectedIsDroppedFromPending() {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e1"] = entry("e1", at: 5)
        d.pending = ["entry/e1"]
        d.settle(pushed: d.pendingChanges(limit: 10),
                 results: [PushResult(table: "entry", id: "e1", status: "rejected", serverSeq: nil, reason: "invalid")])
        XCTAssertTrue(d.pending.isEmpty)
    }
}

final class SettleRaceTests: XCTestCase {
    private func entry(_ id: String, at: Int64) -> Entry {
        Entry(id: id, createdAt: 1, title: nil, x: 0, y: 0, rot: 0, freeX: nil, freeY: nil,
              fasteners: [], deleted: false, updatedAt: at, updatedBy: "dev-a")
    }
    private let ok = { (t: String, id: String) in PushResult(table: t, id: id, status: "accepted", serverSeq: 1, reason: nil) }

    func testEntryEditedWhileThePushWasInFlightStaysPending() {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e1"] = entry("e1", at: 5); d.pending = ["entry/e1"]
        let pushed = d.pendingChanges(limit: 10)
        d.entries["e1"]!.updatedAt = 9
        d.settle(pushed: pushed, results: [ok("entry", "e1")])
        XCTAssertEqual(d.pending, ["entry/e1"])
    }

    func testPageEditedWhileThePushWasInFlightStaysPending() {
        var d = JournalData(deviceID: "dev-a")
        d.pages["p1"] = Page(id: "p1", entryId: "e1", order: 0, text: "a", lookSeed: "1", deleted: false, updatedAt: 5, updatedBy: "dev-a")
        d.pending = ["page/p1"]
        let pushed = d.pendingChanges(limit: 10)
        d.pages["p1"]!.text = "ab"; d.pages["p1"]!.updatedAt = 6
        d.settle(pushed: pushed, results: [ok("page", "p1")])
        XCTAssertEqual(d.pending, ["page/p1"])
    }
}

final class EntryLifecycleTests: XCTestCase {
    private func data() -> JournalData {
        var d = JournalData(deviceID: "dev-a")
        d.entries["e1"] = Entry(id: "e1", createdAt: 1, title: nil, x: 0, y: 0, rot: 0, freeX: nil, freeY: nil,
                                fasteners: [], deleted: false, updatedAt: 1, updatedBy: "dev-a")
        d.pages["p1"] = Page(id: "p1", entryId: "e1", order: 0, text: "  \n", lookSeed: "1", deleted: false, updatedAt: 1, updatedBy: "dev-a")
        d.pages["p2"] = Page(id: "p2", entryId: "e1", order: 1, text: "", lookSeed: "2", deleted: false, updatedAt: 1, updatedBy: "dev-a")
        return d
    }

    func testBlankDetection() {
        var d = data()
        XCTAssertTrue(d.isBlank(entryID: "e1"))
        d.pages["p2"]!.text = "hello"
        XCTAssertFalse(d.isBlank(entryID: "e1"))
        XCTAssertTrue(JournalData(deviceID: "dev-a").isBlank(entryID: "nope"))
    }

    func testTombstoneStampsAndQueuesEverything() {
        var d = data()
        d.tombstone(entryID: "e1", now: 50)
        XCTAssertTrue(d.entries["e1"]!.deleted); XCTAssertEqual(d.entries["e1"]!.updatedAt, 50)
        XCTAssertTrue(d.pages["p1"]!.deleted && d.pages["p2"]!.deleted)
        XCTAssertEqual(d.pending, ["entry/e1", "page/p1", "page/p2"])
        XCTAssertTrue(d.livePages(of: "e1").isEmpty)
    }

    func testTombstoneOfUnknownEntryIsANoOp() {
        var d = JournalData(deviceID: "dev-a")
        d.tombstone(entryID: "nope", now: 1)
        XCTAssertTrue(d.pending.isEmpty)
    }
}
