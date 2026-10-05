import Foundation

/// Rejections raised when a requested transition is inconsistent with the
/// ledger's append-only state machine.
public enum PackLedgerError: Error, Codable, Hashable, Sendable {
    /// The item already has this status — recording would duplicate state.
    case alreadyInStatus(ItemStatus)
    /// `planned` is the initial state and is never a target status; a
    /// re-planning flow must create a new `TripItem` instead.
    case cannotRevertToPlanned
    /// The transition is not permitted by the packing state machine.
    case invalidTransition(from: ItemStatus, to: ItemStatus)
    /// A decoded event history contradicts the state machine and cannot be
    /// replayed.
    case inconsistentHistory
}

/// Append-only transition ledger for trip-item packing state.
///
/// Clients can only append *valid* transitions; every append is validated
/// against the item's derived current status. Current state and summaries
/// are derived views over immutable events.
public struct PackLedger: Codable, Hashable, Sendable {
    public private(set) var transitions: [PackTransition]

    /// Legal transitions from each status. `planned` is reachable from no
    /// status — it exists only as the implicit initial state.
    static let allowedTransitions: [ItemStatus: Set<ItemStatus>] = [
        .planned: [.packed, .missing, .omitted],
        .packed: [.planned, .missing, .omitted],
        .missing: [.planned, .packed, .omitted],
        .omitted: [.planned, .packed, .missing],
    ]

    /// Validates each event against the replayed state machine before
    /// accepting the history (throws `PackLedgerError.inconsistentHistory`
    /// for decoded or hand-built histories that could not have been
    /// produced by `record`). Use `unchecked(transitions:)` for lossless
    /// dataset round-trips.
    public init(transitions: [PackTransition] = []) throws {
        var replayed: [UUID: ItemStatus] = [:]
        for event in transitions {
            let from = replayed[event.tripItemID] ?? .planned
            guard event.fromStatus == from,
                  Self.allowedTransitions[from, default: []].contains(event.toStatus)
            else {
                throw PackLedgerError.inconsistentHistory
            }
            replayed[event.tripItemID] = event.toStatus
        }
        self.transitions = transitions
    }

    /// Accepts a transition history without replay validation — module-internal
    /// and reserved for lossless re-derivation of already-validated datasets
    /// (e.g. `PackDeckDataset.recordTransition`). External callers cannot
    /// obtain an unvalidated ledger.
    static func unchecked(transitions: [PackTransition] = []) -> PackLedger {
        PackLedger(unchecked: transitions)
    }

    private init(unchecked transitions: [PackTransition]) {
        // Preserve supplied event order exactly; timestamps are metadata and can tie.
        self.transitions = transitions
    }

    /// Decoding replays the state machine, so a tampered persisted history
    /// fails to decode rather than surfacing as a ledger that pretends the
    /// inconsistent events are valid.
    private enum CodingKeys: String, CodingKey {
        case transitions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(transitions: container.decode([PackTransition].self, forKey: .transitions))
    }

    /// Validates and appends one transition. The derived current status of
    /// the item is the source of truth for `fromStatus`; requests that do
    /// not move the item to a different, legal status are rejected without
    /// touching history.
    @discardableResult
    public mutating func record(
        tripItemID: UUID,
        to status: ItemStatus,
        at occurredAt: Date = Date()
    ) throws -> PackTransition {
        let from = currentStatus(for: tripItemID)
        guard from != status else {
            throw PackLedgerError.alreadyInStatus(status)
        }
        guard status != .planned else {
            throw PackLedgerError.cannotRevertToPlanned
        }
        guard Self.allowedTransitions[from, default: []].contains(status) else {
            throw PackLedgerError.invalidTransition(from: from, to: status)
        }
        let transition = PackTransition(
            tripItemID: tripItemID,
            fromStatus: from,
            toStatus: status,
            occurredAt: occurredAt
        )
        transitions.append(transition)
        return transition
    }

    /// Appends an inverse event without deleting the previous action.
    /// `record` still rejects direct reversion to planned; only undo may do so.
    @discardableResult
    public mutating func undo(tripItemID: UUID, at occurredAt: Date = Date()) throws -> PackTransition {
        guard let last = transitions.last(where: { $0.tripItemID == tripItemID }) else {
            throw PackLedgerError.alreadyInStatus(.planned)
        }
        let inverse = PackTransition(tripItemID: tripItemID, fromStatus: last.toStatus,
                                     toStatus: last.fromStatus, occurredAt: occurredAt)
        transitions.append(inverse)
        return inverse
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
