import Foundation
import Testing
import PackDeckKit
@testable import PackDeckStore

@Suite("Trip creation and undo persistence")
struct TripCreationTests {
    @Test("plan persists atomically, survives reload, and undo preserves event history")
    func createAndUndo() throws {
        let store = try PackDeckStore.inMemory()
        let kit = KitTemplate(name: "Weekend", items: [KitItem(name: "Socks", baseQuantity: 1)])
        try store.saveKit(kit)
        let plan = try TripPlanner().plan(name: "Trip", durationNights: 2,
                                          laundryAccess: .unavailable, activityTags: ["walk"],
                                          kits: [kit], adHocItems: [AdHocItem(name: "Map")])
        try store.createTrip(plan.trip, items: plan.items)
        var snapshot = try store.snapshot()
        #expect(snapshot.trips.count == 1)
        #expect(snapshot.tripItems.count == 2)
        #expect(snapshot.tripItems[0].sourceKitID == kit.id)
        #expect(snapshot.tripItems[1].sourceKitID == nil)
        try store.recordTransition(tripItemID: plan.items[0].id, to: .packed)
        snapshot = try store.snapshot()
        #expect(try snapshot.summary(for: plan.trip.id).packed == 1)
        try store.undoTransition(tripItemID: plan.items[0].id)
        snapshot = try store.snapshot()
        #expect(snapshot.currentStatus(for: plan.items[0].id) == .planned)
        #expect(snapshot.transitions.count == 2)
        #expect(try snapshot.summary(for: plan.trip.id).packed == 0)
        // Reusing an existing parent identity is rejected and leaves its
        // original child rows untouched.
        #expect(throws: PackDeckStoreError.corruptRow(column: "trips.id", detail: "trip already exists")) {
            try store.createTrip(plan.trip, items: plan.items)
        }
        #expect(try store.snapshot().tripItems.count == 2)
    }

    @Test("an item insertion conflict rolls back the newly created trip")
    func rollback() throws {
        let store = try PackDeckStore.inMemory()
        let kit = KitTemplate(name: "Kit", items: [KitItem(name: "Socks", baseQuantity: 1)])
        let first = try TripPlanner().plan(name: "First", durationNights: 1,
                                           laundryAccess: .unknown, activityTags: [], kits: [kit], adHocItems: [])
        try store.createTrip(first.trip, items: first.items)
        let second = Trip(name: "Second")
        let badItem = TripItem(id: first.items[0].id, tripID: second.id,
                               name: "Conflict", recommendation: first.items[0].recommendation)
        #expect(throws: (any Error).self) {
            try store.createTrip(second, items: [badItem])
        }
        #expect(try store.snapshot().trips.map(\.name) == ["First"])
    }
}
