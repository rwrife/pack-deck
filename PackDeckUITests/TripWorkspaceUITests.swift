import XCTest

final class TripWorkspaceUITests: XCTestCase {
    func testCreateTripFromKitPackAndUpdateProgress() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        app.buttons["kit.add.empty"].tap()
        let kitName = app.textFields["kit.name"]
        XCTAssertTrue(kitName.waitForExistence(timeout: 10))
        kitName.tap()
        kitName.typeText("Weekender\n")
        app.buttons["kit.item.add"].tap()
        let itemName = app.textFields["kit.item.name"].firstMatch
        XCTAssertTrue(itemName.waitForExistence(timeout: 10))
        itemName.tap()
        itemName.typeText("Socks\n")
        app.buttons["kit.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "kit.row.Weekender").firstMatch.waitForExistence(timeout: 10))

        app.tabBars.buttons["Trips"].tap()
        app.buttons["trip.add"].tap()
        let tripName = app.textFields["trip.name"]
        XCTAssertTrue(tripName.waitForExistence(timeout: 10))
        tripName.tap()
        tripName.typeText("Mountain walk\n")
        let kitToggle = app.switches["trip.kit.Weekender"]
        XCTAssertTrue(kitToggle.waitForExistence(timeout: 10))
        let control = kitToggle.switches.firstMatch.exists ? kitToggle.switches.firstMatch : kitToggle
        control.tap()
        let deadline = Date().addingTimeInterval(5)
        while !String(describing: control.value).contains("1") && Date() < deadline {
            usleep(100_000)
        }
        XCTAssertTrue(String(describing: control.value).contains("1"), "kit was not selected")
        app.buttons["trip.create"].tap()

        let tripRow = app.descendants(matching: .any).matching(identifier: "trip.row.Mountain walk").firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 10))
        tripRow.tap()
        let progress = app.staticTexts["workspace.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.label.contains("0 of 1"), progress.label)
        app.buttons["workspace.setStatus.Socks"].tap()
        app.buttons["Packed"].tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        let packedDeadline = Date().addingTimeInterval(5)
        while !progress.label.contains("1 of 1") && Date() < packedDeadline {
            usleep(100_000)
        }
        XCTAssertTrue(progress.label.contains("1 of 1"), progress.label)
        let status = app.staticTexts["workspace.status.Socks"]
        XCTAssertTrue(status.label.contains("Packed"))
        app.buttons["workspace.undo.Socks"].tap()
        let undoDeadline = Date().addingTimeInterval(5)
        while !progress.label.contains("0 of 1") && Date() < undoDeadline {
            usleep(100_000)
        }
        XCTAssertTrue(progress.label.contains("0 of 1"), progress.label)
    }
}
