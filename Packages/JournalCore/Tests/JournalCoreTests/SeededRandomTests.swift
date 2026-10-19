import XCTest
@testable import JournalCore

final class SeededRandomTests: XCTestCase {
    func testKnownSplitMix64Vector() {
        // Reference output of splitmix64 with seed 0.
        var g = SplitMix64(seed: 0)
        XCTAssertEqual(g.next(), 0xE220A8397B1DCDAF)
    }

    func testSameSeedSameSequence() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        for _ in 0..<50 { XCTAssertEqual(a.next(), b.next()) }
    }

    func testUnitInRange() {
        var g = SplitMix64(seed: 7)
        for _ in 0..<1000 {
            let u = g.unit()
            XCTAssertGreaterThanOrEqual(u, 0); XCTAssertLessThan(u, 1)
        }
    }

    func testIntRangeInclusive() {
        var g = SplitMix64(seed: 9)
        var seen = Set<Int>()
        for _ in 0..<500 { seen.insert(g.int(2...4)) }
        XCTAssertEqual(seen, [2, 3, 4])
    }

    func testDeriveSeedDiffersBySalt() {
        XCTAssertNotEqual(deriveSeed(1, 1), deriveSeed(1, 2))
        XCTAssertEqual(deriveSeed(1, 1), deriveSeed(1, 1))
    }
}
