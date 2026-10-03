import XCTest

/// Kit-library UI tests (issue #4).
///
/// Covers the acceptance slice: create kit → add item → save → reopen →
/// verify persisted round trip, plus the delete-warning flow for kits still
/// referenced by a trip's build-time provenance.
///
/// Launch-argument seams provided by `AppStore`:
/// - `--reset-store`          wipes the on-disk database before opening
/// - `--seed-reference-trip`  adds a trip referencing every existing kit
final class KitLibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(resetStore: Bool, seedReferenceTrip: Bool = false, dynamicTypeCategory: String? = nil) {
        let application = XCUIApplication()
        var args: [String] = []
        if resetStore { args.append("--reset-store") }
        if seedReferenceTrip { args.append("--seed-reference-trip") }
        if let dynamicTypeCategory {
            args += ["-UIPreferredContentSizeCategoryName", dynamicTypeCategory]
            application.launchEnvironment["UIPreferredContentSizeCategoryName"] = dynamicTypeCategory
        }
        application.launchArguments = args
        application.launch()
        app = application
    }

    // MARK: - Round trip

    func testCreateKitAddItemSaveReopenRoundTrip() {
        launchApp(resetStore: true)

        // Empty state offers a way in.
        let emptyAdd = app.buttons["kit.add.empty"]
        XCTAssertTrue(emptyAdd.waitForExistence(timeout: 15), "empty-state New Kit button missing")
        emptyAdd.tap()

        fillEditor(name: "Carry-on Tech", itemName: "Headphones", quantityTaps: 2, category: "electronics")
        app.buttons["kit.save"].tap()

        // Back on the library: the kit row shows the saved name.
        let row = kitRow("Carry-on Tech")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved kit row missing from library")
        XCTAssertTrue(row.label.contains("Carry-on Tech"), "row label: \(row.label)")

        // Reopen: values must come back from disk, not view state.
        row.tap()
        let nameField = app.textFields["kit.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        XCTAssertEqual(nameField.value as? String, "Carry-on Tech")

        let itemField = app.textFields["kit.item.name"].firstMatch
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        XCTAssertEqual(itemField.value as? String, "Headphones")

        let categoryField = app.textFields["kit.item.category"].firstMatch
        XCTAssertTrue(categoryField.waitForExistence(timeout: 5))
        XCTAssertEqual(categoryField.value as? String, "electronics")

        // Quantity survived the round trip (1 base + 2 increments = 3).
        let qtyProbe = app.staticTexts["kit.item.quantity"]
        XCTAssertTrue(qtyProbe.waitForExistence(timeout: 5), "quantity readout missing")
        XCTAssertTrue(
            qtyProbe.label.contains("3"),
            "quantity not persisted (label: \(qtyProbe.label), value: \(String(describing: qtyProbe.value)))"
        )
    }

    func testKitPersistsAcrossAppRelaunch() {
        launchApp(resetStore: true)
        app.buttons["kit.add.empty"].tap()
        fillEditor(name: "Weekender", itemName: "Socks", quantityTaps: 0, category: "clothing")
        app.buttons["kit.save"].tap()
        XCTAssertTrue(kitRow("Weekender").waitForExistence(timeout: 10))

        // Terminate and relaunch WITHOUT reset: the row must reappear from disk.
        app.terminate()
        launchApp(resetStore: false)
        XCTAssertTrue(
            kitRow("Weekender").waitForExistence(timeout: 15),
            "kit did not persist across relaunch"
        )
    }

    // MARK: - Delete warning

    func testDeleteReferencedKitWarnsThenDeletesOnConfirm() {
        launchApp(resetStore: true)
        app.buttons["kit.add.empty"].tap()
        fillEditor(name: "Beach Kit", itemName: "Goggles", quantityTaps: 0, category: "")
        app.buttons["kit.save"].tap()
        XCTAssertTrue(kitRow("Beach Kit").waitForExistence(timeout: 10))

        // Relaunch WITHOUT reset but WITH a seeded trip referencing all kits.
        app.terminate()
        launchApp(resetStore: false, seedReferenceTrip: true)

        let row = kitRow("Beach Kit")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        // Warning explains the situation; cancel keeps the kit.
        let alert = app.alerts["Delete kit?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "delete warning alert missing")
        let warning = alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "used by 1 trip")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "warning should mention the referencing trip")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(kitRow("Beach Kit").exists)

        // Confirming deletes the kit.
        kitRow("Beach Kit").swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()

        // Kit library returns to its empty state.
        XCTAssertTrue(app.buttons["kit.add.empty"].waitForExistence(timeout: 10))
    }

    func testDeleteUnreferencedKitHasNoWarning() {
        launchApp(resetStore: true)
        app.buttons["kit.add.empty"].tap()
        fillEditor(name: "Tech Kit", itemName: "Cable", quantityTaps: 0, category: "")
        app.buttons["kit.save"].tap()

        let row = kitRow("Tech Kit")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Delete"].tap()

        // No alert should appear; the kit disappears immediately.
        XCTAssertFalse(app.alerts["Delete kit?"].exists)
        XCTAssertTrue(app.buttons["kit.add.empty"].waitForExistence(timeout: 10))
    }

    // MARK: - Accessibility contract (labels exposed to VoiceOver)

    func testInteractiveControlsExposeAccessibilityLabels() {
        launchApp(resetStore: true)

        let addButton = app.buttons["kit.add.empty"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        XCTAssertTrue(addButton.isHittable)

        addButton.tap()
        XCTAssertTrue(app.textFields["kit.name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["kit.name"].label, "Kit name")
        XCTAssertEqual(app.textFields["kit.notes"].label, "Kit notes")
        XCTAssertTrue(app.buttons["kit.save"].label.contains("Save"))

        app.buttons["kit.item.add"].tap()
        XCTAssertTrue(app.textFields["kit.item.name"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["kit.item.name"].firstMatch.label, "Item name")
    }

    /// Hit-target contract: the named interactive controls measure at least
    /// 44x44 pt (issue #4 acceptance criteria).
    func testInteractiveControlsMeetMinimumHitTargets() {
        launchApp(resetStore: true)
        let addButton = app.buttons["kit.add.empty"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        assertMinHitTarget(addButton, name: "kit.add.empty")

        addButton.tap()
        XCTAssertTrue(app.buttons["kit.save"].waitForExistence(timeout: 10))
        assertMinHitTarget(app.buttons["kit.save"], name: "kit.save")
        assertMinHitTarget(app.buttons["kit.cancel"], name: "kit.cancel")
        assertMinHitTarget(app.buttons["kit.item.add"], name: "kit.item.add")

        app.buttons["kit.item.add"].tap()
        let increment = app.buttons["kit.item.increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5), "quantity increment missing")
        assertMinHitTarget(increment, name: "kit.item.increment")
        assertMinHitTarget(app.buttons["kit.item.decrement"], name: "kit.item.decrement")
    }

    /// Dynamic Type contract: at AX5 (Accessibility Extra Extra Extra Large)
    /// the kit editor controls remain present and hittable — nothing is
    /// clipped or made unreachable by text growth.
    func testKitEditorSurvivesExtraLargeDynamicType() {
        launchApp(resetStore: true, dynamicTypeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        let addButton = app.buttons["kit.add.empty"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()

        XCTAssertTrue(app.textFields["kit.name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["kit.save"].isHittable, "Save clipped/unhittable at AX5")
        app.buttons["kit.item.add"].tap()
        XCTAssertTrue(app.textFields["kit.item.name"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kit.item.add"].isHittable, "Add Item clipped/unhittable at AX5")
    }

    // MARK: - Helpers

    /// Finds the kit row by its identifier wherever it surfaces in the
    /// hierarchy (cell or NavigationLink button depending on iOS version).
    private func kitRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "kit.row.\(name)").firstMatch
    }

    private func assertMinHitTarget(_ element: XCUIElement, name: String, file: StaticString = #filePath, line: UInt = #line) {
        let frame = element.frame
        XCTAssertTrue(
            frame.width >= 43.5 && frame.height >= 43.5,
            "\(name) hit target too small: \(frame.width)x\(frame.height)",
            file: file, line: line
        )
    }

    /// Fills the kit editor sheet: name, one item, optional quantity
    /// increments on the stepper, and an optional category. Dismisses the
    /// keyboard after each text field so bottom-bar controls stay hittable.
    private func fillEditor(
        name: String,
        itemName: String,
        quantityTaps: Int,
        category: String
    ) {
        let nameField = app.textFields["kit.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "kit editor missing")
        nameField.tap()
        nameField.typeText("\(name)\n")   // newline submits & dismisses keyboard

        app.buttons["kit.item.add"].tap()
        let itemField = app.textFields["kit.item.name"].firstMatch
        if !itemField.waitForExistence(timeout: 5) {
            // The first toolbar tap can be swallowed while the keyboard is
            // still dismissing — tap again and allow a longer settle window.
            app.buttons["kit.item.add"].tap()
            XCTAssertTrue(itemField.waitForExistence(timeout: 15), "item row never appeared")
        }
        itemField.tap()
        itemField.typeText("\(itemName)\n")

        if quantityTaps > 0 {
            let incrementButton = app.buttons["kit.item.increment"].firstMatch
            XCTAssertTrue(incrementButton.waitForExistence(timeout: 5), "quantity increment missing")
            for _ in 0..<quantityTaps {
                incrementButton.tap()
            }
            // Prove the taps landed before continuing: the readout mirrors quantity.
            let expected = 1 + quantityTaps
            let readout = app.staticTexts["kit.item.quantity"].firstMatch
            let deadline = Date().addingTimeInterval(5)
            while !readout.label.contains("\(expected)"), Date() < deadline {}
            XCTAssertTrue(
                readout.label.contains("\(expected)"),
                "quantity did not reach \(expected) after \(quantityTaps) increments (label: \(readout.label))"
            )
        }

        if !category.isEmpty {
            let categoryField = app.textFields["kit.item.category"].firstMatch
            XCTAssertTrue(categoryField.waitForExistence(timeout: 5))
            categoryField.tap()
            categoryField.typeText("\(category)\n")
        }

        // Ensure the keyboard is gone before tapping the bottom-bar toolbar.
        if app.keyboards.count > 0 {
            app.swipeDown()
        }
    }
}
