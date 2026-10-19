import XCTest
@testable import JournalCore

final class PaginatorTests: XCTestCase {
    private func fits10(_ s: String) -> Bool { s.count <= 10 }

    func testEmptyTextIsOneEmptyPage() {
        XCTAssertEqual(Paginator.paginate("", fits: fits10), [""])
    }

    func testSplitsAtWordBoundariesAndIsLossless() {
        let pages = Paginator.paginate("hello world foo bar", fits: fits10)
        XCTAssertEqual(pages, ["hello ", "world foo ", "bar"])
        XCTAssertEqual(pages.joined(), "hello world foo bar")
    }

    func testShortTextIsOnePage() {
        XCTAssertEqual(Paginator.paginate("hi there", fits: fits10), ["hi there"])
    }

    func testHugeWordIsSplitByCharacters() {
        let word = String(repeating: "a", count: 25)
        let pages = Paginator.paginate(word, fits: fits10)
        XCTAssertEqual(pages.joined(), word)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 10 })
        XCTAssertEqual(pages.count, 3)
    }

    func testNeverSplitsGraphemeClusters() {
        // Family emoji (ZWJ sequence), flag, e + combining acute: each is ONE Character.
        let text = String(repeating: "👨‍👩‍👧‍👦🇺🇸e\u{301}", count: 12)
        let pages = Paginator.paginate(text, fits: fits10)
        XCTAssertEqual(pages.joined(), text)
        for p in pages { XCTAssertEqual(String(p).count, p.count) } // re-parse is stable
        XCTAssertTrue(pages.allSatisfy { $0.count <= 10 })
    }

    func testNewlinesAndRepeatedSpacesPreserved() {
        let text = "one\n\n  two   three\nfour five six seven"
        XCTAssertEqual(Paginator.paginate(text, fits: fits10).joined(), text)
    }

    func testSingleGraphemeThatNeverFitsStillTerminates() {
        let pages = Paginator.paginate("abc", fits: { _ in false })
        XCTAssertEqual(pages.joined(), "abc")
        XCTAssertEqual(pages.count, 3)
    }

    func testFitScale() {
        XCTAssertEqual(fitScale(contentHeight: 100, available: 200), 1)
        XCTAssertEqual(fitScale(contentHeight: 200, available: 150), 0.75, accuracy: 1e-9)
        XCTAssertEqual(fitScale(contentHeight: 1000, available: 100), 0.7, accuracy: 1e-9)
        XCTAssertEqual(fitScale(contentHeight: 0, available: 100), 1)
        XCTAssertEqual(fitScale(contentHeight: 100, available: 0), 0.7, accuracy: 1e-9)
    }
}
