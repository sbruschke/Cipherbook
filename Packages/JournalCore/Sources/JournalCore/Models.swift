import Foundation

public struct Entry: Codable, Equatable, Identifiable {
    public var id: String
    public var createdAt: Int64
    public var title: String?
    public var x: Double
    public var y: Double
    public var rot: Double
    public var freeX: Double?
    public var freeY: Double?
    public var fasteners: [Fastener]
    public var deleted: Bool
    public var updatedAt: Int64
    public var updatedBy: String
    /// How many times the pile has been turned (the top page sent to the bottom). Browsing the pile never
    /// changes the pages' `order`, which is the reading order the desktop notes use.
    public var turned: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, x, y, rot, fasteners, deleted, turned
        case createdAt = "created_at", freeX = "free_x", freeY = "free_y"
        case updatedAt = "updated_at", updatedBy = "updated_by"
    }

    public init(id: String, createdAt: Int64, title: String?, x: Double, y: Double, rot: Double,
                freeX: Double?, freeY: Double?, fasteners: [Fastener], deleted: Bool,
                updatedAt: Int64, updatedBy: String, turned: Int? = nil) {
        self.id = id; self.createdAt = createdAt; self.title = title; self.x = x; self.y = y
        self.rot = rot; self.freeX = freeX; self.freeY = freeY; self.fasteners = fasteners
        self.deleted = deleted; self.updatedAt = updatedAt; self.updatedBy = updatedBy; self.turned = turned
    }
}

public struct Page: Codable, Equatable, Identifiable {
    public var id: String
    public var entryId: String
    /// 0 = bottom of the stack; the highest order is the top page.
    public var order: Int
    public var text: String
    /// Decimal string: a UInt64 does not survive a JSON number.
    public var lookSeed: String
    public var deleted: Bool
    public var updatedAt: Int64
    public var updatedBy: String

    enum CodingKeys: String, CodingKey {
        case id, text, deleted
        case entryId = "entry_id", order = "ord", lookSeed = "look_seed"
        case updatedAt = "updated_at", updatedBy = "updated_by"
    }

    public var lookSeedValue: UInt64 { UInt64(lookSeed) ?? 0 }

    public init(id: String, entryId: String, order: Int, text: String, lookSeed: String,
                deleted: Bool, updatedAt: Int64, updatedBy: String) {
        self.id = id; self.entryId = entryId; self.order = order; self.text = text
        self.lookSeed = lookSeed; self.deleted = deleted; self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

/// Everything persisted on device: records, the unpushed set, the pull cursor.
public struct JournalData: Codable, Equatable {
    public var entries: [String: Entry] = [:]
    public var pages: [String: Page] = [:]
    /// "entry/<id>" or "page/<id>" for records changed locally and not yet accepted by the server.
    public var pending: Set<String> = []
    public var cursor: Int64 = 0
    public var deviceID: String

    public init(deviceID: String) { self.deviceID = deviceID }

    public static func pendingKey(table: String, id: String) -> String { "\(table)/\(id)" }

    public func livePages(of entryID: String) -> [Page] {
        pages.values.filter { $0.entryId == entryID && !$0.deleted }.sorted { $0.order < $1.order }
    }
}
