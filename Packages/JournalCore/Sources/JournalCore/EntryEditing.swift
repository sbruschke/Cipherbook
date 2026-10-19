import Foundation

public enum EntryEditing {
    /// Re-paginates the edited page and everything after it. Earlier pages are untouched; pages
    /// whose text does not change keep their stamp (so they are not re-synced); new pages get a
    /// fresh id and look seed; pages no longer needed become tombstones.
    public static func reflow(pages: [Page], entryID: String, from index: Int, newText: String,
                              fits: (String) -> Bool, now: Int64, device: String,
                              makeID: () -> String, makeSeed: () -> UInt64) -> [Page] {
        var live = pages.filter { !$0.deleted }.sorted { $0.order < $1.order }
        let dead = pages.filter { $0.deleted }
        let idx = min(max(index, 0), max(live.count - 1, 0))
        let tail = newText + live.dropFirst(idx + 1).map(\.text).joined()
        let newTexts = Paginator.paginate(tail, fits: fits)

        var result: [Page] = Array(live.prefix(idx))
        for (j, text) in newTexts.enumerated() {
            let pos = idx + j
            if pos < live.count {
                var p = live[pos]
                if p.text != text || p.order != pos {
                    p.text = text; p.order = pos; p.updatedAt = now; p.updatedBy = device
                }
                result.append(p)
            } else {
                result.append(Page(id: makeID(), entryId: entryID, order: pos, text: text,
                                   lookSeed: String(makeSeed()), deleted: false, updatedAt: now, updatedBy: device))
            }
        }
        if live.count > idx + newTexts.count {
            for p in live[(idx + newTexts.count)...] {
                var t = p; t.deleted = true; t.updatedAt = now; t.updatedBy = device
                result.append(t)
            }
        }
        live.removeAll()
        return result + dead
    }
}
