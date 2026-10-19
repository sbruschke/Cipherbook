import XCTest
@testable import JournalCore

final class ShuffleSampleTests: XCTestCase {
    private let path = StackOps.shufflePath(count: 5, from: 1, to: 4, clearance: 280)

    func testEndpoints() {
        XCTAssertEqual(StackOps.sample(path, at: 0), path.first)
        XCTAssertEqual(StackOps.sample(path, at: 1), path.last)
        XCTAssertEqual(StackOps.sample(path, at: -3), path.first)
        XCTAssertEqual(StackOps.sample(path, at: 9), path.last)
    }

    func testInterpolatesOffsetAndLiftButStepsLayer() {
        // Midway between t=0.00 (offset 0, layer 1) and t=0.30 (offset 280, layer 1) with easing off at the midpoint.
        let s = StackOps.sample(path, at: 0.15)
        XCTAssertEqual(s.offsetX, 140, accuracy: 1e-9)
        XCTAssertEqual(s.layer, 1)
        // Between t=0.30 (layer 1, lift 0) and t=0.45 (layer 4, lift 1): layer is still the earlier one.
        let m = StackOps.sample(path, at: 0.375)
        XCTAssertEqual(m.layer, 1); XCTAssertEqual(m.lift, 0.5, accuracy: 1e-9)
        // At/after the later keyframe the layer has switched, and the page is still clear of the stack.
        let after = StackOps.sample(path, at: 0.45)
        XCTAssertEqual(after.layer, 4); XCTAssertGreaterThanOrEqual(after.offsetX, 280)
    }

    func testLayerChangesOnlyWhileClear() {
        var prev = StackOps.sample(path, at: 0)
        for i in 1...200 {
            let cur = StackOps.sample(path, at: Double(i) / 200)
            if cur.layer != prev.layer {
                XCTAssertGreaterThanOrEqual(prev.offsetX, 280 - 1e-9); XCTAssertGreaterThanOrEqual(cur.offsetX, 280 - 1e-9)
            }
            prev = cur
        }
    }

    func testEmptyPath() {
        XCTAssertEqual(StackOps.sample([], at: 0.5), ShuffleKeyframe(t: 0, offsetX: 0, layer: 0, lift: 0))
    }
}
