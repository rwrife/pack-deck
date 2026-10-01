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
