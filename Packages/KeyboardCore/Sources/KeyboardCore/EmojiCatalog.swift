import Foundation

/// One emoji as the keyboard shows it. `text` is the standard Unicode string that gets
/// typed; `image` is where its Fluent art sits in the image pack (nil: the system draws it).
public struct Emoji: Equatable {
    public struct Variant: Equatable {
        public let text: String
        public let image: Range<Int>?
    }

    public let index: Int
    public let category: Int
    public let text: String
    public let name: String
    public let image: Range<Int>?
    /// Light … dark skin tones, when the emoji has them. The default is `text`/`image`.
    public let tones: [Variant]

    /// The default followed by the five tones, as the long-press picker lists them.
    public var variants: [Variant] { [Variant(text: text, image: image)] + tones }

    fileprivate let words: [Substring]
}

/// The emoji list and its art, built by `scripts/build-emoji.py`: a JSON index plus one
/// file of WebP images end to end, mapped rather than read so only viewed art is paged in.
public final class EmojiCatalog {
    public let categories: [String]
    public let emoji: [Emoji]
    private let images: NSData
    private let byText: [String: (emoji: Int, variant: Int)]

    private struct Index: Decodable {
        struct Item: Decodable {
            struct Tone: Decodable { let s: String; let i: [Int]? }
            let c: Int, s: String, n: String, k: String
            let i: [Int]?
            let t: [Tone]?
        }
        let version: Int
        let categories: [String]
        let emoji: [Item]
    }

    public enum LoadError: Error { case unsupportedVersion, badImageSpan }

    public init(index: URL, images: URL) throws {
        let decoded = try JSONDecoder().decode(Index.self, from: Data(contentsOf: index))
        guard decoded.version == 1 else { throw LoadError.unsupportedVersion }
        let pack = try NSData(contentsOf: images, options: .alwaysMapped)
        func span(_ pair: [Int]?) throws -> Range<Int>? {
            guard let pair else { return nil }
            guard pair.count == 2, pair[0] >= 0, pair[1] > 0, pair[0] + pair[1] <= pack.length else {
                throw LoadError.badImageSpan
            }
            return pair[0]..<(pair[0] + pair[1])
        }

        var list: [Emoji] = []
        var lookup: [String: (Int, Int)] = [:]
        for (n, item) in decoded.emoji.enumerated() {
            let tones = try (item.t ?? []).map { Emoji.Variant(text: $0.s, image: try span($0.i)) }
            let words = (item.n.lowercased() + " " + item.k)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            list.append(Emoji(index: n, category: item.c, text: item.s, name: item.n,
                              image: try span(item.i), tones: tones, words: words))
            lookup[item.s] = (n, 0)
            for (t, tone) in tones.enumerated() { lookup[tone.text] = (n, t + 1) }
        }
        categories = decoded.categories
        emoji = list
        byText = lookup
        self.images = pack
    }

    /// The WebP bytes for an image span.
    public func imageData(_ span: Range<Int>) -> Data {
        Data(bytes: images.bytes + span.lowerBound, count: span.count)
    }

    /// The emoji a typed string belongs to, and which variant it is (0 = default).
    public func lookup(_ text: String) -> (emoji: Emoji, variant: Int)? {
        byText[text].map { (emoji[$0.emoji], $0.variant) }
    }

    /// First emoji of each category, for the category bar.
    public func firstIndex(ofCategory category: Int) -> Int? {
        emoji.firstIndex { $0.category == category }
    }

    /// Emoji whose name or keywords start with every word of `query`, best first:
    /// names that begin with the query, then names containing the words, then keyword
    /// matches, each in keyboard order.
    public func search(_ query: String, limit: Int = 60) -> [Emoji] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        let terms = needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !terms.isEmpty else { return [] }
        var scored: [(score: Int, emoji: Emoji)] = []
        for e in emoji {
            guard terms.allSatisfy({ t in e.words.contains { $0.hasPrefix(t) } }) else { continue }
            let name = e.name.lowercased()
            let nameWords = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let inName = terms.allSatisfy { t in nameWords.contains { $0.hasPrefix(t) } }
            let score = name.hasPrefix(needle) ? 0 : (inName ? 1 : 2)
            scored.append((score, e))
        }
        return scored.sorted { ($0.score, $0.emoji.index) < ($1.score, $1.emoji.index) }
            .prefix(limit).map(\.emoji)
    }
}

/// Most-recently-used emoji, as stored strings (so a chosen skin tone is kept).
public enum EmojiRecents {
    public static let capacity = 32

    public static func recording(_ text: String, in list: [String]) -> [String] {
        Array(([text] + list.filter { $0 != text }).prefix(capacity))
    }
}
