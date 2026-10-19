import Foundation
import JournalCore

@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var data: JournalData
    private let file = Storage.journalDir.appendingPathComponent("journal.json")
    private var saveWork: DispatchWorkItem?

    init() {
        if let raw = try? Data(contentsOf: file), let d = try? JSONDecoder().decode(JournalData.self, from: raw) {
            data = d
        } else {
            data = JournalData(deviceID: "ios-" + UUID().uuidString.lowercased().prefix(24))
            save()
        }
    }

    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private var device: String { data.deviceID }

    var liveEntries: [Entry] {
        data.entries.values.filter { !$0.deleted }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func pages(of entryID: String) -> [Page] { data.livePages(of: entryID) }

    // MARK: persistence
    private func save() {
        saveWork?.cancel()
        let snapshot = data
        let work = DispatchWorkItem { [file] in
            if let raw = try? JSONEncoder().encode(snapshot) { try? raw.write(to: file, options: .atomic) }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func touch(entry e: Entry) { var e = e; e.updatedAt = now; e.updatedBy = device; put(e) }
    private func put(_ e: Entry) {
        data.entries[e.id] = e; data.pending.insert("entry/\(e.id)"); save()
    }
    private func put(_ p: Page) {
        data.pages[p.id] = p; data.pending.insert("page/\(p.id)"); save()
    }

    // MARK: entries
    @discardableResult
    func newEntry() -> String {
        let id = UUID().uuidString.lowercased()
        let live = liveEntries
        // Drop new stacks to the right of the rightmost one, on the same row.
        let x = (live.map(\.x).max() ?? -WallLayout.cellW) + WallLayout.cellW
        var rng = SystemRandomNumberGenerator()
        let e = Entry(id: id, createdAt: now, title: nil, x: x, y: 0,
                      rot: Double.random(in: -3...3, using: &rng), freeX: nil, freeY: nil,
                      fasteners: [Fastener(kind: .pin, seed: String(UInt64.random(in: 0...UInt64.max)))],
                      deleted: false, updatedAt: now, updatedBy: device)
        put(e)
        let p = Page(id: UUID().uuidString.lowercased(), entryId: id, order: 0, text: "",
                     lookSeed: String(UInt64.random(in: 0...UInt64.max)),
                     deleted: false, updatedAt: now, updatedBy: device)
        put(p)
        return id
    }

    /// Replaces page `pageIndex` with `text` and re-flows it and the pages after it.
    func edit(entryID: String, pageIndex: Int, text: String, fits: (String) -> Bool) {
        let all = data.pages.values.filter { $0.entryId == entryID }
        let out = EntryEditing.reflow(pages: all, entryID: entryID, from: pageIndex, newText: text, fits: fits,
                                      now: now, device: device,
                                      makeID: { UUID().uuidString.lowercased() },
                                      makeSeed: { UInt64.random(in: 0...UInt64.max) })
        for p in out where data.pages[p.id] != p { put(p) }
    }

    /// Done: an entry with no text at all is discarded entirely (never synced, never shown).
    func finishEntry(_ id: String) {
        let live = pages(of: id)
        if live.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            discard(id)
        }
    }

    private func discard(_ id: String) {
        for p in data.pages.values where p.entryId == id {
            data.pages[p.id] = nil; data.pending.remove("page/\(p.id)")
        }
        data.entries[id] = nil; data.pending.remove("entry/\(id)")
        save()
    }

    func deleteEntry(_ id: String) {
        guard var e = data.entries[id] else { return }
        for var p in data.pages.values where p.entryId == id && !p.deleted {
            p.deleted = true; p.updatedAt = now; p.updatedBy = device; put(p)
        }
        e.deleted = true; touch(entry: e)
    }

    // MARK: wall
    func setSnap(_ on: Bool) {
        let before = data.entries
        let list = Array(data.entries.values)
        let after = on ? WallLayout.snapAll(list) : WallLayout.restoreAll(list)
        for e in after where before[e.id] != e { touch(entry: e) }
    }

    func drop(_ id: String, at p: Pt, snap: Bool) {
        let before = data.entries
        let after = WallLayout.drop(id, at: p, snap: snap, in: Array(data.entries.values))
        for e in after where before[e.id] != e { touch(entry: e) }
    }

    func reorder(entryID: String, from: Int, to: Int) {
        for p in StackOps.move(pages(of: entryID), from: from, to: to) where data.pages[p.id]?.order != p.order {
            var p = p; p.updatedAt = now; p.updatedBy = device; put(p)
        }
    }

    func addFastener(_ kind: FastenerKind, to id: String) {
        guard var e = data.entries[id] else { return }
        e.fasteners.append(Fastener(kind: kind, seed: String(UInt64.random(in: 0...UInt64.max))))
        touch(entry: e)
    }

    func removeFastener(at index: Int, from id: String) {
        guard var e = data.entries[id], e.fasteners.indices.contains(index) else { return }
        e.fasteners.remove(at: index); touch(entry: e)
    }

    // MARK: sync plumbing (used by JournalSyncClient)
    func pending(limit: Int) -> [SyncChange] { data.pendingChanges(limit: limit) }
    func settle(pushed: [SyncChange], results: [PushResult]) { data.settle(pushed: pushed, results: results); save() }
    func applyPull(_ changes: [SyncChange], next: Int64) {
        data.applyPulled(changes); data.cursor = next; save()
    }
}
