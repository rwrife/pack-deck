import Foundation
import GRDB
import PackDeckKit

/// Manual domain <-> row mapping.
///
/// Mapping is explicit (not synthesized Codable persistence) so every read
/// goes through the same validated domain constructors the JSON codec
/// honors, and UUIDs/timestamps serialize losslessly regardless of locale.
enum Mapping {
    static func uuidString(_ row: Row, _ column: String) throws -> UUID {
        let raw: String = row[column]
        guard let uuid = UUID(uuidString: raw) else {
            throw PackDeckStoreError.corruptRow(
                column: column,
                detail: "not a UUID: '\(raw)'"
            )
        }
        return uuid
    }

    static func optionalUUIDString(_ row: Row, _ column: String) throws -> UUID? {
        let raw: String? = row[column]
        guard let raw else { return nil }
        guard let uuid = UUID(uuidString: raw) else {
            throw PackDeckStoreError.corruptRow(
                column: column,
                detail: "not a UUID: '\(raw)'"
            )
        }
        return uuid
    }

    static func schemaVersion(_ row: Row, major: String, minor: String) -> DomainSchemaVersion {
        DomainSchemaVersion(major: row[major], minor: row[minor])
    }

    static func date(_ row: Row, _ column: String) -> Date {
        let seconds: Double = row[column]
        return Date(timeIntervalSince1970: seconds)
    }

    static func timestamp(_ date: Date) -> Double {
        date.timeIntervalSince1970
    }

    // MARK: - Kit items

    static func kitItem(_ row: Row) throws -> KitItem {
        KitItem(
            id: try uuidString(row, "id"),
            schemaVersion: schemaVersion(row, major: "schema_major", minor: "schema_minor"),
            name: row["name"],
            baseQuantity: row["base_quantity"],
            category: row["category"]
        )
    }

    static func kitItemArguments(item: KitItem, kitID: UUID, position: Int) -> [DatabaseValueConvertible?] {
        [
            item.id.uuidString,
            kitID.uuidString,
            item.schemaVersion.major,
            item.schemaVersion.minor,
            item.name,
            item.baseQuantity,
            item.category as String?,
            position,
        ]
    }

    // MARK: - Kits

    static func kit(_ row: Row, items: [KitItem]) throws -> KitTemplate {
        KitTemplate(
            id: try uuidString(row, "id"),
            schemaVersion: schemaVersion(row, major: "schema_major", minor: "schema_minor"),
            name: row["name"],
            notes: row["notes"],
            items: items,
            createdAt: date(row, "created_at"),
            updatedAt: date(row, "updated_at")
        )
    }

    static func kitArguments(_ kit: KitTemplate) -> [DatabaseValueConvertible?] {
        [
            kit.id.uuidString,
            kit.schemaVersion.major,
            kit.schemaVersion.minor,
            kit.name,
            kit.notes as String?,
            timestamp(kit.createdAt),
            timestamp(kit.updatedAt),
        ]
    }

    // MARK: - Trips

    static func trip(_ row: Row, tags: [String], sourceKits: [UUID]) throws -> Trip {
        let rawLaundry: String = row["laundry_access"]
        guard let laundry = LaundryAccess(rawValue: rawLaundry) else {
            throw PackDeckStoreError.corruptRow(
                column: "laundry_access",
                detail: "unknown laundry access: '\(rawLaundry)'"
            )
        }
        return Trip(
            id: try uuidString(row, "id"),
            schemaVersion: schemaVersion(row, major: "schema_major", minor: "schema_minor"),
            name: row["name"],
            durationNights: row["duration_nights"],
            laundryAccess: laundry,
            activityTags: tags,
            sourceKitIDs: sourceKits,
            createdAt: date(row, "created_at"),
            updatedAt: date(row, "updated_at")
        )
    }

    static func tripArguments(_ trip: Trip) -> [DatabaseValueConvertible?] {
        [
            trip.id.uuidString,
            trip.schemaVersion.major,
            trip.schemaVersion.minor,
            trip.name,
            trip.durationNights as Int?,
            trip.laundryAccess.rawValue,
            timestamp(trip.createdAt),
            timestamp(trip.updatedAt),
        ]
    }

    // MARK: - Trip items

    static func tripItem(_ row: Row) throws -> TripItem {
        let rawReason: String = row["rec_reason"]
        guard let reason = RecommendationReason(rawValue: rawReason) else {
            throw PackDeckStoreError.corruptRow(
                column: "rec_reason",
                detail: "unknown recommendation reason: '\(rawReason)'"
            )
        }
        let lowConfidenceFlag: Int = row["rec_low_confidence"]
        let confidenceReason: String? = row["rec_confidence_reason"]
        let confidence: Confidence
        if lowConfidenceFlag != 0 {
            confidence = .lowConfidence(reason: confidenceReason ?? "")
        } else {
            confidence = .confident
        }

        let recommendation = Recommendation(
            id: try uuidString(row, "rec_id"),
            schemaVersion: schemaVersion(row, major: "rec_schema_major", minor: "rec_schema_minor"),
            quantity: row["rec_quantity"],
            reason: reason,
            confidence: confidence
        )

        return TripItem(
            id: try uuidString(row, "id"),
            schemaVersion: schemaVersion(row, major: "schema_major", minor: "schema_minor"),
            tripID: try uuidString(row, "trip_id"),
            sourceKitID: try optionalUUIDString(row, "source_kit_id"),
            name: row["name"],
            category: row["category"],
            recommendation: recommendation,
            createdAt: date(row, "created_at")
        )
    }

    static func tripItemArguments(_ item: TripItem) -> [DatabaseValueConvertible?] {
        let confidenceReason: String?
        let lowConfidence: Int
        switch item.recommendation.confidence {
        case .confident:
            confidenceReason = nil
            lowConfidence = 0
        case let .lowConfidence(reason):
            confidenceReason = reason
            lowConfidence = 1
        }

        return [
            item.id.uuidString,
            item.schemaVersion.major,
            item.schemaVersion.minor,
            item.tripID.uuidString,
            item.sourceKitID?.uuidString as String?,
            item.name,
            item.category as String?,
            item.recommendation.id.uuidString,
            item.recommendation.schemaVersion.major,
            item.recommendation.schemaVersion.minor,
            item.recommendation.quantity,
            item.recommendation.reason.rawValue,
            lowConfidence,
            confidenceReason,
            timestamp(item.createdAt),
        ]
    }

    // MARK: - Transitions

    static func transition(_ row: Row) throws -> PackTransition {
        let rawFrom: String = row["from_status"]
        let rawTo: String = row["to_status"]
        guard let from = ItemStatus(rawValue: rawFrom), let to = ItemStatus(rawValue: rawTo) else {
            throw PackDeckStoreError.corruptRow(
                column: "from_status/to_status",
                detail: "unknown status: '\(rawFrom)' -> '\(rawTo)'"
            )
        }
        return PackTransition(
            id: try uuidString(row, "id"),
            schemaVersion: schemaVersion(row, major: "schema_major", minor: "schema_minor"),
            tripItemID: try uuidString(row, "trip_item_id"),
            fromStatus: from,
            toStatus: to,
            occurredAt: date(row, "occurred_at")
        )
    }

    static func transitionArguments(_ transition: PackTransition) -> [DatabaseValueConvertible?] {
        [
            transition.id.uuidString,
            transition.schemaVersion.major,
            transition.schemaVersion.minor,
            transition.tripItemID.uuidString,
            transition.fromStatus.rawValue,
            transition.toStatus.rawValue,
            timestamp(transition.occurredAt),
        ]
    }

    // MARK: - SQL

    static let insertKitSQL = """
    INSERT INTO kits (id, schema_major, schema_minor, name, notes, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    static let insertKitItemSQL = """
    INSERT INTO kit_items (id, kit_id, schema_major, schema_minor, name, base_quantity, category, position)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    static let insertTripSQL = """
    INSERT INTO trips (id, schema_major, schema_minor, name, duration_nights, laundry_access, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    static let insertTripTagSQL = "INSERT INTO trip_activity_tags (trip_id, tag, position) VALUES (?, ?, ?)"

    static let insertTripSourceKitSQL = "INSERT INTO trip_source_kits (trip_id, kit_id, position) VALUES (?, ?, ?)"

    static let insertTripItemSQL = """
    INSERT INTO trip_items (
      id, schema_major, schema_minor, trip_id, source_kit_id, name, category,
      rec_id, rec_schema_major, rec_schema_minor, rec_quantity, rec_reason,
      rec_low_confidence, rec_confidence_reason, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    static let insertTransitionSQL = """
    INSERT INTO pack_transitions (id, schema_major, schema_minor, trip_item_id, from_status, to_status, occurred_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """
}
