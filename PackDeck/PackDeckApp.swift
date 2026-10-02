import SwiftUI

/// Pack Deck app entry point.
///
/// iPhone-only by user directive 2026-09-15 (`TARGETED_DEVICE_FAMILY = 1`
/// in every build configuration; CI enforces it pre- and post-build).
/// Zero-network by construction: no network APIs anywhere in app or
/// package sources — CI enforces an empty-allowlist scan.
@main
struct PackDeckApp: App {
    @State private var store: AppStore

    init() {
        _store = State(initialValue: Self.makeStore())
    }

    /// App entry always runs on the main thread, so the main-actor assertion
    /// is honest; the nonisolated hop exists only because Swift 6 evaluates
    /// property initializers in a nonisolated context.
    nonisolated private static func makeStore() -> AppStore {
        MainActor.assumeIsolated { AppStore() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
