import Foundation
import JournalCore

enum WordArtCache {
    private final class Box { let value: WordArtDrawing; init(_ v: WordArtDrawing) { value = v } }
    private static let cache = NSCache<NSString, Box>()

    static func drawing(text: String, seed: UInt64) -> WordArtDrawing {
        let key = "\(seed)#\(text.count)#\(text.hashValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let d = WordArt.make(text: text, seed: seed)
        cache.setObject(Box(d), forKey: key)
        return d
    }
}
