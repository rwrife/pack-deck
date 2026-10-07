import XCTest

final class DataTransferUITests: XCTestCase {
    func testOfflineTransferActionsAreReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        app.tabBars.buttons["Data"].tap()
        XCTAssertTrue(app.buttons["transfer.exportJSON"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["transfer.importJSON"].exists)
        app.buttons["transfer.prepareCSV"].tap()
        XCTAssertTrue(app.buttons["transfer.shareCSV"].waitForExistence(timeout: 10))
    }
}
