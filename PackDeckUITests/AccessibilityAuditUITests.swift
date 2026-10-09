import XCTest

/// AX-contract audit: the simulator's accessibility tree, not a claim that
/// VoiceOver speech or an external keyboard was physically exercised.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchApp() {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments = [
            "--reset-store", "--seed-accessibility-fixture", "--accessibility-probe",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        application.launchEnvironment["UIPreferredContentSizeCategoryName"] =
            "UICTContentSizeCategoryAccessibilityXXXL"
        application.launch()
        app = application
    }

    private func evidence(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    // Collect findings at each screen without aborting the rest of the journey.
    // The test fails at the end if any were found; none are accepted as passes.
    private func audit() throws -> [String] {
        var findings: [String] = []
        try app.performAccessibilityAudit { issue in
            let diagnostic = "Accessibility audit: \(issue.compactDescription); \(issue.detailedDescription); element: \(String(describing: issue.element?.debugDescription))"
            let attachment = XCTAttachment(string: diagnostic)
            attachment.name = "audit-finding"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            print(diagnostic)
            findings.append(diagnostic)
            return true  // Defer failure so later screens are audited too.
        }
        return findings
    }

    private func assertLargeTextIsActive() {
        let probe = app.staticTexts["accessibility.dynamicType"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "Dynamic Type probe missing")
        XCTAssertTrue(probe.label.lowercased().contains("accessibility"),
                      "Requested AX5 category did not apply: \(probe.label)")
    }

    private func reveal(_ element: XCUIElement, steps: Int = 8) -> Bool {
        for _ in 0..<steps {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    func testLargestTextAndReadingOrderAcrossPrimaryScreens() throws {
        launchApp()
        assertLargeTextIsActive()
        var accumulatedFindings: [String] = []

        let kitRow = app.descendants(matching: .any)
            .matching(identifier: "kit.row.Long weekend carry-on essentials").firstMatch
        XCTAssertTrue(reveal(kitRow), "kit row unreachable at AX5")
        XCTAssertTrue(kitRow.label.contains("Long weekend carry-on essentials"), kitRow.label)
        evidence("AX5-kit-library")
        accumulatedFindings += try audit()

        kitRow.tap()
        XCTAssertTrue(app.textFields["kit.name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["kit.name"].label, "Kit name")
        XCTAssertTrue(app.buttons["kit.save"].isHittable)
        evidence("AX5-kit-editor")
        accumulatedFindings += try audit()
        app.buttons["kit.cancel"].tap()

        app.tabBars.buttons["Trips"].tap()
        let tripRow = app.descendants(matching: .any)
            .matching(identifier: "trip.row.Long weekend mountain trip").firstMatch
        XCTAssertTrue(reveal(tripRow), "trip row unreachable at AX5")
        XCTAssertTrue(tripRow.label.contains("Long weekend mountain trip"), tripRow.label)
        evidence("AX5-trip-list")
        accumulatedFindings += try audit()
        tripRow.tap()
        let progress = app.staticTexts["workspace.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.label.contains("0 of 1 packed"), progress.label)
        let status = app.staticTexts["workspace.status.Travel adapter"]
        XCTAssertTrue(reveal(status), "status text unreachable at AX5")
        XCTAssertTrue(status.label.contains("Planned"), "status must not rely on color: \(status.label)")
        XCTAssertTrue(app.buttons["workspace.setStatus.Travel adapter"].isHittable)
        evidence("AX5-packing-workspace")
        accumulatedFindings += try audit()

        app.tabBars.buttons["Data"].tap()
        XCTAssertTrue(app.buttons["transfer.exportJSON"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["transfer.importJSON"].isHittable)
        evidence("AX5-data-transfer")
        accumulatedFindings += try audit()

        XCTAssertEqual(accumulatedFindings, [], "Native audit findings recorded across screens")
    }

    func testStatusTextAndKeyboardFocusContract() throws {
        launchApp()
        assertLargeTextIsActive()
        var accumulatedFindings: [String] = []

        app.tabBars.buttons["Trips"].tap()
        app.buttons["trip.add"].tap()
        let name = app.textFields["trip.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Focused trip\n")
        XCTAssertEqual(name.value as? String, "Focused trip")
        let keyboardDeadline = Date().addingTimeInterval(5)
        while app.keyboards.count > 0, Date() < keyboardDeadline { usleep(100_000) }
        XCTAssertEqual(app.keyboards.count, 0, "Return did not release keyboard focus")
        evidence("AX5-trip-builder")
        accumulatedFindings += try audit()
        app.buttons["Cancel"].tap()

        let trip = app.descendants(matching: .any)
            .matching(identifier: "trip.row.Long weekend mountain trip").firstMatch
        XCTAssertTrue(reveal(trip))
        trip.tap()
        let menu = app.buttons["workspace.setStatus.Travel adapter"]
        XCTAssertTrue(reveal(menu))
        menu.tap()
        app.buttons["Missing"].tap()
        let status = app.staticTexts["workspace.status.Travel adapter"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Missing"), "status must include a text name: \(status.label)")
        let undo = app.buttons["workspace.undo.Travel adapter"]
        XCTAssertTrue(reveal(undo))
        undo.tap()
        XCTAssertTrue(status.label.contains("Planned"), "undo status not announced: \(status.label)")
        accumulatedFindings += try audit()

        XCTAssertEqual(accumulatedFindings, [], "Native audit findings recorded in focus/status contract")
    }
}
