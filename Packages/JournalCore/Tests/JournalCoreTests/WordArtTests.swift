import XCTest
@testable import JournalCore

final class WordArtTests: XCTestCase {
    func testLegacyTableMatchesOriginal() {
        XCTAssertEqual(LegacyVectors.vectors.count, 93)
        XCTAssertEqual(LegacyVectors.vectors["e"], V3(x: 5, y: 0, z: 0))
        XCTAssertEqual(LegacyVectors.vectors["t"], V3(x: 4, y: 3, z: 0))
        XCTAssertEqual(LegacyVectors.vectors[" "]!.y, -2 * 6.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(LegacyVectors.vectors["E"]!.x, 5 * 3.0.squareRoot() / 3, accuracy: 1e-12)
        XCTAssertNotNil(LegacyVectors.vectors["\\"]); XCTAssertNotNil(LegacyVectors.vectors["\""])
        for (_, v) in LegacyVectors.vectors {    // every vector has length 5 or ~4.9–5.0 (the table is near-unit-sphere)
            let m = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            XCTAssertTrue((4.9...5.1).contains(m), "\(v) has length \(m)")
        }
    }

    func testSplitWords() {
        XCTAssertEqual(WordArt.splitWords("Hello  world\nfoo\t bar "), ["Hello", "world", "foo", "bar"])
        XCTAssertEqual(WordArt.splitWords("   "), [])
    }

    func testEmptyAndUnmappable() {
        XCTAssertTrue(WordArt.make(text: "", seed: 1).isEmpty)
        XCTAssertTrue(WordArt.make(text: "   \n ", seed: 1).isEmpty)
        XCTAssertTrue(WordArt.make(text: "🙂🙂 日本語", seed: 1).isEmpty)
    }

    func testUnmappedCharactersAreSkipped() {
        let a = WordArt.make(text: "hello", seed: 9)
        let b = WordArt.make(text: "he🙂llo", seed: 9)
        XCTAssertEqual(a, b)
    }

    func testDeterministicAndSeedAndTextSensitive() {
        let t = "the quick brown fox jumps over the lazy dog"
        XCTAssertEqual(WordArt.make(text: t, seed: 5), WordArt.make(text: t, seed: 5))
        XCTAssertNotEqual(WordArt.make(text: t, seed: 5), WordArt.make(text: t, seed: 6))
        XCTAssertNotEqual(WordArt.make(text: t, seed: 5), WordArt.make(text: t + " again", seed: 5))
    }

    func testWhitespaceLayoutDoesNotMatter() {
        XCTAssertEqual(WordArt.make(text: "a b c", seed: 3), WordArt.make(text: "a   b\n\nc ", seed: 3))
    }

    func testStrokeCountAndTones() {
        let d = WordArt.make(text: "ab cde f", seed: 4)
        XCTAssertEqual(d.strokes.count, 6)                   // one stroke per mappable character
        XCTAssertEqual(Set(d.strokes.map(\.wordIndex)), [0, 1, 2])
        XCTAssertEqual(d.strokes.filter { $0.wordIndex == 0 }.first?.tone, 0)
        XCTAssertEqual(d.strokes.filter { $0.wordIndex == 2 }.first?.tone, 1)
        XCTAssertEqual(WordArt.make(text: "solo", seed: 4).strokes.first?.tone, 1)
    }

    func testWordsAreLayeredFromACommonOrigin() {
        let d = WordArt.make(text: "alpha beta gamma", seed: 11)
        let firsts = d.strokes.filter { s in d.strokes.first { $0.wordIndex == s.wordIndex }! == s }.map(\.a)
        XCTAssertEqual(firsts.count, 3)
        for p in firsts { XCTAssertEqual(p, firsts[0]) }
    }

    func testChainsAreTipToTail() {
        let d = WordArt.make(text: "hello", seed: 2)
        for (s, n) in zip(d.strokes, d.strokes.dropFirst()) { XCTAssertEqual(s.b, n.a) }
    }

    func testEverythingStaysOnThePage() {
        let texts = ["a", "hello world", String(repeating: "supercalifragilistic ", count: 40), "E T A O I N S H R D L C U"]
        for (i, t) in texts.enumerated() {
            for seed in 0..<40 {
                let d = WordArt.make(text: t, seed: UInt64(seed) &* 2654435761 &+ UInt64(i))
                for s in d.strokes {
                    for p in [s.a, s.b, s.c] + [s.barbL, s.barbR].compactMap({ $0 }) {
                        let q = d.pagePoint(p)
                        XCTAssertTrue((-1e-9...1 + 1e-9).contains(q.x) && (-1e-9...1 + 1e-9).contains(q.y),
                                      "off page: \(q) seed \(seed) text \(i)")
                    }
                }
            }
        }
    }

    func testCapsWordsAndCharacters() {
        let many = (0..<500).map { _ in "word" }.joined(separator: " ")
        XCTAssertEqual(Set(WordArt.make(text: many, seed: 1).strokes.map(\.wordIndex)).count, WordArt.maxWords)
        let long = String(repeating: "e", count: 500)
        XCTAssertEqual(WordArt.make(text: long, seed: 1).strokes.count, WordArt.maxCharsPerWord)
    }

    func testPlacementVariesBySeed() {
        var centers = Set<Pt>()
        for s in 0..<50 { centers.insert(WordArt.make(text: "hello", seed: UInt64(s)).center) }
        XCTAssertEqual(centers.count, 50)
    }

    func testPlacementIsTextIndependentAndFrameContainsEveryStroke() {
        for seed in 0..<60 {
            let pl = WordArt.placement(seed: UInt64(seed))
            let d = WordArt.make(text: "hello brave new world", seed: UInt64(seed))
            XCTAssertEqual(d.center, pl.center); XCTAssertEqual(d.size, pl.size); XCTAssertEqual(d.rotation, pl.rotation)
            let f = pl.frame
            XCTAssertGreaterThanOrEqual(f.minX, 0); XCTAssertLessThanOrEqual(f.maxX, 1)
            XCTAssertGreaterThanOrEqual(f.minY, 0); XCTAssertLessThanOrEqual(f.maxY, 1)
            for s in d.strokes {
                for p in [s.a, s.b, s.c] + [s.barbL, s.barbR].compactMap({ $0 }) {
                    let q = d.pagePoint(p)
                    XCTAssertTrue(q.x >= f.minX - 1e-9 && q.x <= f.maxX + 1e-9 && q.y >= f.minY - 1e-9 && q.y <= f.maxY + 1e-9)
                }
            }
        }
    }

    func testEarlierWordShapesSurviveAppendingAWord() {
        let a = WordArt.make(text: "hello", seed: 8)
        let b = WordArt.make(text: "hello world", seed: 8)
        // Normalisation may rescale/shift, but the bend/width/arrowhead draws are keyed per stroke.
        let wa = a.strokes.map(\.widthA), wb = b.strokes.filter { $0.wordIndex == 0 }.map(\.widthA)
        XCTAssertEqual(wa, wb)
    }
}
