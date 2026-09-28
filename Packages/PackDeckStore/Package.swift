// swift-tools-version:6.0
import PackageDescription

// PackDeckStore — persistence layer for Pack Deck (GRDB/SQLite stub in M1).
// Pure domain storage package, Linux-testable by design.
let package = Package(
    name: "PackDeckStore",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(name: "PackDeckStore", targets: ["PackDeckStore"]),
    ],
    dependencies: [
        .package(path: "../PackDeckKit"),
    ],
    targets: [
        .target(name: "PackDeckStore", dependencies: ["PackDeckKit"]),
        .testTarget(name: "PackDeckStoreTests", dependencies: ["PackDeckStore"]),
    ]
)
