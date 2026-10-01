// swift-tools-version:6.0
import PackageDescription

// PackDeckStore — persistence layer for Pack Deck (GRDB/SQLite).
// Pure data package, Linux-testable by design. Zero-network by
// construction: GRDB/SQLite is a local storage engine only.
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
        // Pinned exact: the CI and native lanes must build the same GRDB
        // graph. GRDB vendors its own SQLite; it performs no networking.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
    ],
    targets: [
        .target(
            name: "PackDeckStore",
            dependencies: [
                "PackDeckKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "PackDeckStoreTests",
            dependencies: ["PackDeckStore", "PackDeckKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
