// swift-tools-version:6.0
import PackageDescription

// PackDeckKit — pure-domain core for Pack Deck.
// No UI, no networking, no Apple-only frameworks: Linux-testable by design.
let package = Package(
    name: "PackDeckKit",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(name: "PackDeckKit", targets: ["PackDeckKit"]),
    ],
    targets: [
        .target(name: "PackDeckKit"),
        .testTarget(name: "PackDeckKitTests", dependencies: ["PackDeckKit"]),
    ]
)
