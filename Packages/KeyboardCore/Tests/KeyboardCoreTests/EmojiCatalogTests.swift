import Foundation
import XCTest
@testable import KeyboardCore

final class EmojiCatalogTests: XCTestCase {
    static let catalog: EmojiCatalog = {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Keyboard/Resources")
        return try! EmojiCatalog(index: resources.appendingPathComponent("emoji-index.json"),
                                 images: resources.appendingPathComponent("emoji-images.dat"))
    }()
    var catalog: EmojiCatalog { Self.catalog }

    func testCategoriesFollowApplesOrder() {
        XCTAssertEqual(catalog.categories.first, "Smileys & People")
        XCTAssertEqual(catalog.categories.last, "Flags")
        XCTAssertEqual(catalog.emoji.first?.text, "😀")
        XCTAssertEqual(catalog.emoji.map(\.category), catalog.emoji.map(\.category).sorted(),
                       "categories are contiguous")
        for c in catalog.categories.indices { XCTAssertNotNil(catalog.firstIndex(ofCategory: c)) }
    }

    func testImagesAreWebP() throws {
        let thumbs = try XCTUnwrap(catalog.lookup("👍")).emoji
        let data = catalog.imageData(try XCTUnwrap(thumbs.image))
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(data.dropFirst(8).prefix(4), Data("WEBP".utf8))
    }

    func testSkinTonesTypeStandardStrings() throws {
        let thumbs = try XCTUnwrap(catalog.lookup("👍")).emoji
        XCTAssertEqual(thumbs.tones.map(\.text), ["👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿"])
        XCTAssertTrue(thumbs.tones.allSatisfy { $0.image != nil })
        let dark = try XCTUnwrap(catalog.lookup("👍🏿"))
        XCTAssertEqual(dark.emoji.text, "👍")
        XCTAssertEqual(dark.variant, 5)
        XCTAssertTrue(try XCTUnwrap(catalog.lookup("😀")).emoji.tones.isEmpty)
    }

    func testFlagsFallBackToSystemArt() throws {
        let canada = try XCTUnwrap(catalog.lookup("🇨🇦")).emoji
        XCTAssertNil(canada.image)
        XCTAssertEqual(canada.category, catalog.categories.firstIndex(of: "Flags"))
    }

    func testTypedStringsAreFullyQualified() throws {
        // Heart needs its variation selector to render as emoji rather than text.
        XCTAssertEqual(try XCTUnwrap(catalog.lookup("❤️")).emoji.text.unicodeScalars.map(\.value), [0x2764, 0xFE0F])
    }

    func testSearch() {
        XCTAssertEqual(catalog.search("thumbs").first?.text, "👍")
        XCTAssertEqual(catalog.search("crying").first?.text, "😢")
        XCTAssertTrue(catalog.search("cry").contains { $0.text == "😭" })
        XCTAssertTrue(catalog.search("canada").contains { $0.text == "🇨🇦" })
        XCTAssertTrue(catalog.search("   ").isEmpty)
        XCTAssertTrue(catalog.search("zzqqxx").isEmpty)
        XCTAssertEqual(catalog.search("heart eyes").first?.text, "😍")
    }

    func testRecents() {
        var list: [String] = []
        for e in ["😀", "👍", "😀", "👍🏽"] { list = EmojiRecents.recording(e, in: list) }
        XCTAssertEqual(list, ["👍🏽", "😀", "👍"])
        for i in 0..<100 { list = EmojiRecents.recording("x\(i)", in: list) }
        XCTAssertEqual(list.count, EmojiRecents.capacity)
    }
}
