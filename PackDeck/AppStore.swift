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
    private(set) var trips: [Trip] = []
    private(set) var tripItems: [TripItem] = []
    private(set) var transitions: [PackTransition] = []

    func status(for item: TripItem) -> ItemStatus {
        transitions.last(where: { $0.tripItemID == item.id })?.toStatus ?? .planned
    }

    func summary(for trip: Trip) -> PackSummary? {
        // Derive from observed mirrors, not a fresh database read: SwiftUI
        // otherwise sees no dependency on transitions and leaves the progress
        // label stale even while item status/Undo update correctly.
        (try? PackLedger(transitions: transitions))?.summary(for: trip.id, items: tripItems)
    }

    @discardableResult
    func createTrip(name: String, nights: Int?, laundry: LaundryAccess,
                    tags: [String], kits: [KitTemplate], adHoc: [AdHocItem]) -> Trip? {
        do {
            let plan = try TripPlanner().plan(name: name, durationNights: nights,
                                              laundryAccess: laundry, activityTags: tags,
                                              kits: kits, adHocItems: adHoc)
            try store.createTrip(plan.trip, items: plan.items)
            reload()
            return plan.trip
        } catch {
            lastError = "Could not create trip: \(error.localizedDescription)"
            return nil
        }
    }

    func setStatus(_ status: ItemStatus, for item: TripItem) {
        do {
            try store.recordTransition(tripItemID: item.id, to: status)
            reload()
        } catch {
            lastError = "Could not change status: \(error.localizedDescription)"
        }
    }

    func undo(for item: TripItem) {
        do {
            try store.undoTransition(tripItemID: item.id)
            reload()
        } catch {
            lastError = "Could not undo: \(error.localizedDescription)"
        }
    }

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
        if ProcessInfo.processInfo.arguments.contains("--seed-accessibility-fixture") {
            seedAccessibilityFixture()
        }
    }

    /// Deterministic local-only fixture for accessibility journeys. Never
    /// replaces user data; only the UI-test runner passes this argument.
    private func seedAccessibilityFixture() {
        guard !kits.contains(where: { $0.name == "Long weekend carry-on essentials" }) else { return }
        let kit = KitTemplate(name: "Long weekend carry-on essentials",
                              notes: "Charger, travel adapter, and daily medication",
                              items: [KitItem(name: "Travel adapter", baseQuantity: 1)])
        guard save(kit) else { return }
        _ = createTrip(name: "Long weekend mountain trip", nights: 3,
                       laundry: .unknown, tags: [], kits: [kit], adHoc: [])
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
            let snapshot = try store.snapshot()
            kits = snapshot.kits
            trips = snapshot.trips
            tripItems = snapshot.tripItems
            transitions = snapshot.transitions
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

    // MARK: - Backup / export (issue #6, zero network by construction)

    /// Versioned JSON backup of the entire local dataset.
    func backupJSON() throws -> Data {
        try BackupCodec.encode(store.snapshot())
    }

    /// CSV checklist of every trip item with its current status.
    func checklistCSV() throws -> Data {
        ChecklistCSV.encode(try store.snapshot())
    }

    /// Validates a backup payload and summarizes it WITHOUT mutating anything,
    /// so the UI can preview counts before the user confirms a replace.
    func previewBackup(_ data: Data) throws -> BackupCodec.Preview {
        try BackupCodec.preview(data)
    }

    /// Replaces the whole dataset from a (previewed) backup, transactionally.
    func restoreBackup(_ data: Data) throws {
        try BackupCodec.restore(data, into: store)
        reload()
    }
}
