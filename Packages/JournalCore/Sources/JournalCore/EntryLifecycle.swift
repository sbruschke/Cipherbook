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
}
