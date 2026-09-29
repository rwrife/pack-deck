import Foundation

/// Append-only transition ledger for trip-item packing state.
///
/// Clients can only append transitions. Current state and summaries are derived
/// views over immutable events.
public struct PackLedger: Codable, Hashable, Sendable {
    public private(set) var transitions: [PackTransition]

    public init(transitions: [PackTransition] = []) {
        // Preserve supplied event order exactly; timestamps are metadata and can tie.
        self.transitions = transitions
    }

    @discardableResult
    public mutating func record(
        tripItemID: UUID,
        to status: ItemStatus,
        at occurredAt: Date = Date()
    ) -> PackTransition {
        let transition = PackTransition(
            tripItemID: tripItemID,
            fromStatus: currentStatus(for: tripItemID),
            toStatus: status,
            occurredAt: occurredAt
        )
        transitions.append(transition)
        return transition
    }

    public func currentStatus(for tripItemID: UUID) -> ItemStatus {
        transitions
            .last(where: { $0.tripItemID == tripItemID })?
            .toStatus ?? .planned
    }

    public func summary(for tripID: UUID, items: [TripItem]) -> PackSummary {
        let tripItems = items.filter { $0.tripID == tripID }

        var packed = 0
        var missing = 0
        var omitted = 0
        var planned = 0

        for item in tripItems {
            switch currentStatus(for: item.id) {
            case .planned:
                planned += 1
            case .packed:
                packed += 1
            case .missing:
                missing += 1
            case .omitted:
                omitted += 1
            }
        }

        let total = tripItems.count
        let ratio = total == 0 ? 0.0 : Double(packed) / Double(total)

        return PackSummary(
            id: tripID,
            totalItems: total,
            packed: packed,
            missing: missing,
            omitted: omitted,
            planned: planned,
            completionRatio: ratio
        )
    }
}
