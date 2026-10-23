import XCTest

final class GearTreeDragUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-preview-route", "tree"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func drag(_ id: String, onto name: String) {
        let handle = app.descendants(matching: .any)["gear-drag-" + id].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(handle.isHittable)
        let destination = app.staticTexts[name].firstMatch
        XCTAssertTrue(destination.isHittable)
        handle.press(forDuration: 0.3, thenDragTo: destination)
    }

    private func save() {
        app.buttons["gear-moves-review"].tap()
        XCTAssertTrue(app.navigationBars["保存修改"].waitForExistence(timeout: 5))
        capture("move-review")
        app.buttons["gear-moves-save"].tap()
        XCTAssertTrue(app.buttons["gear-moves-review"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testActivitySearchAndDetailTab() {
        app.staticTexts["Tarmac SL8 Pro"].tap()
        app.segmentedControls.buttons["活动"].tap()
        XCTAssertTrue(app.staticTexts["清晨骑行"].waitForExistence(timeout: 5))
        capture("gear-activity-tab")
        app.segmentedControls.buttons["历史"].tap()
        app.segmentedControls.buttons["活动"].tap()
        XCTAssertTrue(app.staticTexts["清晨骑行"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["活动"].tap()
        app.swipeDown()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("zzzz")
        // This phone's third-party QWERTY keyboard does not accept typeText events.
        // Tap the visible Z key and space to commit the query when injection is ignored.
        if (field.value as? String ?? "").isEmpty || field.value as? String == "查找活动" {
            let z = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.812))
            for _ in 0..<4 { z.tap() }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.881)).tap()
        }
        capture("activity-search-query")
        XCTAssertTrue(app.staticTexts["没有匹配的活动"].waitForExistence(timeout: 5))
        field.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["周末公路骑行"].waitForExistence(timeout: 5))
        capture("activity-search-restored")
    }

    func testSingleAndBatchDragOnDevice() {
        capture("initial-tree")
        drag("pedals", onto: "Propel Advanced")
        XCTAssertTrue(app.staticTexts["1 项修改"].waitForExistence(timeout: 5))
        capture("single-pending")
        save()
        capture("single-saved")

        app.buttons["gear-multiselect"].tap()
        app.staticTexts["IRC Front"].tap()
        app.staticTexts["IRC Rear"].tap()
        capture("batch-selection")
        drag("front", onto: "Tarmac SL8 Pro")
        XCTAssertTrue(app.staticTexts["2 项修改"].waitForExistence(timeout: 5))
        capture("batch-pending")
        save()
        capture("batch-saved")

        app.terminate()
        app.launchArguments += ["-preserve-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["IRC Rear"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["gear-moves-review"].exists)
        capture("saved-after-relaunch")
    }
}
