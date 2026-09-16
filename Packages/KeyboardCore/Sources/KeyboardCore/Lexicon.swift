import Foundation

/// The keyboard's word list and next-word table, memory-mapped from `lexicon.dat`
/// (built by `scripts/build-lexicon.py`, which documents the layout).
///
/// Mapped rather than parsed: the pages are file-backed and clean, which keeps the
/// extension well inside its memory ceiling where ~60k Swift strings would not.
public final class Lexicon {
    public enum LoadError: Error { case unreadable, badHeader, truncated }

    public let count: Int
    private let data: NSData
    private let blob: UnsafePointer<UInt8>
    private let offsets: UnsafePointer<UInt32>
    private let logFreqs: UnsafePointer<Float32>
    private let rowStarts: UnsafePointer<UInt32>
    private let followerIDs: UnsafePointer<UInt32>
    private let followerLogPs: UnsafePointer<Float32>

    /// Word ids bucketed by the first and last letter of their swipe keys.
    private lazy var endpointBuckets: [[Int32]] = buildBuckets()

    public init(url: URL) throws {
        guard let data = try? NSData(contentsOf: url, options: .alwaysMapped) else {
            throw LoadError.unreadable
        }
        guard data.length >= 20 else { throw LoadError.badHeader }
        let base = data.bytes
        func u32(_ at: Int) -> Int { Int(base.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
        guard base.loadUnaligned(as: UInt32.self) == 0x584C_4243, u32(4) == 1 else {  // "CBLX"
            throw LoadError.badHeader
        }
        let n = u32(8), blobSize = u32(12), bigrams = u32(16)
        var cursor = 20
        func take<T>(_ count: Int, _: T.Type) -> UnsafePointer<T> {
            defer { cursor += count * MemoryLayout<T>.stride }
            return (base + cursor).assumingMemoryBound(to: T.self)
        }
        let expected = 20 + blobSize + 4 * ((n + 1) + n + (n + 2) + bigrams * 2)
        guard data.length == expected, blobSize % 4 == 0 else { throw LoadError.truncated }

        self.data = data
        count = n
        blob = take(blobSize, UInt8.self)
        offsets = take(n + 1, UInt32.self)
        logFreqs = take(n, Float32.self)
        rowStarts = take(n + 2, UInt32.self)
        followerIDs = take(bigrams, UInt32.self)
        followerLogPs = take(bigrams, Float32.self)
    }

    // MARK: Words

    private func bytes(_ id: Int) -> UnsafeBufferPointer<UInt8> {
        let start = Int(offsets[id]), end = Int(offsets[id + 1])
        return UnsafeBufferPointer(start: blob + start, count: end - start)
    }

    public func word(_ id: Int) -> String {
        String(decoding: bytes(id), as: UTF8.self)
    }

    public func logFrequency(_ id: Int) -> Float {
        logFreqs[id]
    }

    /// Lowercases and folds curly apostrophes, matching how the list was built.
    public static func normalize(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }

    public func id(of word: String) -> Int? {
        let key = Array(Self.normalize(word).utf8)
        let lower = lowerBound(key)
        return lower < count && compare(bytes(lower), key) == 0 ? lower : nil
    }

    /// Ids of every word that starts with `prefix`, as a contiguous range.
    public func prefixRange(_ prefix: String) -> Range<Int> {
        let key = Array(Self.normalize(prefix).utf8)
        guard !key.isEmpty else { return 0..<count }
        let lower = lowerBound(key)
        var upperKey = key
        // Every word with this prefix sorts before prefix + 0xFF.
        upperKey.append(0xFF)
        return lower..<lowerBound(upperKey)
    }

    private func lowerBound(_ key: [UInt8]) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compare(bytes(mid), key) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func compare(_ a: UnsafeBufferPointer<UInt8>, _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    // MARK: Next-word table

    /// Likely next words after `id`, most likely first; `nil` means sentence start.
    public func followers(of id: Int?) -> [(id: Int, logP: Float)] {
        let row = id ?? count
        let start = Int(rowStarts[row]), end = Int(rowStarts[row + 1])
        return (start..<end).map { (Int(followerIDs[$0]), followerLogPs[$0]) }
    }

    // MARK: Swipe support

    /// The letters a swipe passes through for a word: apostrophes dropped and
    /// repeated letters collapsed, since a path cannot visit a key twice in a row.
    public func swipeKeys(_ id: Int) -> [UInt8] {
        var out: [UInt8] = []
        for b in bytes(id) where b >= 0x61 && b <= 0x7A && out.last != b {
            out.append(b)
        }
        return out
    }

    /// Words whose swipe keys start with `first` and end with `last` (both a–z).
    public func words(from first: UInt8, to last: UInt8) -> [Int32] {
        guard (0x61...0x7A).contains(first), (0x61...0x7A).contains(last) else { return [] }
        return endpointBuckets[Int(first - 0x61) * 26 + Int(last - 0x61)]
    }

    private func buildBuckets() -> [[Int32]] {
        var buckets = [[Int32]](repeating: [], count: 26 * 26)
        for id in 0..<count {
            let keys = swipeKeys(id)
            guard keys.count >= 2, let f = keys.first, let l = keys.last else { continue }
            buckets[Int(f - 0x61) * 26 + Int(l - 0x61)].append(Int32(id))
        }
        return buckets
    }
}
