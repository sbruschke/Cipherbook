import Foundation

public struct RecordVersion: Equatable {
    public var updatedAt: Int64
    public var updatedBy: String
    public init(updatedAt: Int64, updatedBy: String) { self.updatedAt = updatedAt; self.updatedBy = updatedBy }
}

/// Last-write-wins: later timestamp wins; ties go to the greater device id (plain code-unit
/// comparison — device ids are restricted to [a-z0-9-] so every platform agrees). A replay isn't newer.
public func isNewer(_ incoming: RecordVersion, than stored: RecordVersion?) -> Bool {
    guard let stored else { return true }
    if incoming.updatedAt != stored.updatedAt { return incoming.updatedAt > stored.updatedAt }
    return incoming.updatedBy > stored.updatedBy
}

/// A pulled row replaces the local one unless the local row beats it.
public func shouldApplyPulled(incoming: RecordVersion, local: RecordVersion?) -> Bool {
    guard let local else { return true }
    return !isNewer(local, than: incoming)
}

public enum SyncRecord: Equatable {
    case entry(Entry)
    case page(Page)

    var table: String { if case .entry = self { return "entry" } else { return "page" } }
    var id: String { switch self { case .entry(let e): return e.id; case .page(let p): return p.id } }
    var version: RecordVersion {
        switch self {
        case .entry(let e): return RecordVersion(updatedAt: e.updatedAt, updatedBy: e.updatedBy)
        case .page(let p):  return RecordVersion(updatedAt: p.updatedAt, updatedBy: p.updatedBy)
        }
    }
}

public struct SyncChange: Codable, Equatable {
    public var record: SyncRecord
    public init(record: SyncRecord) { self.record = record }

    enum CodingKeys: String, CodingKey { case table, record }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .table) {
        case "entry": record = .entry(try c.decode(Entry.self, forKey: .record))
        case "page":  record = .page(try c.decode(Page.self, forKey: .record))
        default:
            throw DecodingError.dataCorruptedError(forKey: .table, in: c, debugDescription: "unknown table")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(record.table, forKey: .table)
        switch record {
        case .entry(let e): try c.encode(e, forKey: .record)
        case .page(let p):  try c.encode(p, forKey: .record)
        }
    }
}

public struct PushResult: Codable, Equatable {
    public var table: String
    public var id: String?
    /// "accepted" | "ignored" | "rejected"
    public var status: String
    public var serverSeq: Int64?
    public var reason: String?

    enum CodingKeys: String, CodingKey { case table, id, status, reason, serverSeq = "server_seq" }

    public init(table: String, id: String?, status: String, serverSeq: Int64?, reason: String?) {
        self.table = table; self.id = id; self.status = status; self.serverSeq = serverSeq; self.reason = reason
    }
}

public struct PullResponse: Codable, Equatable {
    public var changes: [SyncChange]
    public var next: Int64
    public var more: Bool
}

public extension JournalData {
    mutating func applyPulled(_ changes: [SyncChange]) {
        for change in changes {
            let rec = change.record
            switch rec {
            case .entry(let e):
                let local = entries[e.id].map { RecordVersion(updatedAt: $0.updatedAt, updatedBy: $0.updatedBy) }
                if shouldApplyPulled(incoming: rec.version, local: local) {
                    entries[e.id] = e
                    if local == nil || !isNewer(local!, than: rec.version) { pending.remove("entry/\(e.id)") }
                }
            case .page(let p):
                let local = pages[p.id].map { RecordVersion(updatedAt: $0.updatedAt, updatedBy: $0.updatedBy) }
                if shouldApplyPulled(incoming: rec.version, local: local) {
                    pages[p.id] = p
                    pending.remove("page/\(p.id)")
                }
            }
        }
    }

    /// Records still waiting for the server, entries first. Keys with no record are dropped.
    func pendingChanges(limit: Int) -> [SyncChange] {
        var out: [SyncChange] = []
        for key in pending.sorted() {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "entry", let e = entries[parts[1]] { out.append(SyncChange(record: .entry(e))) }
            if parts[0] == "page", let p = pages[parts[1]] { out.append(SyncChange(record: .page(p))) }
        }
        out.sort { ($0.record.table, $0.record.id) < ($1.record.table, $1.record.id) }
        return Array(out.prefix(limit))
    }

    /// Results are matched to the pushed changes by index. Accepted, ignored (the server already
    /// had a newer row) and rejected (retrying cannot help) all leave the pending set; a missing
    /// result keeps the record pending for the next sync.
    mutating func settle(pushed: [SyncChange], results: [PushResult]) {
        for (i, ch) in pushed.enumerated() where i < results.count {
            pending.remove("\(ch.record.table)/\(ch.record.id)")
        }
        // Keys whose record no longer exists can never be pushed: drop them.
        pending = pending.filter { key in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return false }
            switch parts[0] {
            case "entry": return entries[parts[1]] != nil
            case "page": return pages[parts[1]] != nil
            default: return false
            }
        }
    }
}
