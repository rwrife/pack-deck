import Foundation
import GRDB
import PackDeckKit

/// A complete, validated snapshot of every persisted entity.
///
/// The transition ledger is rebuilt through the domain's replay-validated
/// `PackDeckDataset` initializer, so a snapshot can never surface a
/// transition history the state machine could not have produced.
public struct PackDeckSnapshot: Equatable, Sendable {
    public let dataset: PackDeckDataset

    public var kits: [KitTemplate] { dataset.kits }
    public var trips: [Trip] { dataset.trips }
    public var tripItems: [TripItem] { dataset.tripItems }
    public var transitions: [PackTransition] { dataset.transitions }

    init(dataset: PackDeckDataset) {
        self.dataset = dataset
    }

    /// Live packing state derived from the transition ledger.
    public func currentStatus(for tripItemID: UUID) -> ItemStatus {
        transitions.last(where: { $0.tripItemID == tripItemID })?.toStatus ?? .planned
    }

    /// Packing progress for one trip (same derivation as `PackLedger`).
    public func summary(for tripID: UUID) throws -> PackSummary {
        try PackLedger(transitions: transitions).summary(for: tripID, items: tripItems)
    }
}
