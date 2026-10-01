import Foundation
import GRDB
import Testing
@testable import PackDeckStore
import PackDeckKit

// Deterministic fixture ids/timestamps for all persistence tests.
private let kitID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
private let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let tripID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let tripItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

/// Builds a canonical kit + trip + trip-item + transition dataset.
///
/// The `PackDeckDataset` initializer enforces ledger replay validity for
/// every fixture dataset, and the store re-validates on read.
struct Fixture {
    static func dataset(transitioned: Bool = true) throws -> PackDeckDataset {
        let kitItem = KitItem(id: itemID, name: "Socks", baseQuantity: 1, category: "clothing")
        let kit = KitTemplate(
            id: kitID,
            name: "Weekender",
            notes: "Short trips",
            items: [kitItem],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let trip = Trip(
            id: tripID,
            name: "Weekend",
            durationNights: 2,
            laundryAccess: .unavailable,
            activityTags: ["hiking", "city"],
            sourceKitIDs: [kit.id],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let recommendation = RecommendationEngine().recommend(for: kitItem, on: trip)
        let tripItem = TripItem(
            id: tripItemID,
            tripID: trip.id,
            sourceKitID: kit.id,
            name: kitItem.name,
            category: kitItem.category,
            recommendation: recommendation,
            createdAt: fixedDate
        )
        var transitions: [PackTransition] = []
        if transitioned {
            transitions = [
                PackTransition(
                    tripItemID: tripItem.id,
                    fromStatus: .planned,
                    toStatus: .packed,
                    occurredAt: fixedDate
                ),
            ]
        }
        return try PackDeckDataset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            kits: [kit],
            trips: [trip],
            tripItems: [tripItem],
            transitions: transitions
        )
    }
}

@Suite("PackDeckStore on-disk persistence")
struct OnDiskStoreTests {
    private func makeStoreURL() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("packdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(PackDeckStore.defaultDatabaseFilename)
    }

    @Test("on-disk database round-trips a full dataset and survives reopen")
    func onDiskRoundTrip() throws {
        let url = try makeStoreURL()
        let dataset = try Fixture.dataset()

        do {
            let store = try PackDeckStore(url: url)
            try store.replaceAll(with: dataset)
        }

        // Reopen: everything must read back exactly (fresh connection).
        let store = try PackDeckStore(url: url)
        let snapshot = try store.snapshot()
        #expect(snapshot.dataset == dataset)
        #expect(snapshot.currentStatus(for: tripItemID) == .packed)

        let summary = try snapshot.summary(for: tripID)
        #expect(summary.totalItems == 1)
        #expect(summary.packed == 1)
        #expect(summary.completionRatio == 1.0)

        try FileManager.default.removeItem(
            at: url.deletingLastPathComponent()
        )
    }

    @Test("schema lands at v2 and both migrations are recorded")
    func migrationHistory() throws {
        let url = try makeStoreURL()
        let store = try PackDeckStore(url: url)
        let applied = try store.appliedMigrations()
        #expect(applied == ["v1-initial-schema", "v2-item-position"])
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@Suite("PackDeckStore transactions")
struct TransactionTests {
    @Test("a failed write rolls back the whole transaction (no partial state)")
    func failedWriteRollsBack() throws {
        let store = try PackDeckStore.inMemory()
        let dataset = try Fixture.dataset()
        try store.replaceAll(with: dataset)

        // Second item in the batch references a missing trip: the store
        // must abort mid-transaction, and the rollback must undo the
        // already-inserted first item too.
        let engine = RecommendationEngine()
        let rec = engine.recommend(
            for: KitItem(name: "Toothbrush", baseQuantity: 1),
            on: Trip(name: "t", durationNights: 1, laundryAccess: .unavailable)
        )
        let validItem = TripItem(
            id: UUID(),
            tripID: tripID,
            name: "Valid",
            recommendation: rec
        )
        let orphanItem = TripItem(
            id: UUID(),
            tripID: UUID(), // no such trip
            name: "Orphan",
            recommendation: rec
        )

        #expect(throws: PackDeckStoreError.tripNotFound(orphanItem.tripID)) {
            try store.addTripItems([validItem, orphanItem])
        }

        let snapshot = try store.snapshot()
        #expect(snapshot.tripItems.count == dataset.tripItems.count)
        #expect(snapshot.tripItems.contains(dataset.tripItems[0]))
    }

    @Test("transition ledger validation rejects invalid appends without DB change")
    func invalidTransitionRejected() throws {
        let store = try PackDeckStore.inMemory()
        try store.replaceAll(with: try Fixture.dataset(transitioned: false))

        // planned -> packed is legal.
        try store.recordTransition(tripItemID: tripItemID, to: .packed, at: fixedDate)

        // Duplicate append rejected by the ledger, nothing written.
        #expect(throws: PackLedgerError.alreadyInStatus(.packed)) {
            try store.recordTransition(tripItemID: tripItemID, to: .packed, at: fixedDate)
        }
        #expect(throws: PackLedgerError.cannotRevertToPlanned) {
            try store.recordTransition(tripItemID: tripItemID, to: .planned, at: fixedDate)
        }

        let snapshot = try store.snapshot()
        #expect(snapshot.transitions.count == 1)
        #expect(snapshot.currentStatus(for: tripItemID) == .packed)
    }

    @Test("transition for unknown trip item fails with tripItemNotFound")
    func transitionUnknownItem() throws {
        let store = try PackDeckStore.inMemory()
        #expect(throws: PackDeckStoreError.tripItemNotFound(itemID)) {
            try store.recordTransition(tripItemID: itemID, to: .packed)
        }
    }

    @Test("deleting a trip cascades its items and their ledger events")
    func tripDeleteCascades() throws {
        let store = try PackDeckStore.inMemory()
        try store.replaceAll(with: try Fixture.dataset())

        try store.deleteTrip(id: tripID)
        let snapshot = try store.snapshot()
        #expect(snapshot.trips.isEmpty)
        #expect(snapshot.tripItems.isEmpty)
        #expect(snapshot.transitions.isEmpty)
    }

    @Test("deleting a kit leaves trip provenance untouched")
    func kitDeleteKeepsTripProvenance() throws {
        let store = try PackDeckStore.inMemory()
        try store.replaceAll(with: try Fixture.dataset())

        let referrers = try store.tripsReferencing(kitID: kitID)
        #expect(referrers.map(\.id) == [tripID])

        try store.deleteKit(id: kitID)
        let snapshot = try store.snapshot()
        #expect(snapshot.kits.isEmpty)
        // Kits are copied into trips at build time, not live-linked.
        #expect(snapshot.trips.first?.sourceKitIDs == [kitID])
        #expect(snapshot.tripItems.first?.sourceKitID == kitID)
    }

    @Test("kit save replaces items wholesale preserving order")
    func kitReplaceReordersItems() throws {
        let store = try PackDeckStore.inMemory()
        let first = KitTemplate(
            id: kitID,
            name: "Weekender",
            items: [
                KitItem(id: itemID, name: "Socks", baseQuantity: 1),
                KitItem(id: UUID(), name: "Charger", baseQuantity: 2),
            ],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try store.saveKit(first)

        var second = first
        second.name = "Weekender v2"
        second.items = Array(first.items.reversed())
        second.updatedAt = fixedDate.addingTimeInterval(60)
        try store.saveKit(second)

        let snapshot = try store.snapshot()
        #expect(snapshot.kits.count == 1)
        let kit = try #require(snapshot.kits.first)
        #expect(kit.name == "Weekender v2")
        #expect(kit.items.map(\.name) == ["Charger", "Socks"])
    }
}

@Suite("PackDeckStore migration fixtures")
struct MigrationFixtureTests {
    private func legacyDatabase() throws -> DatabaseQueue {
        let url = try #require(
            Bundle.module.url(forResource: "legacy_schema_v1", withExtension: "sql", subdirectory: "Fixtures"),
            "legacy schema fixture missing from test bundle"
        )
        let legacyDDL = try String(contentsOf: url, encoding: .utf8)
        let queue = try DatabaseQueue()
        try queue.write { writer in
            for statement in Schema.statements(in: legacyDDL) { try writer.execute(sql: statement) }

            // grdb_migrations table as created by the migrator at v1 so the
            // store recognizes a legacy database and applies only v2.
            try writer.execute(sql: """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)
            """)
            try writer.execute(sql: """
            INSERT INTO grdb_migrations (identifier) VALUES ('v1-initial-schema')
            """)

            // Seed legacy rows in v1 column order (rowid order defines
            // backfill order for the v2 position column).
            try writer.execute(
                sql: "INSERT INTO store_meta (key, value) VALUES (?, ?)",
                arguments: [Schema.datasetIDKey, UUID(uuidString: "00000000-0000-0000-0000-000000000006")!.uuidString]
            )
            try writer.execute(
                sql: """
                INSERT INTO kits (id, schema_major, schema_minor, name, notes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [kitID.uuidString, 1, 0, "Weekender", "Short trips",
                            fixedDate.timeIntervalSince1970, fixedDate.timeIntervalSince1970]
            )
            try writer.execute(
                sql: """
                INSERT INTO kit_items (id, kit_id, schema_major, schema_minor, name, base_quantity, category)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [itemID.uuidString, kitID.uuidString, 1, 0, "Socks", 1, "clothing"]
            )
            try writer.execute(
                sql: """
                INSERT INTO trips (id, schema_major, schema_minor, name, duration_nights, laundry_access, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [tripID.uuidString, 1, 0, "Weekend", 2, "unavailable",
                            fixedDate.timeIntervalSince1970, fixedDate.timeIntervalSince1970]
            )
            try writer.execute(sql: "INSERT INTO trip_activity_tags (trip_id, tag) VALUES (?, ?)",
                               arguments: [tripID.uuidString, "hiking"])
            try writer.execute(sql: "INSERT INTO trip_activity_tags (trip_id, tag) VALUES (?, ?)",
                               arguments: [tripID.uuidString, "city"])
            try writer.execute(sql: "INSERT INTO trip_source_kits (trip_id, kit_id) VALUES (?, ?)",
                               arguments: [tripID.uuidString, kitID.uuidString])

            let recommendation = Recommendation(
                id: itemID, quantity: 3, reason: .fullTripWithoutLaundry, confidence: .confident
            )
            try writer.execute(
                sql: """
                INSERT INTO trip_items (
                  id, schema_major, schema_minor, trip_id, source_kit_id, name, category,
                  rec_id, rec_schema_major, rec_schema_minor, rec_quantity, rec_reason,
                  rec_low_confidence, rec_confidence_reason, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: StatementArguments(Mapping.tripItemArguments(TripItem(
                    id: tripItemID, tripID: tripID, sourceKitID: kitID,
                    name: "Socks", category: "clothing", recommendation: recommendation,
                    createdAt: fixedDate
                )))
            )
            try writer.execute(
                sql: "INSERT INTO pack_transitions (id, schema_major, schema_minor, trip_item_id, from_status, to_status, occurred_at) VALUES (?,?,?,?,?,?,?)",
                arguments: [UUID().uuidString, 1, 0, tripItemID.uuidString, "planned", "packed",
                            fixedDate.timeIntervalSince1970]
            )
        }
        return queue
    }

    @Test("v1 fixture data survives the v2 migration with integrity")
    func legacyDataMigratesLosslessly() throws {
        let queue = try legacyDatabase()
        let dataset = try Fixture.dataset()

        // Upgrade through the store's real migrate path (what an app
        // upgrade does on launch).
        let store = try PackDeckStore(database: queue)
        let snapshot = try store.snapshot()

        // Every entity, order, and the ledger event survive unchanged.
        #expect(snapshot.kits == dataset.kits)
        #expect(snapshot.trips == dataset.trips)
        #expect(snapshot.tripItems == dataset.tripItems)
        #expect(snapshot.transitions.count == dataset.transitions.count)
        #expect(snapshot.currentStatus(for: tripItemID) == .packed)
        #expect(snapshot.dataset.id == dataset.id)

        // v2 backfilled positional order from insertion order.
        let tags = try store.snapshot().trips.first?.activityTags
        #expect(tags == ["hiking", "city"])

        // Post-migration the store remains fully writable.
        try store.recordTransition(tripItemID: tripItemID, to: .missing, at: fixedDate)
        #expect(try store.snapshot().currentStatus(for: tripItemID) == .missing)
    }

    @Test("fixture DDL matches the shipped v1 migration (no drift)")
    func schemaParity() throws {
        let url = try #require(
            Bundle.module.url(forResource: "legacy_schema_v1", withExtension: "sql", subdirectory: "Fixtures"),
            "legacy schema fixture missing from test bundle"
        )
        let fixtureDDL = try String(contentsOf: url, encoding: .utf8)
        #expect(normalize(fixtureDDL) == normalize(Schema.v1DDL))
    }

    private func normalize(_ sql: String) -> String {
        sql
            .split(whereSeparator: { $0 == " " || $0.isNewline })
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

@Suite("Backup codec")
struct BackupCodecTests {
    @Test("encode -> wipe -> import -> assert full equality; exports are stable")
    func exportWipeImportRoundTrip() throws {
        let store = try PackDeckStore.inMemory()
        let dataset = try Fixture.dataset()
        try store.replaceAll(with: dataset)

        let backup = try BackupCodec.encode(try store.snapshot())

        // Wipe.
        try store.replaceAll(with: try PackDeckDataset())
        #expect(try store.snapshot().kits.isEmpty)

        try BackupCodec.restore(backup, into: store)
        let restored = try store.snapshot()
        #expect(restored.dataset == dataset)

        // Re-export is byte-stable (sorted keys, ISO8601 dates).
        let second = try BackupCodec.encode(restored)
        #expect(second == backup)
    }

    @Test("backup format carries an integer version checked on import")
    func versionGate() throws {
        let backup = try BackupCodec.encode(try Fixture.dataset())
        var envelope = try JSONSerialization.jsonObject(with: backup) as? [String: Any]
        let version = envelope?["formatVersion"] as? Int
        #expect(version == BackupCodec.currentFormatVersion)
        #expect(PackDeckStore.backupFormatVersion == BackupCodec.currentFormatVersion)

        // Unknown future version refuses to import.
        envelope?["formatVersion"] = 999
        let tampered = try JSONSerialization.data(withJSONObject: envelope ?? [:])
        #expect(throws: BackupCodec.BackupError.unsupportedFormatVersion(999)) {
            _ = try BackupCodec.decode(tampered)
        }

        // Garbage refuses to import.
        #expect(throws: BackupCodec.BackupError.self) {
            _ = try BackupCodec.decode(Data("not json".utf8))
        }
    }

    @Test("restore of unknown provenance rolls back transactionally")
    func restoreAllOrNothing() throws {
        let store = try PackDeckStore.inMemory()
        try store.replaceAll(with: try Fixture.dataset())

        // A trip item pointing at a nonexistent trip: FK rejection
        // mid-import must roll the whole replace back — all-or-nothing.
        let rec = Recommendation(
            id: itemID, quantity: 3, reason: .fullTripWithoutLaundry, confidence: .confident
        )
        let orphan = TripItem(id: UUID(), tripID: UUID(), name: "Orphan", recommendation: rec)
        let dataset = try PackDeckDataset(kits: [], trips: [], tripItems: [orphan], transitions: [])
        #expect(throws: (any Error).self) {
            try store.replaceAll(with: dataset)
        }
        let snapshot = try store.snapshot()
        #expect(snapshot.tripItems.count == 1)
        #expect(snapshot.tripItems.first?.tripID == tripID) // unchanged original
        #expect(snapshot.trips.count == 1)
    }
}

@Suite("Store namespace")
struct StoreNamespaceTests {
    @Test("milestone marker reflects persistence milestone")
    func milestoneMarker() {
        #expect(PackDeckStore.milestone == "M3-persistence")
    }
}
