import Foundation

/// Version stamp carried by every persisted domain document.
public struct DomainSchemaVersion: Codable, Hashable, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let current = DomainSchemaVersion(major: 1, minor: 0)
}

/// Common persistence contract for stable, versioned domain values.
public protocol VersionedDomainModel: Codable, Identifiable, Hashable, Sendable {
    var schemaVersion: DomainSchemaVersion { get }
}

/// A reusable packing kit template.
public struct KitTemplate: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public var name: String
    public var notes: String?
    public var items: [KitItem]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        schemaVersion: DomainSchemaVersion = .current,
        name: String,
        notes: String? = nil,
        items: [KitItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.notes = notes
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One reusable line in a kit.
public struct KitItem: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public var name: String

    /// Units needed per travel day. Values below one are normalized to one
    /// by the recommendation engine with low confidence.
    public var baseQuantity: Int

    public var category: String?

    public init(
        id: UUID = UUID(),
        schemaVersion: DomainSchemaVersion = .current,
        name: String,
        baseQuantity: Int,
        category: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.baseQuantity = baseQuantity
        self.category = category
    }
}

/// Tri-state laundry context; `unknown` must not masquerade as a known flag.
public enum LaundryAccess: String, Codable, CaseIterable, Hashable, Sendable {
    case available
    case unavailable
    case unknown
}

/// A planned trip and the context used for recommendation math.
public struct Trip: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public var name: String

    /// Whole nights. One night means two travel days; `nil` is explicitly unknown.
    public var durationNights: Int?

    public var laundryAccess: LaundryAccess
    public var activityTags: [String]

    /// Kits selected for this trip. Store/UI layers snapshot their items at build time.
    public var sourceKitIDs: [UUID]

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        schemaVersion: DomainSchemaVersion = .current,
        name: String,
        durationNights: Int? = nil,
        laundryAccess: LaundryAccess = .unknown,
        activityTags: [String] = [],
        sourceKitIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.durationNights = durationNights
        self.laundryAccess = laundryAccess
        self.activityTags = activityTags
        self.sourceKitIDs = sourceKitIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Packing status of a trip item.
public enum ItemStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case planned
    case packed
    case missing
    case omitted
}

/// Stable reason identifiers suitable for UI copy mapping.
public enum RecommendationReason: String, Codable, CaseIterable, Hashable, Sendable {
    case tripDurationScaled = "trip_duration_scaled"
    case fullTripWithoutLaundry = "full_trip_without_laundry"
    case laundryCycleCap = "laundry_cycle_cap"
    case unknownLaundryConservative = "unknown_laundry_conservative"
    case unknownDurationBaseQuantity = "unknown_duration_base_quantity"
    case invalidDurationBaseQuantity = "invalid_duration_base_quantity"
    case invalidBaseQuantityNormalized = "invalid_base_quantity_normalized"
    case quantityOverflowSaturated = "quantity_overflow_saturated"
}

/// Deterministic output for one kit item. Identity is the source item's UUID.
public struct Recommendation: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public let quantity: Int
    public let reason: RecommendationReason
    public let confidence: Confidence

    public init(
        id: UUID,
        schemaVersion: DomainSchemaVersion = .current,
        quantity: Int,
        reason: RecommendationReason,
        confidence: Confidence
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.quantity = quantity
        self.reason = reason
        self.confidence = confidence
    }

    /// Named, stable reason string for direct display/logging contracts.
    public var reasonString: String { reason.rawValue }
}

/// Why the engine is (un)certain about a recommendation.
public enum Confidence: Codable, Hashable, Sendable {
    case confident
    case lowConfidence(reason: String)
}

/// A concrete item in a trip's packing-list snapshot.
///
/// Current status is intentionally absent. It is derived from `PackLedger`, so
/// state changes can only be represented by append-only transitions.
public struct TripItem: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public let tripID: UUID
    public let sourceKitID: UUID?
    public var name: String
    public var category: String?
    public var recommendation: Recommendation
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        schemaVersion: DomainSchemaVersion = .current,
        tripID: UUID,
        sourceKitID: UUID? = nil,
        name: String,
        category: String? = nil,
        recommendation: Recommendation,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.tripID = tripID
        self.sourceKitID = sourceKitID
        self.name = name
        self.category = category
        self.recommendation = recommendation
        self.createdAt = createdAt
    }
}

/// A single, immutable packing-progress event.
public struct PackTransition: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public let tripItemID: UUID
    public let fromStatus: ItemStatus
    public let toStatus: ItemStatus
    public let occurredAt: Date

    public init(
        id: UUID = UUID(),
        schemaVersion: DomainSchemaVersion = .current,
        tripItemID: UUID,
        fromStatus: ItemStatus,
        toStatus: ItemStatus,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.tripItemID = tripItemID
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.occurredAt = occurredAt
    }
}

/// Aggregate packing progress for a trip. Identity is the trip UUID.
public struct PackSummary: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public let totalItems: Int
    public let packed: Int
    public let missing: Int
    public let omitted: Int
    public let planned: Int
    public let completionRatio: Double

    public init(
        id: UUID,
        schemaVersion: DomainSchemaVersion = .current,
        totalItems: Int,
        packed: Int,
        missing: Int,
        omitted: Int,
        planned: Int,
        completionRatio: Double
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.totalItems = totalItems
        self.packed = packed
        self.missing = missing
        self.omitted = omitted
        self.planned = planned
        self.completionRatio = completionRatio
    }
}

/// Root payload for lossless domain encoding and future store backups.
///
/// `transitions` honors the same append-only contract as `PackLedger`:
/// external code can only append state-machine-valid events via
/// `recordTransition`; decoded histories are replay-validated.
public struct PackDeckDataset: VersionedDomainModel {
    public let id: UUID
    public let schemaVersion: DomainSchemaVersion
    public var kits: [KitTemplate]
    public var trips: [Trip]
    public var tripItems: [TripItem]
    public private(set) var transitions: [PackTransition]

    public init(
        id: UUID = UUID(),
        schemaVersion: DomainSchemaVersion = .current,
        kits: [KitTemplate] = [],
        trips: [Trip] = [],
        tripItems: [TripItem] = [],
        transitions: [PackTransition] = []
    ) throws {
        // Reuse the ledger replay so a hand-built dataset cannot carry an
        // inconsistent event history either.
        _ = try PackLedger(transitions: transitions)
        self.id = id
        self.schemaVersion = schemaVersion
        self.kits = kits
        self.trips = trips
        self.tripItems = tripItems
        self.transitions = transitions
    }

    /// Appends one state-machine-valid transition for the given trip item.
    @discardableResult
    public mutating func recordTransition(
        tripItemID: UUID,
        to status: ItemStatus,
        at occurredAt: Date = Date()
    ) throws -> PackTransition {
        var ledger = PackLedger.unchecked(transitions: transitions)
        let transition = try ledger.record(tripItemID: tripItemID, to: status, at: occurredAt)
        transitions = ledger.transitions
        return transition
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, kits, trips, tripItems, transitions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.schemaVersion = try container.decode(DomainSchemaVersion.self, forKey: .schemaVersion)
        self.kits = try container.decode([KitTemplate].self, forKey: .kits)
        self.trips = try container.decode([Trip].self, forKey: .trips)
        self.tripItems = try container.decode([TripItem].self, forKey: .tripItems)
        // Replay-validate so tampered persisted transitions never decode.
        let transitions = try container.decode([PackTransition].self, forKey: .transitions)
        _ = try PackLedger(transitions: transitions)
        self.transitions = transitions
    }
}
