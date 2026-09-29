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
        let dataset = PackDeckDataset(
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
    func recordsHistory() {
        var ledger = PackLedger()

        let first = ledger.record(tripItemID: itemID, to: .packed, at: fixedDate)
        let second = ledger.record(
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
    func summary() {
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
        var ledger = PackLedger()
        ledger.record(tripItemID: first.id, to: .packed, at: fixedDate)

        let summary = ledger.summary(for: tripID, items: [first, second])

        #expect(summary.totalItems == 2)
        #expect(summary.packed == 1)
        #expect(summary.planned == 1)
        #expect(summary.missing == 0)
        #expect(summary.omitted == 0)
        #expect(summary.completionRatio == 0.5)
        #expect(ledger.transitions.count == 1)
    }
}

@Suite("Namespace")
struct NamespaceTests {
    @Test("milestone marker reflects domain engine")
    func milestoneMarker() {
        #expect(PackDeckKit.milestone == "M2-domain-engine")
    }
}
