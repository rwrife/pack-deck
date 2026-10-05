import Foundation

public enum TripPlanError: Error, Equatable, Sendable {
    case emptyName
    case emptySelection
    case duplicateKit
    case emptyItemName
}

/// Draft input independent of any kit. The builder copies all source rows into
/// new trip items, so later edits/deletions to a kit never rewrite a trip.
public struct AdHocItem: Sendable, Equatable {
    public var name: String
    public var baseQuantity: Int

    public init(name: String, baseQuantity: Int = 1) {
        self.name = name
        self.baseQuantity = baseQuantity
    }
}

public struct TripPlan: Sendable {
    public let trip: Trip
    public let items: [TripItem]
}

public struct TripPlanner: Sendable {
    public init() {}

    public func plan(name: String, durationNights: Int?, laundryAccess: LaundryAccess,
                     activityTags: [String], kits: [KitTemplate], adHocItems: [AdHocItem]) throws -> TripPlan {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TripPlanError.emptyName }
        guard Set(kits.map(\.id)).count == kits.count else { throw TripPlanError.duplicateKit }
        guard adHocItems.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TripPlanError.emptyItemName
        }
        guard !kits.flatMap(\.items).isEmpty || !adHocItems.isEmpty else { throw TripPlanError.emptySelection }

        let trip = Trip(name: trimmed, durationNights: durationNights,
                        laundryAccess: laundryAccess,
                        activityTags: activityTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                        sourceKitIDs: kits.map(\.id))
        let engine = RecommendationEngine()
        func copy(_ source: KitItem, kitID: UUID?) -> TripItem {
            // A new identity per copied row avoids clashes between trips or
            // two kits sharing an item UUID. Recommendations use that identity.
            let id = UUID()
            let line = KitItem(id: id, name: source.name,
                               baseQuantity: source.baseQuantity, category: source.category)
            return TripItem(id: id, tripID: trip.id, sourceKitID: kitID,
                            name: line.name, category: line.category,
                            recommendation: engine.recommend(for: line, on: trip))
        }
        let kitLines = kits.flatMap { kit in kit.items.map { copy($0, kitID: kit.id) } }
        let adHocLines = adHocItems.map {
            copy(KitItem(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                         baseQuantity: $0.baseQuantity), kitID: nil)
        }
        return TripPlan(trip: trip, items: kitLines + adHocLines)
    }
}
