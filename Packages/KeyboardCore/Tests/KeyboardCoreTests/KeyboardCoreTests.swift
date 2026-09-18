import Foundation
import XCTest
@testable import KeyboardCore

/// The real lexicon shipped in the keyboard, so these tests cover the data too.
let sharedLexicon: Lexicon = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // KeyboardCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // KeyboardCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Keyboard/Resources/lexicon.dat")
    return try! Lexicon(url: url)
}()

final class LexiconTests: XCTestCase {
    let lex = sharedLexicon

    func testLooksUpWordsCaseAndApostropheInsensitively() throws {
        let the = try XCTUnwrap(lex.id(of: "The"))
        XCTAssertEqual(lex.word(the), "the")
        XCTAssertEqual(lex.id(of: "don\u{2019}t"), lex.id(of: "don't"))
        XCTAssertNotNil(lex.id(of: "don't"))
        XCTAssertNil(lex.id(of: "dont"), "lazy contractions are folded into the real spelling")
        XCTAssertNil(lex.id(of: "qzxv"))
    }

    func testPrefixRangeHoldsExactlyThePrefixedWords() {
        let range = lex.prefixRange("ciph")
        XCTAssertFalse(range.isEmpty)
        for id in range { XCTAssertTrue(lex.word(id).hasPrefix("ciph"), lex.word(id)) }
        if range.lowerBound > 0 { XCTAssertFalse(lex.word(range.lowerBound - 1).hasPrefix("ciph")) }
        if range.upperBound < lex.count { XCTAssertFalse(lex.word(range.upperBound).hasPrefix("ciph")) }
        XCTAssertTrue(lex.prefixRange("qzxv").isEmpty)
    }

    func testFollowers() throws {
        let thank = try XCTUnwrap(lex.id(of: "thank"))
        XCTAssertEqual(lex.followers(of: thank).first.map { lex.word($0.id) }, "you")
        XCTAssertFalse(lex.followers(of: nil).isEmpty, "sentence-start row")
    }

    func testSwipeKeysDropApostrophesAndCollapseRepeats() throws {
        XCTAssertEqual(String(decoding: lex.swipeKeys(try XCTUnwrap(lex.id(of: "hello"))), as: UTF8.self), "helo")
        XCTAssertEqual(String(decoding: lex.swipeKeys(try XCTUnwrap(lex.id(of: "don't"))), as: UTF8.self), "dont")
    }
}

final class PredictorTests: XCTestCase {
    let predictor = Predictor(lexicon: sharedLexicon)

    func testContextParsing() {
        XCTAssertEqual(WordContext.from(before: nil, currentWord: nil), .sentenceStart)
        XCTAssertEqual(WordContext.from(before: "Hi there. ", currentWord: nil), .sentenceStart)
        XCTAssertEqual(WordContext.from(before: "I think ", currentWord: nil), .after("think"))
        XCTAssertEqual(WordContext.from(before: "I think wh", currentWord: "wh"), .after("think"))
        XCTAssertEqual(WordContext.from(before: "Don\u{2019}t ", currentWord: nil), .after("don't"))
        XCTAssertEqual(WordContext.from(before: "one, ", currentWord: nil), .unknown)
        XCTAssertEqual(WordContext.from(before: "line\n", currentWord: nil), .sentenceStart)
    }

    func testCompletionsAreFrequencyRanked() {
        let words = predictor.completions(prefix: "th", context: .unknown, limit: 3)
        XCTAssertEqual(words.first, "the")
        XCTAssertFalse(words.contains("th"))
    }

    func testContextLiftsFollowers() {
        let plain = predictor.completions(prefix: "y", context: .unknown, limit: 5)
        let afterThank = predictor.completions(prefix: "y", context: .after("thank"), limit: 5)
        XCTAssertEqual(afterThank.first, "you")
        XCTAssertEqual(Set(plain).count, plain.count)
        let goingT = predictor.completions(prefix: "t", context: .after("going"), limit: 3)
        XCTAssertEqual(goingT.first, "to")
    }

    func testNextWords() {
        XCTAssertEqual(predictor.nextWords(context: .after("thank"), limit: 3).first, "you")
        XCTAssertEqual(predictor.nextWords(context: .after("going"), limit: 3).first, "to")
        XCTAssertFalse(predictor.nextWords(context: .sentenceStart, limit: 3).isEmpty)
        XCTAssertTrue(predictor.nextWords(context: .unknown, limit: 3).isEmpty)
        XCTAssertTrue(predictor.nextWords(context: .after("qzxv"), limit: 3).isEmpty)
    }

    func testRankPutsLikelyWordsFirstAndUnknownsLast() {
        XCTAssertEqual(predictor.rank(["zzqx", "thw", "the", "tho"], context: .unknown), ["the", "tho", "zzqx", "thw"])
    }
}

final class SwipeDecoderTests: XCTestCase {
    /// iPhone portrait geometry, matching `KeyboardView`'s layout rules.
    static let unit = 38.4
    static let keys: [Character: Point] = {
        var out: [Character: Point] = [:]
        let rows: [(String, Double)] = [("qwertyuiop", 3), ("asdfghjkl", 22.2), ("zxcvbnm", 60.6)]
        for (r, (letters, start)) in rows.enumerated() {
            for (i, c) in letters.enumerated() {
                out[c] = Point(x: start + unit * (Double(i) + 0.5), y: 27 + 54 * Double(r))
            }
        }
        return out
    }()

    let decoder = SwipeDecoder(predictor: Predictor(lexicon: sharedLexicon))

    /// A plausible human path: jittered key hits joined by a slightly bowed stroke.
    func swipe(_ word: String, noise: Double, rng: inout SplitMix) -> [Point] {
        var letters: [Character] = []
        for c in word where c.isLetter && letters.last != c { letters.append(c) }
        let hits = letters.map { c -> Point in
            let k = Self.keys[c]!
            return Point(x: k.x + rng.gaussian() * noise * Self.unit,
                         y: k.y + rng.gaussian() * noise * Self.unit * 0.8)
        }
        var path: [Point] = []
        for (a, b) in zip(hits, hits.dropFirst()) {
            let bow = rng.gaussian() * 0.15 * Self.unit
            for s in 0..<8 {
                let t = Double(s) / 8
                let bend = sin(t * .pi) * bow
                path.append(Point(x: a.x + (b.x - a.x) * t - bend * 0.3, y: a.y + (b.y - a.y) * t + bend))
            }
        }
        path.append(hits.last!)
        return path
    }

    func decode(_ path: [Point], _ context: WordContext = .unknown) -> [String] {
        decoder.decode(path: path, keys: Self.keys, keyWidth: Self.unit, context: context, limit: 3)
    }

    func testCleanSwipes() {
        var rng = SplitMix(seed: 1)
        for word in ["hello", "keyboard", "cipher", "reading", "people", "thanks", "question"] {
            XCTAssertEqual(decode(swipe(word, noise: 0, rng: &rng)).first, word)
        }
    }

    func testTapIsNotASwipe() {
        let k = Self.keys["g"]!
        XCTAssertEqual(decode([k, Point(x: k.x + 4, y: k.y + 2)]), [])
    }

    func testContextBreaksTiesBetweenIdenticalPaths() {
        var rng = SplitMix(seed: 2)
        let path = swipe("to", noise: 0, rng: &rng)
        XCTAssertEqual(decode(path, .after("going")).first, "to")
        XCTAssertTrue(decode(path).contains("too"))
    }

    /// Accuracy over the most common words with realistic noise. The thresholds pin the
    /// current quality so a regression fails loudly; paths that are identical after
    /// collapsing repeats ("to"/"too") count as a hit, since no decoder can split them.
    func testAccuracyOnCommonWords() {
        let lex = sharedLexicon
        let common = (0..<lex.count)
            .filter { let w = lex.word($0); return w.count >= 2 && w.allSatisfy(\.isLetter) }
            .sorted { lex.logFrequency($0) > lex.logFrequency($1) }
            .prefix(400)
        var rng = SplitMix(seed: 42)
        var top1 = 0, top3 = 0
        var misses: [String] = []
        for id in common {
            let word = lex.word(id)
            let result = decode(swipe(word, noise: 0.28, rng: &rng))
            let keys = lex.swipeKeys(id)
            let same = { (w: String) in lex.id(of: w).map { lex.swipeKeys($0) == keys } ?? false }
            if let first = result.first, same(first) { top1 += 1 } else if misses.count < 25 {
                misses.append("\(word)→\(result.first ?? "∅")")
            }
            if result.contains(where: same) { top3 += 1 }
        }
        let n = Double(common.count)
        print("swipe accuracy: top1 \(Double(top1) / n), top3 \(Double(top3) / n); misses: \(misses)")
        XCTAssertGreaterThanOrEqual(Double(top1) / n, 0.93)
        XCTAssertGreaterThanOrEqual(Double(top3) / n, 0.99)
    }

    func testDecodeIsFastEnough() {
        var rng = SplitMix(seed: 7)
        let paths = ["something", "information", "because", "through"].map { swipe($0, noise: 0.28, rng: &rng) }
        _ = decode(paths[0])  // builds the endpoint buckets
        let start = Date()
        for p in paths { _ = decode(p) }
        let perSwipe = Date().timeIntervalSince(start) / Double(paths.count)
        print("decode: \(Int(perSwipe * 1000)) ms per swipe")
        XCTAssertLessThan(perSwipe, 0.25)
    }
}

/// Deterministic RNG so accuracy numbers are reproducible.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gaussian() -> Double {
        let u = max(uniform(), 1e-12), v = uniform()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}

final class SuggestionRulesTests: XCTestCase {
    func testCaseOnlyChangesAreRecognised() {
        XCTAssertTrue(SuggestionRules.isCaseOnlyChange("A", of: "a"))
        XCTAssertTrue(SuggestionRules.isCaseOnlyChange("Will", of: "will"))
        XCTAssertTrue(SuggestionRules.isCaseOnlyChange("mark", of: "Mark"))
        XCTAssertFalse(SuggestionRules.isCaseOnlyChange("a", of: "a"))
        XCTAssertFalse(SuggestionRules.isCaseOnlyChange("I'm", of: "im"))
        XCTAssertFalse(SuggestionRules.isCaseOnlyChange("Paris", of: "paris ")) // different letters
        XCTAssertFalse(SuggestionRules.isCaseOnlyChange("teh", of: "the"))
    }
}
