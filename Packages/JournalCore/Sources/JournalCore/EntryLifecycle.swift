import Foundation

public extension JournalData {
    /// True when every live page of the entry is empty or whitespace (or it has none).
    func isBlank(entryID: String) -> Bool {
        livePages(of: entryID).allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Deletes an entry and its pages as tombstones, so the deletion reaches the server even if the
    /// entry was already pushed (e.g. by a sync that fired while it was still being edited).
    mutating func tombstone(entryID: String, now: Int64) {
        guard var e = entries[entryID] else { return }
        for var p in pages.values where p.entryId == entryID && !p.deleted {
            p.deleted = true; p.updatedAt = now; p.updatedBy = deviceID
            pages[p.id] = p; pending.insert("page/\(p.id)")
        }
        e.deleted = true; e.updatedAt = now; e.updatedBy = deviceID
        entries[entryID] = e; pending.insert("entry/\(entryID)")
    }

    /// Turns the entry's pile `by` steps (positive: the top page goes to the bottom). Only the entry changes;
    /// the pages keep their order, so the reading order of the entry is never touched by browsing.
    mutating func turnPile(entryID: String, by steps: Int, now: Int64) {
        guard var e = entries[entryID] else { return }
        let n = livePages(of: entryID).count
        guard n > 1 else { return }
        e.turned = (((e.turned ?? 0) + steps) % n + n) % n
        e.updatedAt = now; e.updatedBy = deviceID
        entries[entryID] = e; pending.insert("entry/\(entryID)")
    }
}
