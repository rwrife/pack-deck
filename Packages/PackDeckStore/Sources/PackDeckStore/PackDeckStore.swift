import Foundation
import GRDB
import PackDeckKit

/// Errors surfaced by `PackDeckStore` operations.
public enum PackDeckStoreError: Error, Equatable, Sendable {
    /// A requested entity does not exist in the database.
    case kitNotFound(UUID)
    case tripNotFound(UUID)
    case tripItemNotFound(UUID)

    /// A persisted row contradicts the domain contract and cannot be
    /// decoded (unknown enum raw values, malformed UUIDs, …). Fail closed
    /// rather than silently coercing.
    case corruptRow(column: String, detail: String)

    /// The database is not migrated to the expected schema version.
    case notMigrated
}

/// GRDB/SQLite persistence for Pack Deck.
///
/// Design contract (M3, issue #3):
/// - Every mutation is one database transaction — a failed write can never
///   leave partial state (including cascading child rows).
/// - The packing-transition ledger is append-only and validated with the
///   domain `PackLedger` rules *before* anything is written, so no SQL
///   error or client bug can persist an invalid transition.
/// - Reads return validated `PackDeckSnapshot` values; decoding is
///   fail-closed (see `PackDeckStoreError.corruptRow`).
/// - Local storage only: SQLite in the app container, zero network use.
///
/// Thread safety: GRDB's `DatabasePool` and `DatabaseQueue` are internally
/// synchronized and Sendable; the existential wrapper erases that marker,
/// hence `@unchecked` (the store keeps no other mutable state).
public final class PackDeckStore: @unchecked Sendable {
    /// Namespace identifier.
    public static let domain = "PackDeckStore"

    /// Current persistence schema milestone marker.
    public static let milestone = "M3-persistence"

    /// Schema version the store was built against (number of migrations).
    public static let schemaVersion: Int = 2

    /// Backup/interchange format version (independent of DB schema version;
    /// `BackupCodec` checks it on import).
    public static let backupFormatVersion: Int = 1

    /// App-container default database filename.
    public static let defaultDatabaseFilename = "packdeck.sqlite"

    /// Existential over GRDB's reader+writer protocols: `DatabasePool`
    /// (on-disk, WAL) for the app, `DatabaseQueue` (in-memory) for tests.
    let db: any DatabaseReader & DatabaseWriter

    // MARK: - Construction

    /// Opens (creating if necessary) an on-disk database at `url`.
    ///
    /// Uses WAL journaling; migrations run eagerly so callers never see a
    /// partially-migrated database.
    public init(url: URL) throws {
        let pool = try DatabasePool(path: url.path)
        self.db = pool
        try Self.migrate(db)
    }

    /// Opens an in-memory database (tests only; nothing persists).
    public static func inMemory() throws -> PackDeckStore {
        try PackDeckStore(database: DatabaseQueue())
    }

    /// Wraps an existing reader/writer; set `migrating` false only when the
    /// database is already at the current schema (fixture-based tests).
    init(database: any DatabaseReader & DatabaseWriter, migrating: Bool = true) throws {
        self.db = database
        if migrating {
            try Self.migrate(database)
        }
    }

    /// Applies pending migrations and ensures the meta row exists.
    static func migrate(_ db: any DatabaseReader & DatabaseWriter) throws {
        try Schema.migrator.migrate(db)
        try db.write { writer in
            let applied = try Schema.migrator.appliedMigrations(writer)
            guard applied.contains(SchemaIdentifier.latest) else {
                throw PackDeckStoreError.notMigrated
            }
            try initializeMeta(writer)
        }
    }

    /// Applied migration ids, oldest first (raw probe shared with tests).
    func appliedMigrations() throws -> [String] {
        try db.read { reader in
            try Array(String.fetchAll(
                reader,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            ))
        }
    }

    private static func initializeMeta(_ writer: Database) throws {
        if try DatasetIDReader.datasetID(writer) == nil {
            try writer.execute(
                sql: "INSERT INTO store_meta (key, value) VALUES (?, ?)",
                arguments: [Schema.datasetIDKey, UUID().uuidString]
            )
        }
    }

    // MARK: - Reads

    /// One consistent read of the whole dataset (single transaction).
    public func snapshot() throws -> PackDeckSnapshot {
        try db.read { reader in try Self.readSnapshot(reader) }
    }

    public func fetchKit(_ id: UUID) throws -> KitTemplate? {
        let snapshot = try snapshot()
        return snapshot.kits.first { $0.id == id }
    }

    public func fetchTrip(_ id: UUID) throws -> Trip? {
        let snapshot = try snapshot()
        return snapshot.trips.first { $0.id == id }
    }

    /// Kits that still list `kitID` in their `sourceKitIDs` provenance.
    /// Used by the UI's delete-warning flow (kits are copied into trips at
    /// build time, so deletion is allowed but should be confirmed).
    public func tripsReferencing(kitID: UUID) throws -> [Trip] {
        let snapshot = try snapshot()
        return snapshot.trips.filter { $0.sourceKitIDs.contains(kitID) }
    }

    // MARK: - Kits

    /// Inserts or replaces a kit and its items (items are replaced wholesale
    /// to preserve array order semantics).
    public func saveKit(_ kit: KitTemplate) throws {
        try db.write { writer in
            try Self.deleteKitRows(writer, id: kit.id)
            try Self.insertKit(writer, kit)
        }
    }

    /// Deletes a kit (and its items via explicit child delete plus FK
    /// cascade). Referencing trips are *not* rewritten — trips keep their
    /// build-time provenance ids by design.
    public func deleteKit(id: UUID) throws {
        try db.write { writer in
            guard try Self.kitExists(writer, id: id) else {
                throw PackDeckStoreError.kitNotFound(id)
            }
            try Self.deleteKitRows(writer, id: id)
        }
    }

    // MARK: - Trips

    public func saveTrip(_ trip: Trip) throws {
        try db.write { writer in
            // Explicit delete + re-insert replaces parent and child rows in
            // one transaction. Trip items only cascade when the trip itself
            // is deleted (they are snapshots, not live children).
            try writer.execute(
                sql: "DELETE FROM trips WHERE id = ?",
                arguments: [trip.id.uuidString]
            )
            try Self.insertTrip(writer, trip)
        }
    }

    /// Deletes a trip; its items cascade, and their ledger events cascade
    /// with the items — one transaction, no orphans.
    public func deleteTrip(id: UUID) throws {
        try db.write { writer in
            guard try Self.tripExists(writer, id: id) else {
                throw PackDeckStoreError.tripNotFound(id)
            }
            try writer.execute(sql: "DELETE FROM trips WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Trip items

    /// Adds snapshot items to a trip in one transaction (the trip-builder
    /// "combine kits + ad-hoc items" write). Rejects duplicate ids.
    public func addTripItems(_ items: [TripItem]) throws {
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        guard ids.count == items.count else {
            throw PackDeckStoreError.corruptRow(column: "id", detail: "duplicate trip item ids in batch")
        }
        try db.write { writer in
            for item in items {
                let dupeSQL = "SELECT 1 FROM trip_items WHERE id = ?"
                let dupe = try Row.fetchOne(writer, sql: dupeSQL, arguments: [item.id.uuidString])
                if dupe != nil {
                    throw PackDeckStoreError.corruptRow(column: "id", detail: "trip item \(item.id) already exists")
                }
                let tripSQL = "SELECT 1 FROM trips WHERE id = ?"
                let tripRow = try Row.fetchOne(writer, sql: tripSQL, arguments: [item.tripID.uuidString])
                if tripRow == nil {
                    throw PackDeckStoreError.tripNotFound(item.tripID)
                }
                try Self.insertTripItem(writer, item)
            }
        }
    }

    // MARK: - Transition ledger

    /// Appends one packing transition for `tripItemID`, validated against
    /// the replayed ledger *before* the write. Rejections raise the domain
    /// `PackLedgerError` and touch nothing.
    @discardableResult
    public func recordTransition(
        tripItemID: UUID,
        to status: ItemStatus,
        at occurredAt: Date = Date()
    ) throws -> PackTransition {
        try db.write { writer in
            let existsSQL = "SELECT 1 FROM trip_items WHERE id = ?"
            let row = try Row.fetchOne(writer, sql: existsSQL, arguments: [tripItemID.uuidString])
            if row == nil {
                throw PackDeckStoreError.tripItemNotFound(tripItemID)
            }

            let transitions = try Self.readTransitions(writer)
            var ledger = try PackLedger(transitions: transitions)

            // Domain validation first; throws without touching the DB.
            let transition = try ledger.record(tripItemID: tripItemID, to: status, at: occurredAt)
            try Self.insertTransition(writer, transition)
            return transition
        }
    }

    // MARK: - Whole-dataset replacement (backup restore)

    /// Replaces every persisted row with `dataset` in a single transaction
    /// and re-stamps the store's dataset identity so future exports match.
    /// A failure (including foreign-key rejection of unknown provenance)
    /// rolls the entire replace back — all-or-nothing.
    public func replaceAll(with dataset: PackDeckDataset) throws {
        try db.write { writer in
            for table in Self.clearOrder {
                try writer.execute(sql: "DELETE FROM \(table)")
            }
            for kit in dataset.kits {
                try Self.insertKit(writer, kit)
            }
            for trip in dataset.trips {
                try Self.insertTrip(writer, trip)
            }
            for item in dataset.tripItems {
                try Self.insertTripItem(writer, item)
            }
            for transition in dataset.transitions {
                try Self.insertTransition(writer, transition)
            }
            try writer.execute(
                sql: "INSERT OR REPLACE INTO store_meta (key, value) VALUES (?, ?)",
                arguments: [Schema.datasetIDKey, dataset.id.uuidString]
            )
        }
    }

    /// Deletion order matters: children before parents.
    static let clearOrder = [
        "pack_transitions",
        "trip_items",
        "trip_activity_tags",
        "trip_source_kits",
        "trips",
        "kit_items",
        "kits",
    ]

    // MARK: - Shared internals (internal, exercised through the public API)

    static func readSnapshot(_ reader: Database) throws -> PackDeckSnapshot {
        var kits: [KitTemplate] = []
        var trips: [Trip] = []
        var tripItems: [TripItem] = []

        let kitRows = try Array(Row.fetchAll(reader, sql: "SELECT * FROM kits ORDER BY rowid"))
        for row in kitRows {
            let kitID: UUID = try Mapping.uuidString(row, "id")
            let items = try readKitItems(reader, kitID: kitID)
            kits.append(try Mapping.kit(row, items: items))
        }

        let tripRows = try Array(Row.fetchAll(reader, sql: "SELECT * FROM trips ORDER BY rowid"))
        for row in tripRows {
            let tripID: UUID = try Mapping.uuidString(row, "id")
            let tags = try readTags(reader, tripID: tripID)
            let sourceKits = try readSourceKits(reader, tripID: tripID)
            trips.append(try Mapping.trip(row, tags: tags, sourceKits: sourceKits))
        }

        for row in try Array(Row.fetchAll(reader, sql: "SELECT * FROM trip_items ORDER BY rowid")) {
            tripItems.append(try Mapping.tripItem(row))
        }
        let transitions = try readTransitions(reader)

        let datasetID = try DatasetIDReader.datasetID(reader) ?? UUID()
        let dataset: PackDeckDataset
        do {
            dataset = try PackDeckDataset(
                id: datasetID,
                kits: kits,
                trips: trips,
                tripItems: tripItems,
                transitions: transitions
            )
        } catch {
            // Ledger replay rejection means the on-disk history is invalid.
            throw PackDeckStoreError.corruptRow(
                column: "pack_transitions",
                detail: "ledger replay rejected persisted history"
            )
        }
        return PackDeckSnapshot(dataset: dataset)
    }

    static func readKitItems(_ reader: Database, kitID: UUID) throws -> [KitItem] {
        let sql = "SELECT * FROM kit_items WHERE kit_id = ? ORDER BY position, rowid"
        return try Array(Row.fetchAll(reader, sql: sql, arguments: [kitID.uuidString])).map {
            try Mapping.kitItem($0)
        }
    }

    static func readTags(_ reader: Database, tripID: UUID) throws -> [String] {
        let sql = "SELECT tag FROM trip_activity_tags WHERE trip_id = ? ORDER BY position, rowid"
        return try Array(Row.fetchAll(reader, sql: sql, arguments: [tripID.uuidString]))
            .map { $0[0] as String }
    }

    static func readSourceKits(_ reader: Database, tripID: UUID) throws -> [UUID] {
        let sql = "SELECT kit_id FROM trip_source_kits WHERE trip_id = ? ORDER BY position, rowid"
        return try Array(Row.fetchAll(reader, sql: sql, arguments: [tripID.uuidString])).map { row in
            try Mapping.uuidString(row, "kit_id")
        }
    }

    /// Ledger events in append order. Insertion order (`rowid`) is the
    /// source of truth — `occurred_at` may tie between rapid transitions.
    static func readTransitions(_ reader: Database) throws -> [PackTransition] {
        let sql = "SELECT * FROM pack_transitions ORDER BY rowid"
        return try Array(Row.fetchAll(reader, sql: sql)).map { try Mapping.transition($0) }
    }

    static func kitExists(_ writer: Database, id: UUID) throws -> Bool {
        let row = try Row.fetchOne(writer, sql: "SELECT 1 FROM kits WHERE id = ?", arguments: [id.uuidString])
        return row != nil
    }

    static func tripExists(_ writer: Database, id: UUID) throws -> Bool {
        let row = try Row.fetchOne(writer, sql: "SELECT 1 FROM trips WHERE id = ?", arguments: [id.uuidString])
        return row != nil
    }

    static func deleteKitRows(_ writer: Database, id: UUID) throws {
        // Explicit child delete first; the FK cascade covers the same rows
        // but doing both keeps intent legible and survives pragma changes.
        try writer.execute(sql: "DELETE FROM kit_items WHERE kit_id = ?", arguments: [id.uuidString])
        try writer.execute(sql: "DELETE FROM kits WHERE id = ?", arguments: [id.uuidString])
    }

    static func insertKit(_ writer: Database, _ kit: KitTemplate) throws {
        try writer.execute(sql: Mapping.insertKitSQL, arguments: StatementArguments(Mapping.kitArguments(kit)))
        for (position, item) in kit.items.enumerated() {
            try writer.execute(
                sql: Mapping.insertKitItemSQL,
                arguments: StatementArguments(Mapping.kitItemArguments(item: item, kitID: kit.id, position: position))
            )
        }
    }

    static func insertTrip(_ writer: Database, _ trip: Trip) throws {
        try writer.execute(sql: Mapping.insertTripSQL, arguments: StatementArguments(Mapping.tripArguments(trip)))
        for (position, tag) in trip.activityTags.enumerated() {
            let args: [DatabaseValueConvertible?] = [trip.id.uuidString, tag, position]
            try writer.execute(sql: Mapping.insertTripTagSQL, arguments: StatementArguments(args))
        }
        for (position, kitID) in trip.sourceKitIDs.enumerated() {
            let args: [DatabaseValueConvertible?] = [trip.id.uuidString, kitID.uuidString, position]
            try writer.execute(sql: Mapping.insertTripSourceKitSQL, arguments: StatementArguments(args))
        }
    }

    static func insertTripItem(_ writer: Database, _ item: TripItem) throws {
        try writer.execute(sql: Mapping.insertTripItemSQL, arguments: StatementArguments(Mapping.tripItemArguments(item)))
    }

    static func insertTransition(_ writer: Database, _ transition: PackTransition) throws {
        try writer.execute(sql: Mapping.insertTransitionSQL, arguments: StatementArguments(Mapping.transitionArguments(transition)))
    }
}

/// Reads the stable dataset identity from `store_meta`.
enum DatasetIDReader {
    static func datasetID(_ reader: Database) throws -> UUID? {
        let sql = "SELECT value FROM store_meta WHERE key = ?"
        guard let row = try Row.fetchOne(reader, sql: sql, arguments: [Schema.datasetIDKey]) else {
            return nil
        }
        let raw: String = row[0]
        return UUID(uuidString: raw)
    }
}

/// The latest schema identifier the store can read.
enum SchemaIdentifier {
    static let latest = "v2-item-position"
}
