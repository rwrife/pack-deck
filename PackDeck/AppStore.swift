import Foundation
import Observation
import PackDeckKit
import PackDeckStore

/// MainActor-isolated, observable facade over the persistence store.
///
/// The app layer talks to `PackDeckStore` through this type so SwiftUI views
/// can observe kit-library state reactively. `PackDeckStore` is thread-safe
/// (`@unchecked Sendable` over GRDB's synchronized reader/writer) and is used
/// here from the main actor only.
@Observable
@MainActor
final class AppStore {
    /// Underlying GRDB-backed store (never exposed to views directly).
    let store: PackDeckStore

    /// Reactive mirror of the persisted kit list.
    private(set) var kits: [KitTemplate] = []

    /// Last user-facing failure message; views surface it in an alert and
    /// clear it on dismissal. Persistence failures must never crash the app
    /// or silently lose edits.
    var lastError: String?

    /// Opens the app-container database. A failure here is unrecoverable —
    /// the app cannot function without its local store.
    init() {
        let url = URL.documentsDirectory
            .appending(path: PackDeckStore.defaultDatabaseFilename)
        if ProcessInfo.processInfo.arguments.contains("--reset-store") {
            AppStore.resetDatabase(nextTo: url)
        }
        do {
            self.store = try PackDeckStore(url: url)
        } catch {
            fatalError("Failed to open PackDeckStore at \(url.path): \(error)")
        }
        reload()
        if ProcessInfo.processInfo.arguments.contains("--seed-reference-trip") {
            seedReferenceTrip()
        }
    }

    /// XCUITest seam: `--seed-reference-trip` creates one trip whose
    /// build-time provenance references every existing kit, so the delete-
    /// warning flow can be exercised end-to-end before the trip-builder UI
    /// (issue #5) exists. Never triggered by normal app launches.
    private func seedReferenceTrip() {
        let kitIDs = kits.map(\.id)
        guard !kitIDs.isEmpty else { return }
        let trip = Trip(
            name: "Seeded Reference Trip",
            durationNights: 2,
            sourceKitIDs: kitIDs
        )
        try? store.saveTrip(trip)
        reload()
    }

    /// XCUITest seam: `--reset-store` wipes the on-disk database (and WAL
    /// sidecars) before opening, so UI-test runs start from a deterministic
    /// empty state. Never passed by the shipping app itself.
    private static func resetDatabase(nextTo url: URL) {
        let fileManager = FileManager.default
        let base = url.deletingLastPathComponent()
        for name in [
            PackDeckStore.defaultDatabaseFilename,
            PackDeckStore.defaultDatabaseFilename + "-wal",
            PackDeckStore.defaultDatabaseFilename + "-shm",
        ] {
            try? fileManager.removeItem(at: base.appending(path: name))
        }
    }

    /// Test seam: wrap an already-opened store (in-memory for previews/tests).
    init(store: PackDeckStore) {
        self.store = store
        reload()
    }

    /// Refreshes the kit mirror from a single consistent snapshot.
    func reload() {
        do {
            kits = try store.snapshot().kits
            lastError = nil
        } catch {
            lastError = "Could not read your kits: \(error.localizedDescription)"
        }
    }

    /// Persists (insert or replace) a kit, then refreshes the mirror.
    /// Returns true on success; on failure sets `lastError` and returns false.
    @discardableResult
    func save(_ kit: KitTemplate) -> Bool {
        do {
            try store.saveKit(kit)
            reload()
            return true
        } catch {
            lastError = "Could not save \u{201C}\(kit.name)\u{201D}: \(error.localizedDescription)"
            return false
        }
    }

    /// Deletes a kit and its items, then refreshes the mirror.
    /// Returns true on success; on failure sets `lastError` and returns false.
    @discardableResult
    func delete(id: UUID) -> Bool {
        do {
            try store.deleteKit(id: id)
            reload()
            return true
        } catch {
            lastError = "Could not delete the kit: \(error.localizedDescription)"
            return false
        }
    }

    /// Trips that still list `kitID` in their build-time provenance. Empty when
    /// the kit is unused — the UI uses this to decide whether to warn on delete.
    func tripsReferencing(kitID: UUID) -> [Trip] {
        (try? store.tripsReferencing(kitID: kitID)) ?? []
    }
}
