// swift-tools-version:5.9
import PackageDescription

// Word prediction and swipe decoding for the CipherKeys keyboard. Foundation only,
// so `swift test` runs on Linux as well as in the Xcode build.
let package = Package(
    name: "KeyboardCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "KeyboardCore", targets: ["KeyboardCore"])],
    targets: [
        .target(name: "KeyboardCore"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ]
)
