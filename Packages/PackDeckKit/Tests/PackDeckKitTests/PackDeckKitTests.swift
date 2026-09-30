import Foundation
import Testing
@testable import PackDeckKit

private let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let tripID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let secondItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("Recommendation engine")
struct RecommendationEngineTests {
    private let engine = RecommendationEngine(laundryCycleDays: 7)
    private let item = KitItem(id: itemID, name: "Socks", baseQuantity: 1, category: "clothing")

    @Test("single-night trip scales by two travel days")
    func singleNightTrip() {
        let trip = Trip(id: tripID, name: "Overnight", durationNights: 1, laundryAccess: .unavailable)

        let recommendation = engine.recommend(for: item, on: trip)

        #expect(recommendation.quantity == 2)
        #expect(recommendation.reason == .fullTripWithoutLaundry)
        #expect(recommendation.reasonString == "full_trip_without_laundry")
        #expect(recommendation.confidence == .confident)
    }

    @Test("multi-week trip with laundry caps quantity at one cycle")
    func multiWeekTrip() {
        let trip = Trip(id: tripID, name: "Three weeks", durationNights: 20, laundryAccess: .available)

        let recommendation = engine.recommend(for: item, on: trip)

        #expect(recommendation.quantity == 7)
        #expect(recommendation.reason == .laundryCycleCap)
        #expect(recommendation.confidence == .confident)
    }

    @Test("no laundry scales base quantity across the full trip")
    func noLaundryTrip() {
        let twoPerDay = KitItem(id: itemID, name: "Contact lenses", baseQuantity: 2)
        let trip = Trip(id: tripID, name: "Remote trek", durationNights: 4, laundryAccess: .unavailable)

        let recommendation = engine.recommend(for: twoPerDay, on: trip)

        #expect(recommendation.quantity == 10)
        #expect(recommendation.reason == .fullTripWithoutLaundry)
    }

    @Test("missing duration keeps base quantity with explicit low confidence")
    func missingDuration() {
        let trip = Trip(id: tripID, name: "Someday", durationNights: nil, laundryAccess: .available)

        let recommendation = engine.recommend(for: item, on: trip)

        #expect(recommendation.quantity == 1)
        #expect(recommendation.reason == .unknownDurationBaseQuantity)
        #expect(
            recommendation.confidence == .lowConfidence(
                reason: RecommendationReason.unknownDurationBaseQuantity.rawValue
            )
        )
    }

    @Test("unknown laundry never presents as confident")
    func unknownLaundry() {
        let trip = Trip(id: tripID, name: "Uncertain", durationNights: 13, laundryAccess: .unknown)

        let recommendation = engine.recommend(for: item, on: trip)

        #expect(recommendation.quantity == 7)
        #expect(recommendation.reason == .unknownLaundryConservative)
        #expect(
            recommendation.confidence == .lowConfidence(
                reason: RecommendationReason.unknownLaundryConservative.rawValue
            )
        )
    }

    @Test("short trip with laundry scales by duration without cycle cap")
    func shortLaundryTrip() {
        let trip = Trip(id: tripID, name: "Short stay", durationNights: 2, laundryAccess: .available)

        let recommendation = engine.recommend(for: item, on: trip)

        #expect(recommendation.quantity == 3)
        #expect(recommendation.reason == .tripDurationScaled)
        #expect(recommendation.confidence == .confident)
    }

    @Test("nonpositive duration keeps base quantity with low confidence")
    func invalidDuration() {
        let trip = Trip(id: tripID, name: "Invalid", durationNights: 0, laundryAccess: .unavailable)

        let recommendation = engine.recommend(for: item, on: trip)

        #expect(recommendation.quantity == 1)
        #expect(recommendation.reason == .invalidDurationBaseQuantity)
        #expect(
            recommendation.confidence == .lowConfidence(
                reason: RecommendationReason.invalidDurationBaseQuantity.rawValue
            )
        )
    }

    @Test("identical inputs produce identical outputs")
    func deterministic() {
        let trip = Trip(id: tripID, name: "Repeatable", durationNights: 5, laundryAccess: .available)
        let first = engine.recommend(for: item, on: trip)
        let second = engine.recommend(for: item, on: trip)

        #expect(first == second)
    }

    @Test("invalid base quantity is normalized and signaled")
    func invalidBaseQuantity() {
        let invalid = KitItem(id: itemID, name: "Invalid", baseQuantity: 0)
        let trip = Trip(id: tripID, name: "Trip", durationNights: 1, laundryAccess: .unavailable)

        let recommendation = engine.recommend(for: invalid, on: trip)

        #expect(recommendation.quantity == 2)
        #expect(
            recommendation.confidence == .lowConfidence(
                reason: RecommendationReason.invalidBaseQuantityNormalized.rawValue
            )
        )
    }

    @Test("extreme durations and base quantities saturate without trapping")
    func overflowSaturatesExplicitly() {
        let hugeTrip = Trip(id: tripID, name: "Impossible", durationNights: Int.max, laundryAccess: .unavailable)
        let hugeBase = KitItem(id: itemID, name: "Bolts", baseQuantity: Int.max)

        let r1 = engine.recommend(for: item, on: hugeTrip)
        #expect(r1.quantity == Int.max)
        #expect(r1.confidence == .lowConfidence(reason: RecommendationReason.quantityOverflowSaturated.rawValue))

        let r2 = engine.recommend(for: hugeBase, on: Trip(id: tripID, name: "One night", durationNights: 1, laundryAccess: .unavailable))
        #expect(r2.quantity == Int.max)
        #expect(String(describing: r2.confidence).contains(RecommendationReason.quantityOverflowSaturated.rawValue))

        // Int.max nights with laundry available still caps at one cycle without trapping.
        let r3 = engine.recommend(for: item, on: Trip(id: tripID, name: "Capped", durationNights: Int.max, laundryAccess: .available))
        #expect(r3.quantity == 7)
        #expect(r3.reason == .laundryCycleCap)
    }
}

@Suite("Versioned Codable models")
struct CodableModelTests {
    @Test("full dataset round-trips with stable identities and schema versions")
    func datasetRoundTrip() throws {
        let kitItem = KitItem(id: itemID, name: "Socks", baseQuantity: 1, category: "clothing")
        let kit = KitTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Weekender",
            items: [kitItem],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let trip = Trip(
            id: tripID,
            name: "Weekend",
            durationNights: 2,
            laundryAccess: .unavailable,
            sourceKitIDs: [kit.id],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let recommendation = RecommendationEngine().recommend(for: kitItem, on: trip)
        let tripItem = TripItem(
            id: secondItemID,
            tripID: trip.id,
            sourceKitID: kit.id,
            name: kitItem.name,
            category: kitItem.category,
            recommendation: recommendation,
            createdAt: fixedDate
        )
        let transition = PackTransition(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            tripItemID: tripItem.id,
            fromStatus: .planned,
            toStatus: .packed,
            occurredAt: fixedDate
        )
        let dataset = try PackDeckDataset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            kits: [kit],
            trips: [trip],
            tripItems: [tripItem],
            transitions: [transition]
        )

        let data = try JSONEncoder().encode(dataset)
        let decoded = try JSONDecoder().decode(PackDeckDataset.self, from: data)

        #expect(decoded == dataset)
        #expect(decoded.schemaVersion == .current)
        #expect(decoded.kits.first?.schemaVersion == .current)
        #expect(decoded.trips.first?.schemaVersion == .current)
        #expect(decoded.tripItems.first?.schemaVersion == .current)
        #expect(decoded.transitions.first?.schemaVersion == .current)
    }

    @Test("dataset rejects inconsistent histories and exposes transitions append-only")
    func datasetTransitionContract() throws {
        let fabricated = PackTransition(
            tripItemID: itemID,
            fromStatus: .packed,
            toStatus: .omitted,
            occurredAt: fixedDate
        )
        #expect(throws: PackLedgerError.inconsistentHistory) {
            _ = try PackDeckDataset(transitions: [fabricated])
        }

        // Legal appends flow through recordTransition and stay replay-valid.
        var dataset = try PackDeckDataset()
        let t1 = try dataset.recordTransition(tripItemID: itemID, to: .packed, at: fixedDate)
        let t2 = try dataset.recordTransition(tripItemID: itemID, to: .missing, at: fixedDate)
        #expect(t1.fromStatus == .planned)
        #expect(t2.fromStatus == .packed)
        #expect(dataset.transitions.count == 2)

        // Duplicate append rejected, history unchanged.
        #expect(throws: PackLedgerError.alreadyInStatus(.missing)) {
            try dataset.recordTransition(tripItemID: itemID, to: .missing, at: fixedDate)
        }
        #expect(dataset.transitions.count == 2)

        // Round-trip revalidates.
        let data = try JSONEncoder().encode(dataset)
        let decoded = try JSONDecoder().decode(PackDeckDataset.self, from: data)
        #expect(decoded == dataset)
    }
}

@Suite("Append-only packing ledger")
struct PackLedgerTests {
    private let recommendation = Recommendation(
        id: itemID,
        quantity: 1,
        reason: .tripDurationScaled,
        confidence: .confident
    )

    @Test("status changes append events and retain prior events")
    func recordsHistory() throws {
        var ledger = try PackLedger()

        let first = try ledger.record(tripItemID: itemID, to: .packed, at: fixedDate)
        let second = try ledger.record(
            tripItemID: itemID,
            to: .missing,
            at: fixedDate.addingTimeInterval(1)
        )

        #expect(first.fromStatus == .planned)
        #expect(first.toStatus == .packed)
        #expect(second.fromStatus == .packed)
        #expect(second.toStatus == .missing)
        #expect(ledger.transitions.count == 2)
        #expect(ledger.transitions[0] == first)
        #expect(ledger.transitions[1] == second)
        #expect(ledger.currentStatus(for: itemID) == .missing)
    }

    @Test("summary derives current states without mutating history")
    func summary() throws {
        let first = TripItem(
            id: itemID,
            tripID: tripID,
            name: "Socks",
            recommendation: recommendation,
            createdAt: fixedDate
        )
        let secondRecommendation = Recommendation(
            id: secondItemID,
            quantity: 1,
            reason: .tripDurationScaled,
            confidence: .confident
        )
        let second = TripItem(
            id: secondItemID,
            tripID: tripID,
            name: "Charger",
            recommendation: secondRecommendation,
            createdAt: fixedDate
        )
        var ledger = try PackLedger()
        try ledger.record(tripItemID: first.id, to: .packed, at: fixedDate)

        let summary = ledger.summary(for: tripID, items: [first, second])

        #expect(summary.totalItems == 2)
        #expect(summary.packed == 1)
        #expect(summary.planned == 1)
        #expect(summary.missing == 0)
        #expect(summary.omitted == 0)
        #expect(summary.completionRatio == 0.5)
        #expect(ledger.transitions.count == 1)
    }

    @Test("duplicate and reverting transitions are rejected without touching history")
    func rejectsInvalidTransitions() throws {
        var ledger = try PackLedger()
        try ledger.record(tripItemID: itemID, to: .packed, at: fixedDate)

        // planned -> planned on a fresh item: no state movement.
        #expect(throws: PackLedgerError.alreadyInStatus(.planned)) {
            try ledger.record(tripItemID: secondItemID, to: .planned, at: fixedDate)
        }
        // packed -> packed: duplicate.
        #expect(throws: PackLedgerError.alreadyInStatus(.packed)) {
            try ledger.record(tripItemID: itemID, to: .packed, at: fixedDate)
        }
        // packed -> planned: planned is never a target status.
        #expect(throws: PackLedgerError.cannotRevertToPlanned) {
            try ledger.record(tripItemID: itemID, to: .planned, at: fixedDate)
        }
        // Rejections must not append anything.
        #expect(ledger.transitions.count == 1)
    }

    @Test("inconsistent hand-built or decoded history is rejected")
    func rejectsInconsistentHistory() throws {
        let fabricated = PackTransition(
            tripItemID: itemID,
            fromStatus: .packed,   // lie: nothing produced a packed event
            toStatus: .missing,
            occurredAt: fixedDate
        )
        #expect(throws: PackLedgerError.inconsistentHistory) {
            _ = try PackLedger(transitions: [fabricated])
        }

        // A tampered persisted ledger JSON fails at decode time.
        let valid = PackTransition(
            tripItemID: itemID,
            fromStatus: .planned,
            toStatus: .packed,
            occurredAt: fixedDate
        )
        let tampered = PackTransition(
            id: valid.id,
            tripItemID: valid.tripItemID,
            fromStatus: .omitted,   // tamper the persisted fromStatus
            toStatus: valid.toStatus,
            occurredAt: valid.occurredAt
        )
        let data = try JSONEncoder().encode(PackLedger.unchecked(transitions: [tampered]))
        #expect(throws: PackLedgerError.inconsistentHistory) {
            _ = try JSONDecoder().decode(PackLedger.self, from: data)
        }
    }
}

@Suite("Namespace")
struct NamespaceTests {
    @Test("milestone marker reflects domain engine")
    func milestoneMarker() {
        #expect(PackDeckKit.milestone == "M2-domain-engine")
    }
}
