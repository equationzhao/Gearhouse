import XCTest

final class GearEquipmentUITests: XCTestCase {
    func testCopyTimelineAttachmentsAndAllDayInstallationOnDevice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        app.staticTexts["Tarmac SL8 Pro"].tap()
        XCTAssertTrue(app.buttons["gear-add-attachment"].waitForExistence(timeout: 5))
        capture(app, "equipment-attachments-and-timeline")
        let tarmacTitle = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Tarmac SL8 Pro")).firstMatch
        for _ in 0..<2 {
            app.buttons["gear-detail-menu"].tap()
            app.buttons["gear-copy"].tap()
            XCTAssertTrue(app.navigationBars["复制装备"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["名称"].value as? String, "Tarmac SL8 Pro")
            XCTAssertFalse(app.staticTexts["Intervals.icu 装备"].exists)
            capture(app, "equipment-copy-form")
            app.buttons["保存"].tap()
            XCTAssertTrue(tarmacTitle.waitForExistence(timeout: 5))
            XCTAssertFalse(app.alerts.firstMatch.exists)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["库存"].waitForExistence(timeout: 5))
        let stockGroup = app.buttons["stock-group-Tarmac SL8 Pro"]
        XCTAssertFalse(stockGroup.exists)
        app.buttons["库存"].tap()
        XCTAssertTrue(stockGroup.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["×2"].exists)
        capture(app, "equipment-copy-in-stock")
        stockGroup.tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Tarmac SL8 Pro · ")).count, 2)
        capture(app, "equipment-copy-stock-expanded")
        app.buttons["使用中"].tap()
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Tarmac SL8 Pro")).firstMatch.tap()
        XCTAssertTrue(tarmacTitle.waitForExistence(timeout: 5))
        let add = app.buttons["添加装配"]
        for _ in 0..<4 { if add.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.navigationBars["添加装配"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["installation-date"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.datePickers["生效时间"].exists)
        capture(app, "installation-date-only")
        app.buttons["取消"].tap()
        XCTAssertFalse(app.staticTexts["清洁后重新煮蜡"].exists)
        capture(app, "equipment-own-history")
        let openTimeline = app.buttons["gear-timeline-open"]
        for _ in 0..<4 { if openTimeline.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(openTimeline.isHittable)
        openTimeline.tap()
        XCTAssertTrue(app.navigationBars["时间线"].waitForExistence(timeout: 5))
        let maintenance = app.staticTexts["清洁后重新煮蜡"]
        for _ in 0..<6 { if maintenance.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(maintenance.isHittable)
        XCTAssertTrue(app.staticTexts["KMC Chain"].exists)
        XCTAssertFalse(app.buttons["装备操作"].exists)
        capture(app, "equipment-timeline-page")
        app.buttons["timeline-record-event:wax-event"].tap()
        XCTAssertTrue(app.navigationBars["KMC Chain"].waitForExistence(timeout: 5))
        XCTAssertTrue(maintenance.waitForExistence(timeout: 5))
        XCTAssertTrue(maintenance.isHittable)
        capture(app, "timeline-record-destination")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["时间线"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tarmacTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(maintenance.exists)
    }
    func testAttachmentPreviewAndDeletionOnDevice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "gear-attachments"]
        app.launch()
        let receipt = app.staticTexts["发票.pdf"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 15))
        receipt.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["分享附件"].waitForExistence(timeout: 5))
        capture(app, "equipment-pdf-preview")
        app.buttons["完成"].tap()
        receipt.press(forDuration: 1)
        app.buttons["删除附件"].tap()
        app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(receipt.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["gear-add-attachment"].tap()
        capture(app, "equipment-attachment-file-picker")
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "取消", "Close", "Cancel"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testInventoryReplacementAndReinstall() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree"]
        app.launch()
        XCTAssertTrue(app.buttons["库存"].waitForExistence(timeout: 15))
        app.buttons["库存"].tap()
        app.buttons["gear-add"].tap()
        XCTAssertTrue(app.navigationBars["添加库存"].waitForExistence(timeout: 5))
        app.textFields["名称"].tap(); app.textFields["名称"].typeText("库存测试链条")
        app.buttons["gear-category"].tap()
        let category = app.buttons["链条"]
        for _ in 0..<4 { if category.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(category.isHittable); category.tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["库存测试链条"].waitForExistence(timeout: 5))
        capture(app, "inventory-stock-list")
        app.buttons["使用中"].tap()
        let chain = app.staticTexts["KMC Chain"].firstMatch
        for _ in 0..<5 { if chain.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(chain.isHittable); chain.tap()
        XCTAssertTrue(app.buttons["gear-replace"].waitForExistence(timeout: 5))
        app.buttons["gear-replace"].tap()
        app.buttons["replacement-choice"].tap()
        XCTAssertTrue(app.staticTexts["库存测试链条"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["IRC Formula Pro"].exists)
        app.staticTexts["库存测试链条"].tap()
        capture(app, "inventory-replacement-form")
        app.buttons["inventory-next"].tap()
        capture(app, "inventory-replacement-review")
        app.buttons["inventory-next"].tap()
        XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["KMC Chain"].exists)
        XCTAssertTrue(app.staticTexts["库存测试链条"].exists)
        app.buttons["库存"].tap()
        XCTAssertTrue(app.staticTexts["KMC Chain"].waitForExistence(timeout: 5))
        app.staticTexts["KMC Chain"].tap()
        XCTAssertTrue(app.buttons["gear-install"].waitForExistence(timeout: 5))
        capture(app, "inventory-old-chain-history")
        app.buttons["gear-install"].tap()
        XCTAssertTrue(app.navigationBars["装到装备"].waitForExistence(timeout: 5))
        app.buttons["inventory-parent"].tap()
        app.buttons["Tarmac SL8 Pro"].tap()
        XCTAssertTrue(app.buttons["inventory-install-mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventory-next"].isEnabled)
        app.buttons["inventory-install-mode"].tap()
        XCTAssertTrue(app.buttons["替换 库存测试链条"].waitForExistence(timeout: 5))
        app.buttons["作为新增组件"].tap()
        XCTAssertTrue(app.buttons["inventory-next"].isEnabled)
        capture(app, "inventory-reinstall-form")
        app.buttons["取消"].tap()
        let recordMenu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gear-history-menu-operation:")).firstMatch
        for _ in 0..<6 { if recordMenu.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(recordMenu.isHittable); recordMenu.tap()
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["更换链条"].waitForExistence(timeout: 5))
        capture(app, "inventory-edit-replacement")
        app.buttons["删除记录"].tap()
        app.buttons["删除"].firstMatch.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        if app.navigationBars["KMC Chain"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["使用中"].waitForExistence(timeout: 5))
        app.buttons["使用中"].tap()
        XCTAssertTrue(app.staticTexts["KMC Chain"].waitForExistence(timeout: 5))
    }
    func testCreateReplacementLocksCategoryAndPreservesOldGear() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree"]
        app.launch()
        let chain = app.staticTexts["KMC Chain"].firstMatch
        XCTAssertTrue(app.buttons["使用中"].waitForExistence(timeout: 15))
        for _ in 0..<5 { if chain.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(chain.isHittable); chain.tap()
        app.buttons["gear-replace"].tap()
        app.buttons["replacement-choice"].tap()
        app.buttons["新建装备"].tap()
        XCTAssertTrue(app.textFields["replacement-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["replacement-name"].value as? String, "KMC Chain 新件")
        XCTAssertTrue(app.staticTexts["链条"].exists)
        XCTAssertFalse(app.buttons["gear-category"].exists)
        capture(app, "inventory-new-replacement-category")
        app.buttons["inventory-next"].tap()
        app.buttons["inventory-next"].tap()
        XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["KMC Chain 新件"].exists)
        app.buttons["库存"].tap()
        XCTAssertTrue(app.staticTexts["KMC Chain"].waitForExistence(timeout: 5))
        capture(app, "inventory-grouped-stock")
    }
    func testIdenticalStockGroupingAndComponentCategorySelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree"]
        app.launch()
        XCTAssertTrue(app.buttons["库存"].waitForExistence(timeout: 15))
        app.buttons["库存"].tap()
        for _ in 0..<2 {
            app.buttons["gear-add"].tap()
            app.textFields["名称"].tap(); app.textFields["名称"].typeText("L05A-RF")
            app.buttons["gear-category"].tap()
            let pads = app.buttons["来令片"]
            for _ in 0..<6 { if pads.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(pads.isHittable); pads.tap()
            app.buttons["保存"].tap()
            XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 5))
        }
        let group = app.buttons["stock-group-L05A-RF"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["×2"].exists)
        XCTAssertFalse(app.staticTexts["L05A-RF · 1"].exists)
        capture(app, "inventory-identical-collapsed")
        group.tap()
        XCTAssertTrue(app.staticTexts["L05A-RF · 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["L05A-RF · 2"].exists)
        capture(app, "inventory-identical-expanded")
        app.staticTexts["L05A-RF · 1"].tap()
        XCTAssertTrue(app.navigationBars["L05A-RF · 1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["使用中"].tap()
        app.staticTexts["Tarmac SL8 Pro"].tap()
        app.buttons["gear-detail-menu"].tap()
        app.buttons["gear-add-component"].tap()
        XCTAssertTrue(app.buttons["component-category"].waitForExistence(timeout: 5))
        app.buttons["component-category"].tap(); app.buttons["来令片"].tap()
        let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component-choice-"))
        XCTAssertEqual(candidates.count, 2)
        candidates.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND (value == %@ OR label CONTAINS %@)", "component-selection-count", "1 件", "1 件")).firstMatch.exists)
        app.buttons["component-category"].tap(); app.buttons["轮胎"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND (value == %@ OR label CONTAINS %@)", "component-selection-count", "1 件", "1 件")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["L05A-RF · 1"].exists)
        candidates.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND (value == %@ OR label CONTAINS %@)", "component-selection-count", "2 件", "2 件")).firstMatch.exists)
        capture(app, "component-category-multiselection")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["Tarmac SL8 Pro"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["库存"].tap()
        XCTAssertFalse(group.exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "L05A-RF · ")).count, 1)
        capture(app, "inventory-identical-one-installed")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
