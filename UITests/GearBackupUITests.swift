import XCTest

/// Requires a one-time iCloud Drive folder selection in the isolated preview library.
final class GearBackupUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-preview-route", "tree", "-preserve-preview", "-backup-qa"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openBackups() {
        app.tabBars.buttons["同步"].tap()
        app.buttons["backup-settings"].tap()
        XCTAssertTrue(app.switches["backup-enabled"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["backup-enabled"].value as? String, "1", "Select an iCloud Drive folder in the preview library before running this test.")
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["backup-versions"])
        waitForExpectations(timeout: 30)
        app.buttons["backup-versions"].tap()
    }

    private var cloudRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'backup-version-'"))
    }

    func testSelectBackupLocationOnDevice() {
        app.tabBars.buttons["同步"].tap()
        app.buttons["backup-settings"].tap()
        let toggle = app.switches["backup-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "1" {
            toggle.tap()
            capture("icloud-directory-picker")
            print(app.debugDescription)
            expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
            waitForExpectations(timeout: 180)
        }
        capture("icloud-backup-enabled")
    }

    func testAutomaticBackupAndVersionRestoreOnDevice() throws {
        openBackups()
        XCTAssertTrue(cloudRows.firstMatch.waitForExistence(timeout: 30))
        let original = cloudRows.firstMatch.identifier
        let count = cloudRows.count
        capture("backup-versions-before-change")

        app.tabBars.buttons["装备"].tap()
        app.staticTexts["Tarmac SL8 Pro"].tap()
        app.buttons["gear-detail-menu"].tap()
        app.buttons["隐藏"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts["Tarmac SL8 Pro"].exists)

        // Existing tab navigation keeps the versions screen open. Reload until the
        // five-second automatic backup has created a recovery point for the edit.
        app.tabBars.buttons["同步"].tap()
        let deadline = Date().addingTimeInterval(45)
        while cloudRows.count <= count && Date() < deadline {
            app.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        XCTAssertGreaterThan(cloudRows.count, count)
        capture("backup-created-automatically")
        app.buttons[original].tap()
        XCTAssertTrue(app.buttons["backup-restore"].waitForExistence(timeout: 10))
        capture("backup-restore-detail")
        app.buttons["backup-restore"].tap()
        app.buttons["backup-restore-confirm"].tap()
        XCTAssertTrue(app.buttons["backup-restore"].waitForNonExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["恢复前备份 · 本机"].waitForExistence(timeout: 10))
        capture("backup-restored-with-safety-version")
        app.tabBars.buttons["装备"].tap()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 10))
        capture("restored-gear-tree")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        openBackups()
        XCTAssertTrue(app.buttons[original].waitForExistence(timeout: 15))
        capture("backup-folder-access-after-relaunch")
    }
}
