import XCTest
@testable import JournalCore

final class AppearanceTests: XCTestCase {
    func testDeterministic() {
        XCTAssertEqual(PageLook.make(seed: 42, preset: .aged), PageLook.make(seed: 42, preset: .aged))
    }

    func testDifferentSeedsGiveDifferentOutlines() {
        var seen = Set<[Pt]>()
        for s in 0..<300 { seen.insert(PageLook.make(seed: UInt64(s), preset: .aged).outline) }
        XCTAssertEqual(seen.count, 300)
    }

    func testOutlineShapeAndBounds() {
        for s in 0..<200 {
            let look = PageLook.make(seed: UInt64(s) &* 7919, preset: .aged)
            XCTAssertEqual(look.outline.count, 4 * PageLook.edgePointsPerSide)
            for p in look.outline {
                XCTAssertGreaterThanOrEqual(p.x, -0.011); XCTAssertLessThanOrEqual(p.x, 1.011)
                XCTAssertGreaterThanOrEqual(p.y, -0.011); XCTAssertLessThanOrEqual(p.y, 1.011)
            }
            XCTAssertTrue((0.96...1.04).contains(look.widthScale))
            XCTAssertTrue((-3...3).contains(look.rotation))
            XCTAssertEqual(look.cornerCurl.count, 4)
        }
    }

    func testWornPresetsHaveMoreDamageOnAverage() {
        func avgDamage(_ p: Preset) -> Double {
            let n = 400
            let total = (0..<n).reduce(0.0) { acc, s in
                let l = PageLook.make(seed: UInt64(s), preset: p)
                return acc + Double(l.stains.count + l.creases.count)
            }
            return total / Double(n)
        }
        XCTAssertGreaterThan(avgDamage(.aged), avgDamage(.vellum))
    }

    func testPresetsHaveStyles() {
        for p in Preset.allCases {
            XCTAssertTrue(p.style.baseHex.hasPrefix("#"))
            XCTAssertTrue((0...1).contains(p.style.wear))
        }
    }

    func testFastenerLookDeterministicAndPlausible() {
        for kind in FastenerKind.allCases {
            let a = FastenerLook.make(kind: kind, seed: 99)
            XCTAssertEqual(a, FastenerLook.make(kind: kind, seed: 99))
            XCTAssertNotEqual(a, FastenerLook.make(kind: kind, seed: 100))
            XCTAssertTrue((0...1).contains(a.position.x)); XCTAssertTrue((0...0.4).contains(a.position.y))
        }
    }
}
