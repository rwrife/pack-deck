import Foundation
import Testing
@testable import PackDeckStore
import PackDeckKit

@Suite("Offline data transfer")
struct TransferTests {
    @Test("preview is non-mutating and contains every imported count")
    func previewCounts() throws {
        let store = try PackDeckStore.inMemory()
        let before = try store.snapshot()
        let dataset = try Fixture.dataset()
        let preview = try BackupCodec.preview(BackupCodec.encode(dataset))
        #expect(preview.formatVersion == BackupCodec.currentFormatVersion)
        #expect(preview.kitCount == 1)
        #expect(preview.tripCount == 1)
        #expect(preview.tripItemCount == 1)
        #expect(preview.transitionCount == 1)
        #expect(try store.snapshot() == before)
    }

    @Test("backup wipe restore preserves fractional timestamps and full data equality")
    func fractionalRoundTrip() throws {
        let store = try PackDeckStore.inMemory()
        let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let kit = KitTemplate(name: "Fractional", items: [KitItem(name: "Phone", baseQuantity: 1)],
                              createdAt: date, updatedAt: date)
        let plan = try TripPlanner().plan(name: "Trip", durationNights: 2, laundryAccess: .available,
                                          activityTags: ["city"], kits: [kit], adHocItems: [])
        try store.saveKit(kit)
        try store.createTrip(plan.trip, items: plan.items)
        try store.recordTransition(tripItemID: plan.items[0].id, to: .missing, at: date)
        let before = try store.snapshot()
        let data = try BackupCodec.encode(before)
        try store.replaceAll(with: try PackDeckDataset())
        try BackupCodec.restore(data, into: store)
        #expect(try store.snapshot() == before)
    }

    @Test("v1 whole-second backups remain readable")
    func legacyBackup() throws {
        let dataset = try Fixture.dataset()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(BackupCodec.Envelope(formatVersion: 1, dataset: dataset))
        #expect(try BackupCodec.decode(data) == dataset)
        #expect(try BackupCodec.preview(data).formatVersion == 1)
    }

    @Test("preview rejects duplicates and missing parents before confirmation")
    func malformedPreview() throws {
        let original = try Fixture.dataset()
        var duplicates = original
        duplicates.kits.append(original.kits[0])
        var duplicateItems = original
        duplicateItems.kits.append(KitTemplate(name: "Other", items: original.kits[0].items))
        var orphan = original
        orphan.trips = []
        let orphanEvent = try PackDeckDataset(transitions: original.transitions)
        for invalid in [duplicates, duplicateItems, orphan, orphanEvent] {
            let data = try BackupCodec.encode(invalid)
            #expect(throws: BackupCodec.BackupError.self) { _ = try BackupCodec.preview(data) }
        }
        #expect(throws: BackupCodec.BackupError.self) { _ = try BackupCodec.preview(Data("garbage".utf8)) }
        var deletedKit = original
        deletedKit.kits = [] // Provenance is deliberately historical, not a FK.
        #expect(try BackupCodec.preview(BackupCodec.encode(deletedKit)).kitCount == 0)
    }

    @Test("CSV quotes comma, quote and newline text and derives current status")
    func csvRows() throws {
        var dataset = try Fixture.dataset()
        dataset.kits[0].name = "Kit, one"
        dataset.trips[0].name = "Trip \"two\""
        dataset.tripItems[0].name = "Socks\nBlue"
        let store = try PackDeckStore.inMemory()
        try store.replaceAll(with: dataset)
        let csv = String(decoding: ChecklistCSV.encode(try store.snapshot()), as: UTF8.self)
        #expect(csv == "\"Trip name\",\"Item name\",\"Kit source\",\"Recommended quantity\",\"Status\"\r\n\"Trip \"\"two\"\"\",\"Socks\nBlue\",\"Kit, one\",\"3\",\"packed\"\r\n")
        try store.deleteKit(id: dataset.kits[0].id)
        let deleted = String(decoding: ChecklistCSV.encode(try store.snapshot()), as: UTF8.self)
        #expect(deleted.contains("\"Deleted kit\""))
    }

    @Test("CSV includes ad-hoc planned rows and guards spreadsheet formulas")
    func adhocAndFormulas() throws {
        let store = try PackDeckStore.inMemory()
        let plan = try TripPlanner().plan(name: "=SUM(A1)", durationNights: 1, laundryAccess: .unknown,
                                          activityTags: [], kits: [], adHocItems: [AdHocItem(name: "@formula")])
        try store.createTrip(plan.trip, items: plan.items)
        let csv = String(decoding: ChecklistCSV.encode(try store.snapshot()), as: UTF8.self)
        #expect(csv.contains("\"'=SUM(A1)\",\"'@formula\",\"Ad-hoc\",\"2\",\"planned\""))
        for text in ["=1", "+1", "-1", "@1", " \t=1"] {
            #expect(ChecklistCSV.field(text).hasPrefix("\"'"))
        }
        #expect(ChecklistCSV.field("ordinary") == "\"ordinary\"")
    }
}
