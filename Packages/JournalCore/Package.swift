// swift-tools-version:5.9
import PackageDescription

// Model, appearance, wall layout, shuffle paths, pagination and sync merge for the Journal.
// Foundation only, so `swift test` runs on Linux as well as in the Xcode build.
let package = Package(
    name: "JournalCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "JournalCore", targets: ["JournalCore"])],
    targets: [
        .target(name: "JournalCore"),
        .testTarget(name: "JournalCoreTests", dependencies: ["JournalCore"]),
    ]
)
