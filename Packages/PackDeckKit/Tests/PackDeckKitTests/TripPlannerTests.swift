import Foundation
import Testing
@testable import PackDeckKit

@Suite("Trip planner and workspace ledger")
struct TripPlannerTests {
    @Test("kit and ad-hoc rows retain provenance, recommendation and independent identity")
    func planCopies() throws {
        let kit = KitTemplate(name: "Weekend", items: [KitItem(name: "Socks", baseQuantity: 2)])
        let planner = TripPlanner()
        let first = try planner.plan(name: "  Hike  ", durationNights: 2, laundryAccess: .unavailable,
                                     activityTags: [" hiking "], kits: [kit], adHocItems: [AdHocItem(name: "Map")])
        let second = try planner.plan(name: "Hike", durationNights: 2, laundryAccess: .unavailable,
                                      activityTags: [], kits: [kit], adHocItems: [])
        #expect(first.trip.name == "Hike")
        #expect(first.trip.activityTags == ["hiking"])
        #expect(first.items.count == 2)
        #expect(first.items[0].sourceKitID == kit.id)
        #expect(first.items[1].sourceKitID == nil)
        #expect(first.items[0].recommendation.quantity == 6)
        #expect(first.items[0].recommendation.reason == .fullTripWithoutLaundry)
        #expect(first.items[0].recommendation.id == first.items[0].id)
        #expect(first.items[0].id != second.items[0].id)
    }

    @Test("invalid inputs fail without producing partial plans")
    func rejectsInvalid() {
        let kit = KitTemplate(name: "Empty")
        #expect(throws: TripPlanError.emptyName) {
            try TripPlanner().plan(name: "  ", durationNights: 1, laundryAccess: .unknown,
                                   activityTags: [], kits: [kit], adHocItems: [])
        }
        #expect(throws: TripPlanError.emptySelection) {
            try TripPlanner().plan(name: "Trip", durationNights: 1, laundryAccess: .unknown,
                                   activityTags: [], kits: [kit], adHocItems: [])
        }
        #expect(throws: TripPlanError.emptyItemName) {
            try TripPlanner().plan(name: "Trip", durationNights: 1, laundryAccess: .unknown,
                                   activityTags: [], kits: [], adHocItems: [AdHocItem(name: " ")])
        }
    }

    @Test("undo appends a replayable inverse event, including a return to planned")
    func undo() throws {
        let id = UUID()
        var ledger = try PackLedger()
        try ledger.record(tripItemID: id, to: .packed)
        try ledger.undo(tripItemID: id)
        #expect(ledger.currentStatus(for: id) == .planned)
        #expect(ledger.transitions.count == 2)
        let replayed = try PackLedger(transitions: ledger.transitions)
        #expect(replayed.currentStatus(for: id) == .planned)
        try ledger.record(tripItemID: id, to: .missing)
        #expect(ledger.currentStatus(for: id) == .missing)
    }
}
