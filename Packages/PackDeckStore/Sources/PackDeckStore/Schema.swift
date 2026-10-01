import Foundation
import GRDB

/// SQLite schema definitions and the versioned migrator for PackDeckStore.
///
/// Schema history:
/// - `v1-initial-schema`: baseline tables for kits, kit items, trips,
///   trip items, the append-only packing-transition ledger, and store meta.
/// - `v2-item-position`: adds explicit `position` ordering columns to
///   `kit_items`, `trip_activity_tags`, and `trip_source_kits` (the kit
///   editor reorders rows; array order is part of the domain contract),
///   backfilling from insertion order, plus covering indexes.
///
/// `Tests/PackDeckStoreTests/Fixtures/legacy_schema_v1.sql` reproduces the
/// exact v1 DDL for fixture-based migration tests; a schema-parity test
/// guards against drift between the two.
enum Schema {
    /// Statements GRDB applies inside one transaction per migration.
    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-initial-schema") { db in
            for statement in v1Statements { try db.execute(sql: statement) }
        }
        migrator.registerMigration("v2-item-position") { db in
            for statement in v2Statements { try db.execute(sql: statement) }
        }
        return migrator
    }()

    /// The `store_meta` key holding the stable dataset identity used by
    /// backup export/import so an export -> wipe -> import -> export cycle
    /// yields a byte-identical dataset.
    static let datasetIDKey = "dataset_id"

    /// Joined v1 DDL (fixture-parity reference; executed via `v1Statements`).
    static let v1DDL = """
CREATE TABLE IF NOT EXISTS store_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS kits (
  id TEXT PRIMARY KEY,
  schema_major INTEGER NOT NULL,
  schema_minor INTEGER NOT NULL,
  name TEXT NOT NULL,
  notes TEXT,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS kit_items (
  id TEXT PRIMARY KEY,
  kit_id TEXT NOT NULL REFERENCES kits(id) ON DELETE CASCADE,
  schema_major INTEGER NOT NULL,
  schema_minor INTEGER NOT NULL,
  name TEXT NOT NULL,
  base_quantity INTEGER NOT NULL,
  category TEXT
);
CREATE TABLE IF NOT EXISTS trips (
  id TEXT PRIMARY KEY,
  schema_major INTEGER NOT NULL,
  schema_minor INTEGER NOT NULL,
  name TEXT NOT NULL,
  duration_nights INTEGER,
  laundry_access TEXT NOT NULL,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS trip_activity_tags (
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  tag TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS trip_source_kits (
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  kit_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS trip_items (
  id TEXT PRIMARY KEY,
  schema_major INTEGER NOT NULL,
  schema_minor INTEGER NOT NULL,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  source_kit_id TEXT,
  name TEXT NOT NULL,
  category TEXT,
  rec_id TEXT NOT NULL,
  rec_schema_major INTEGER NOT NULL,
  rec_schema_minor INTEGER NOT NULL,
  rec_quantity INTEGER NOT NULL,
  rec_reason TEXT NOT NULL,
  rec_low_confidence INTEGER NOT NULL,
  rec_confidence_reason TEXT,
  created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS pack_transitions (
  id TEXT PRIMARY KEY,
  schema_major INTEGER NOT NULL,
  schema_minor INTEGER NOT NULL,
  trip_item_id TEXT NOT NULL REFERENCES trip_items(id) ON DELETE CASCADE,
  from_status TEXT NOT NULL,
  to_status TEXT NOT NULL,
  occurred_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_trip_items_trip ON trip_items(trip_id);
CREATE INDEX IF NOT EXISTS idx_pack_transitions_item ON pack_transitions(trip_item_id);
"""

    static var v1Statements: [String] { statements(in: v1DDL) }

    /// Forward migration: explicit positional order for child rows.
    /// Backfill preserves the insertion order already present in v1 rows.
    static let v2DDL = """
ALTER TABLE kit_items ADD COLUMN position INTEGER NOT NULL DEFAULT 0;
UPDATE kit_items SET position = (
  SELECT kit_items.rowid - (
    SELECT MIN(k2.rowid) FROM kit_items AS k2 WHERE k2.kit_id = kit_items.kit_id
  )
);
CREATE INDEX IF NOT EXISTS idx_kit_items_kit_position ON kit_items(kit_id, position);
ALTER TABLE trip_activity_tags ADD COLUMN position INTEGER NOT NULL DEFAULT 0;
UPDATE trip_activity_tags SET position = (
  SELECT trip_activity_tags.rowid - (
    SELECT MIN(t2.rowid) FROM trip_activity_tags AS t2 WHERE t2.trip_id = trip_activity_tags.trip_id
  )
);
CREATE INDEX IF NOT EXISTS idx_trip_activity_tags_trip_position ON trip_activity_tags(trip_id, position);
ALTER TABLE trip_source_kits ADD COLUMN position INTEGER NOT NULL DEFAULT 0;
UPDATE trip_source_kits SET position = (
  SELECT trip_source_kits.rowid - (
    SELECT MIN(s2.rowid) FROM trip_source_kits AS s2 WHERE s2.trip_id = trip_source_kits.trip_id
  )
);
CREATE INDEX IF NOT EXISTS idx_trip_source_kits_trip_position ON trip_source_kits(trip_id, position);
"""

    static var v2Statements: [String] { statements(in: v2DDL) }

    /// Splits a DDL script into single statements (the scripts contain no
    /// semicolons inside literals, so a plain split is exact).
    static func statements(in script: String) -> [String] {
        script
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
