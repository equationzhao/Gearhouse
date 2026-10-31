import XCTest
import UIKit

final class GearEquipmentUITests: XCTestCase {
    func testActivityFiltersCombineSearchAndClearIndividually() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["活动"].waitForExistence(timeout: 15))
        app.tabBars.buttons["活动"].tap()
        XCTAssertTrue(app.buttons["activity-row-demo-virtual"].waitForExistence(timeout: 5))
        capture(app, "activities-overview-light")
        app.buttons["activities-filters"].tap()
        capture(app, "activities-filter-menu-light")
        app.buttons["室内骑行"].tap()
        XCTAssertTrue(app.buttons["activities-filter-type"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity-row-demo-virtual"].exists)
        capture(app, "activities-indoor-filter-light")
        app.buttons["activities-filters"].tap()
        app.buttons["主装备未关联"].tap()
        XCTAssertTrue(app.buttons["activities-clear-filters"].waitForExistence(timeout: 5))
        capture(app, "activities-combined-filter-empty-light")
        app.buttons["activities-filter-assignment"].tap()
        XCTAssertTrue(app.buttons["activity-row-demo-virtual"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activities-filter-type"].exists)
        app.buttons["activities-filter-type"].tap()
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForExistence(timeout: 5))
        app.buttons["activities-filters"].tap()
        app.buttons["骑行"].tap()
        let search = app.searchFields.firstMatch
        for _ in 0..<3 { if search.isHittable { break }; app.swipeDown() }
        search.tap(); search.typeText("KMC\n")
        XCTAssertTrue(app.buttons["activity-row-demo-ride2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForNonExistence(timeout: 5))
        capture(app, "activities-filter-with-search-light")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["activities-filters"].waitForExistence(timeout: 5))
        app.buttons["activities-filters"].tap()
        app.buttons["主装备未关联"].tap()
        for _ in 0..<3 { if search.isHittable { break }; app.swipeDown() }
        search.tap()
        if search.value as? String != "KMC" { search.typeText("KMC\n") }
        let clear = app.buttons["activities-clear-filters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(app.buttons["activity-row-demo-ride2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity-row-demo-ride"].exists)
        XCTAssertEqual(search.value as? String, "KMC")
        capture(app, "activities-clear-filters-keeps-search-light")
    }

    func testActivityUnlinkedFilterUpdatesAfterLinkingEquipment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "activity-list-unlinked", "-preview-dark"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["活动"].waitForExistence(timeout: 15))
        app.tabBars.buttons["活动"].tap()
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForExistence(timeout: 5))
        app.buttons["activities-filters"].tap()
        app.buttons["主装备未关联"].tap()
        XCTAssertTrue(app.buttons["activity-row-demo-virtual"].waitForNonExistence(timeout: 5))
        capture(app, "activities-unlinked-dark")
        app.buttons["activity-row-demo-ride"].tap()
        let link = app.buttons["关联装备"]
        for _ in 0..<4 { if link.isHittable { break }; app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.buttons["备用公路车"].waitForExistence(timeout: 5))
        app.buttons["备用公路车"].tap()
        XCTAssertTrue(app.navigationBars["活动详情"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["activities-clear-filters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity-row-demo-ride"].exists)
        capture(app, "activities-unlinked-resolved-dark")
        app.buttons["activities-clear-filters"].tap()
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForExistence(timeout: 5))
    }

    func testReminderOverviewSearchSnoozeAndMaintenanceReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminders-overview", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-reminders"].waitForExistence(timeout: 15))
        capture(app, "equipment-reminder-entry-light")
        app.buttons["gear-reminders"].tap()
        let due = app.buttons["reminder-overview-preview-hot-wax"]
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        capture(app, "reminders-overview-light")
        due.tap()
        let snooze = app.buttons["明天提醒"]
        for _ in 0..<5 { if snooze.isHittable { break }; app.swipeUp() }
        snooze.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let search = app.searchFields.firstMatch
        for _ in 0..<8 { if search.isHittable { break }; app.swipeDown() }
        search.tap(); search.typeText("煮蜡\n")
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        XCTAssertTrue(due.label.contains("稍后提醒"))
        capture(app, "reminders-snoozed-light")
        due.tap()
        let record = app.buttons["reminder-record"]
        for _ in 0..<4 { if record.isHittable { break }; app.swipeUp() }
        record.tap()
        XCTAssertTrue(app.navigationBars["添加记录"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        XCTAssertFalse(due.label.contains("稍后提醒"))
        capture(app, "reminders-maintenance-resets-overview-light")
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        search.tap(); search.typeText("Tarmac\n")
        XCTAssertTrue(app.buttons["reminder-overview-preview-snoozed"].waitForExistence(timeout: 5))
        XCTAssertFalse(due.exists)
        capture(app, "reminders-equipment-search-light")
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "no-such-reminder\n")
        let clear = app.buttons["reminders-clear-search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        capture(app, "reminders-search-empty-light")
        clear.tap()
        XCTAssertTrue(app.buttons["reminder-overview-preview-missing"].waitForExistence(timeout: 5))
        let completed = app.buttons["reminder-overview-preview-completed"]
        for _ in 0..<8 { if completed.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(completed.isHittable)
        XCTAssertTrue(completed.label.contains("已完成"))
        capture(app, "reminders-overview-later-light")
    }

    func testReminderOverviewCanCreateReminderFromEmptyState() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminders-empty", "-preview-dark"]
        app.launch()
        let add = app.buttons["reminders-empty-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        capture(app, "reminders-empty-dark")
        add.tap()
        XCTAssertTrue(app.navigationBars["选择装备"].waitForExistence(timeout: 5))
        let search = app.searchFields["查找装备"]
        for _ in 0..<3 { if search.isHittable { break }; app.swipeDown() }
        search.tap(); search.typeText("KMC\n")
        let gear = app.buttons["reminder-choose-gear-chain"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        capture(app, "reminders-choose-equipment-dark")
        gear.tap()
        XCTAssertTrue(app.navigationBars["添加提醒"].waitForExistence(timeout: 5))
        let title = app.descendants(matching: .any)["reminder-title"].firstMatch
        XCTAssertTrue(title.exists)
        title.tap(); title.typeText("检查链条")
        app.buttons["保存"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons["不允许"]
        if deny.waitForExistence(timeout: 3) { deny.tap() }
        XCTAssertTrue(app.navigationBars["添加提醒"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "reminder-overview-", "检查链条")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "reminders-created-dark")
    }

    func testReminderOverviewAndActivityFiltersWithAccessibilityText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminders-overview", "-preview-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-reminders"].waitForExistence(timeout: 15))
        app.buttons["gear-reminders"].tap()
        XCTAssertTrue(app.buttons["reminder-overview-preview-hot-wax"].waitForExistence(timeout: 5))
        capture(app, "reminders-overview-accessibility-dark")
        app.swipeUp()
        capture(app, "reminders-overview-accessibility-later-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["活动"].tap()
        XCTAssertTrue(app.buttons["activities-filters"].waitForExistence(timeout: 5))
        app.buttons["activities-filters"].tap()
        app.buttons["待确认或同步"].tap()
        XCTAssertTrue(app.buttons["activities-clear-filters"].waitForExistence(timeout: 5))
        capture(app, "activities-filter-accessibility-dark")
        app.buttons["activities-filters"].tap()
        app.buttons["骑行"].tap()
        XCTAssertTrue(app.buttons["activities-filter-type"].waitForExistence(timeout: 5))
        capture(app, "activities-combined-filter-accessibility-dark")
        app.buttons["activities-clear-filters"].tap()
        XCTAssertTrue(app.buttons["activity-row-preview-last-ride"].waitForExistence(timeout: 5))
        capture(app, "activities-list-accessibility-dark")
    }

    func testReminderGearPickerShowsPhotoAndCanCancel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "equipment-design", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-reminders"].waitForExistence(timeout: 15))
        app.buttons["gear-reminders"].tap()
        app.buttons["reminders-add"].tap()
        XCTAssertTrue(app.navigationBars["选择装备"].waitForExistence(timeout: 5))
        let search = app.searchFields["查找装备"]
        for _ in 0..<3 { if search.isHittable { break }; app.swipeDown() }
        search.tap(); search.typeText("Tarmac\n")
        XCTAssertTrue(app.buttons["reminder-choose-gear-tarmac"].waitForExistence(timeout: 5))
        capture(app, "reminders-picker-photo-light")
        if app.buttons["close"].exists { app.buttons["close"].tap() }
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["添加提醒"].exists)
        app.buttons["reminders-add"].tap()
        XCTAssertTrue(app.navigationBars["选择装备"].waitForExistence(timeout: 5))
        capture(app, "reminders-picker-reopened-light")
        app.buttons["取消"].tap()
    }

    func testReminderOverviewAndActivityFiltersAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminders-overview", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-reminders"].waitForExistence(timeout: 15))
        app.buttons["gear-reminders"].tap()
        XCTAssertTrue(app.buttons["reminder-overview-preview-hot-wax"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
        app.buttons["reminders-add"].tap()
        XCTAssertTrue(app.navigationBars["选择装备"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
        app.buttons["取消"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["活动"].tap()
        app.buttons["activities-filters"].tap()
        app.buttons["骑行"].tap()
        XCTAssertTrue(app.buttons["activities-filter-type"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
        capture(app, "activities-filter-accessibility-audit-light")
    }
    func testActivityListAndAssignmentWithLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["活动"].waitForExistence(timeout: 15))
        app.tabBars.buttons["活动"].tap()
        XCTAssertTrue(app.staticTexts["周末公路骑行"].waitForExistence(timeout: 5))
        capture(app, "activity-list-large-text-light")
        app.staticTexts["周末公路骑行"].tap()
        let shoe = app.buttons["activity-shoe"]
        for _ in 0..<6 { if shoe.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(shoe.isHittable)
        shoe.tap(); app.buttons["RC7"].tap()
        app.buttons["activity-save"].tap()
        XCTAssertFalse(app.buttons["activity-save"].isEnabled)
        capture(app, "activity-assignment-large-text-light")
        app.terminate()
        app.launchArguments = ["-preview-route", "activity-conflict", "-preview-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.navigationBars["活动详情"].waitForExistence(timeout: 15))
        let adopt = app.buttons["activity-use-remote"]
        for _ in 0..<6 { if adopt.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(adopt.isHittable)
        capture(app, "activity-conflict-large-text-dark")
        app.swipeUp()
        capture(app, "activity-conflict-actions-large-text-dark")
        adopt.tap()
        XCTAssertTrue(adopt.waitForNonExistence(timeout: 5))
    }
    func testGearFormKeepsRemovedICULinkVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "gear-edit-missing-remote", "-preview-dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["编辑装备"].waitForExistence(timeout: 15))
        let refresh = app.buttons["gear-refresh-remote"]
        for _ in 0..<6 { if refresh.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(refresh.isHittable)
        XCTAssertTrue(app.staticTexts["保留现有关联"].exists)
        capture(app, "gear-removed-remote-link-dark")
        app.buttons["保存"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testActivityShoeSaveKeepsMainAndClearsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "activity", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-shoe"].waitForExistence(timeout: 15))
        app.buttons["activity-shoe"].tap()
        app.buttons["RC7"].tap()
        app.buttons["activity-save"].tap()
        XCTAssertFalse(app.buttons["activity-save"].isEnabled)
        XCTAssertFalse(app.buttons["activity-cancel"].exists)
        XCTAssertFalse(app.staticTexts["activity-pending"].exists)
        XCTAssertTrue(app.staticTexts["Propel Advanced"].firstMatch.exists)
        capture(app, "activity-shoe-saved-light")
        app.terminate()
        app.launchArguments += ["-preserve-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-shoe"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["activity-shoe"].label.contains("RC7"))
        XCTAssertFalse(app.buttons["activity-save"].isEnabled)
    }
    func testActivityConflictAdoptsICUAndKeepsShoes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "activity-conflict", "-preview-dark"]
        app.launch()
        let adopt = app.buttons["activity-use-remote"]
        XCTAssertTrue(adopt.waitForExistence(timeout: 15))
        for _ in 0..<3 { if adopt.isHittable { break }; app.swipeUp() }
        capture(app, "activity-conflict-dark")
        adopt.tap()
        XCTAssertTrue(adopt.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["activity-pending"].exists)
        for _ in 0..<3 { if app.buttons["activity-shoe"].isHittable { break }; app.swipeDown() }
        XCTAssertTrue(app.buttons["activity-shoe"].label.contains("RC7"))
        XCTAssertFalse(app.buttons["activity-save"].isEnabled)
        capture(app, "activity-adopted-remote-dark")
    }
    func testActivityPendingShoeSaveDoesNotRetryMain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "activity-pending"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-shoe"].waitForExistence(timeout: 15))
        app.buttons["activity-shoe"].tap()
        app.buttons["无"].tap()
        app.buttons["activity-save"].tap()
        XCTAssertFalse(app.buttons["activity-save"].isEnabled)
        XCTAssertFalse(app.buttons["activity-cancel"].exists)
        XCTAssertTrue(app.staticTexts["activity-pending"].exists)
        XCTAssertFalse(app.staticTexts["请连接 Intervals.icu"].exists)
        app.swipeUp()
        capture(app, "activity-pending-local-save")
    }
    func testActivityUnknownRemoteCanLinkExistingEquipment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "activity-unlinked", "-preview-light"]
        app.launch()
        let link = app.buttons["关联装备"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        for _ in 0..<3 { if link.isHittable { break }; app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.navigationBars["关联装备"].waitForExistence(timeout: 5))
        capture(app, "activity-link-remote-equipment")
        XCTAssertTrue(app.buttons["刷新 ICU 装备"].exists)
        XCTAssertTrue(app.buttons["新建装备"].exists)
        app.buttons["备用公路车"].tap()
        XCTAssertTrue(app.navigationBars["活动详情"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["关联装备"].exists)
        XCTAssertTrue(app.buttons["activity-main"].label.contains("备用公路车"))
        capture(app, "activity-linked-existing-equipment")
    }
    func testCopyTimelineAttachmentsAndAllDayInstallationOnDevice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        app.staticTexts["Tarmac SL8 Pro"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["gear-distance-metric"].firstMatch.waitForExistence(timeout: 5))
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
        let add = app.buttons["gear-add-record"]
        for _ in 0..<4 { if add.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        add.tap()
        app.buttons["添加装配"].tap()
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
        for _ in 0..<5 { if receipt.isHittable { break }; app.swipeUp() }
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
        app.buttons["gear-detail-menu"].tap()
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
        capture(app, "inventory-old-chain-history")
        app.buttons["gear-detail-menu"].tap()
        XCTAssertTrue(app.buttons["gear-install"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.alerts["放弃未保存的更改？"].waitForExistence(timeout: 5))
        app.alerts["放弃未保存的更改？"].buttons["inventory-discard"].firstMatch.tap()
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
    func testTimedReplacementCancelReviewAndSave() {
        runTimedReplacement(arguments: [])
    }
    func testTimedInstallationCancelKeepsDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "installation"]
        app.launch()
        let precision = app.switches["installation-precise"]
        XCTAssertTrue(precision.waitForExistence(timeout: 15))
        precision.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["installation-time"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "installation-timed-edit")
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(app.buttons["继续编辑"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["继续编辑"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["installation-time"].firstMatch.exists)
        app.buttons["取消"].firstMatch.tap()
        app.buttons["放弃更改"].firstMatch.tap()
    }
    func testTimedReplacementLargeTextDark() {
        runTimedReplacement(arguments: ["-preview-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
    }
    private func runTimedReplacement(arguments: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["使用中"].waitForExistence(timeout: 15))
        let chain = app.staticTexts["KMC Chain"].firstMatch
        for _ in 0..<5 { if chain.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(chain.isHittable); chain.tap()
        app.buttons["gear-detail-menu"].tap(); app.buttons["gear-replace"].tap()
        let precision = app.switches["inventory-precise"]
        XCTAssertTrue(precision.waitForExistence(timeout: 5))
        for _ in 0..<5 { if precision.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(precision.isHittable); precision.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        for _ in 0..<4 { if app.descendants(matching: .any)["inventory-time"].firstMatch.exists { break }; app.swipeUp() }
        XCTAssertTrue(app.descendants(matching: .any)["inventory-time"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "inventory-timed-edit")
        app.buttons["inventory-cancel"].tap()
        XCTAssertTrue(app.buttons["inventory-continue-editing"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["inventory-continue-editing"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inventory-time"].firstMatch.exists)
        app.buttons["replacement-choice"].tap(); app.buttons["新建装备"].tap()
        app.buttons["inventory-next"].tap()
        XCTAssertTrue(app.staticTexts["生效时间"].waitForExistence(timeout: 5))
        capture(app, "inventory-timed-review")
        app.buttons["inventory-cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inventory-time"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["inventory-next"].tap(); app.buttons["inventory-next"].tap()
        XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 10))
        let newGear = app.staticTexts["KMC Chain 新件"].firstMatch
        XCTAssertTrue(newGear.waitForExistence(timeout: 5)); newGear.tap()
        let timeline = app.buttons["gear-timeline-open"]
        for _ in 0..<8 { if timeline.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(timeline.isHittable); timeline.tap()
        XCTAssertTrue(app.navigationBars["时间线"].waitForExistence(timeout: 5))
        let timed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "+08:00")).firstMatch
        XCTAssertTrue(timed.waitForExistence(timeout: 5))
        capture(app, "inventory-timed-history")
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
        app.buttons["gear-detail-menu"].tap()
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
    func testEquipmentVisualHierarchyAndPhotoPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "equipment-design", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["gear-drag-pedals"].firstMatch.exists)
        capture(app, "equipment-home-light")
        app.buttons["gear-toggle-propel"].tap()
        XCTAssertFalse(app.staticTexts["IRC Front"].exists)
        capture(app, "equipment-home-collapsed")
        app.buttons["gear-toggle-propel"].tap()
        XCTAssertTrue(app.staticTexts["IRC Front"].exists)
        app.buttons["gear-multiselect"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["gear-drag-pedals"].firstMatch.exists)
        capture(app, "equipment-home-editing")
        app.buttons["gear-multiselect"].tap()
        app.staticTexts["Tarmac SL8 Pro"].tap()
        XCTAssertTrue(app.buttons["gear-cover-photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["检查胎压"].exists)
        capture(app, "equipment-detail-light")
        reveal(app, element: app.buttons["gear-timeline-open"])
        XCTAssertTrue(app.buttons["gear-timeline-open"].isHittable)
        app.segmentedControls.buttons["活动"].tap()
        reveal(app, element: app.staticTexts["清晨骑行"])
        XCTAssertTrue(app.staticTexts["清晨骑行"].waitForExistence(timeout: 5))
        capture(app, "equipment-detail-activities")
        for _ in 0..<8 { if app.segmentedControls.buttons["历史"].isHittable { break }; app.swipeDown() }
        app.segmentedControls.buttons["历史"].tap()
        for _ in 0..<8 { if app.buttons["gear-photo-actions"].isHittable { break }; app.swipeDown() }
        app.buttons["gear-photo-actions"].tap()
        XCTAssertTrue(app.buttons["gear-add-photo"].waitForExistence(timeout: 5))
        capture(app, "equipment-photo-actions")
        app.buttons["gear-manage-photos"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gear-photo-cover-")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "equipment-photo-manager")
        app.buttons["完成"].tap()
        app.buttons["完成"].tap()
        app.buttons["gear-cover-photo"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        capture(app, "equipment-cover-gallery")
        app.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["库存"].tap()
        XCTAssertTrue(app.buttons["stock-group-L05A-RF"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["×2"].exists)
        capture(app, "equipment-inventory-light")

        app.terminate()
        app.launchArguments = ["-preview-route", "equipment-design", "-preview-dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        capture(app, "equipment-home-dark")
        app.staticTexts["Tarmac SL8 Pro"].tap()
        XCTAssertTrue(app.buttons["gear-cover-photo"].waitForExistence(timeout: 10))
        capture(app, "equipment-detail-dark")

        app.terminate()
        app.launchArguments = ["-preview-route", "gear", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["CL II"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["gear-timeline-open"].isHittable)
        capture(app, "equipment-no-cover-light")
        app.terminate()
        app.launchArguments = ["-preview-route", "gear", "-preview-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.navigationBars["CL II"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["gear-cover-photo"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gear-distance-metric"].firstMatch.exists)
        capture(app, "equipment-no-cover-large-text")
        app.terminate()
        app.launchArguments = ["-preview-route", "equipment-design", "-preview-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        capture(app, "equipment-home-large-text")
        app.buttons["gear-multiselect"].tap()
        capture(app, "equipment-home-large-text-editing")
        app.terminate()
        app.launchArguments = ["-preview-route", "equipment-design", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
    }
    func testEquipmentLongStatisticsAndRecordsRemainReadable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "equipment-long-content", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let name = "Tarmac SL8 Pro · Shimano Ultegra Di2"
            let title = "更换链条并检查前后变速器、飞轮与盘片的磨损情况"
            let notes = "清洁传动系统后重新煮蜡，检查前后变速器、飞轮、盘片与链条的磨损情况。随后检查轮组、外胎、碟片与来令片，并确认所有螺丝已经按规定扭矩锁紧。"
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))
            app.staticTexts[name].tap()
            let duration = app.descendants(matching: .any)["gear-duration-metric"].firstMatch
            XCTAssertTrue(duration.waitForExistence(timeout: 5))
            capture(app, "long-detail-history-" + appearance)
            let caption = app.staticTexts["累计距离"].firstMatch
            XCTAssertGreaterThanOrEqual(caption.frame.minX, app.buttons["gear-cover-photo"].frame.minX + 12)
            XCTAssertGreaterThanOrEqual(duration.frame.minX, 28)
            XCTAssertLessThanOrEqual(duration.frame.maxX, app.frame.maxX - 16)
            let record = app.staticTexts[title].firstMatch
            let recordNotes = app.staticTexts[notes].firstMatch
            for _ in 0..<6 {
                if record.isHittable && recordNotes.isHittable && recordNotes.frame.maxY < app.tabBars.firstMatch.frame.minY { break }
                app.swipeUp()
            }
            capture(app, "long-detail-record-" + appearance)
            XCTAssertTrue(record.isHittable)
            XCTAssertTrue(recordNotes.isHittable)
            XCTAssertGreaterThan(recordNotes.frame.height, 40)
            XCTAssertLessThanOrEqual(record.frame.maxX, app.frame.maxX - 20)
            XCTAssertLessThanOrEqual(recordNotes.frame.maxY, app.tabBars.firstMatch.frame.minY - 4)
            let activities = app.segmentedControls.buttons["活动"]
            for _ in 0..<6 { if activities.isHittable { break }; app.swipeDown() }
            activities.tap()
            capture(app, "long-detail-activities-" + appearance)
            let attachment = app.buttons["gear-add-attachment"]
            for _ in 0..<6 { if attachment.isHittable && attachment.frame.maxY < app.tabBars.firstMatch.frame.minY { break }; app.swipeUp() }
            capture(app, "long-detail-bottom-" + appearance)
            XCTAssertTrue(attachment.isHittable)
            XCTAssertLessThanOrEqual(attachment.frame.maxY, app.tabBars.firstMatch.frame.minY - 4)
            app.terminate()
        }
    }
    func testReminderProgressAppearanceAndMaintenanceReset() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "reminder-progress", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let drip = app.descendants(matching: .any)["reminder-row-preview-drip"].firstMatch
            XCTAssertTrue(drip.waitForExistence(timeout: 15))
            capture(app, "reminder-equipment-" + appearance)
            reveal(app, element: drip)
            drip.tap()
            let distance = app.descendants(matching: .any)["reminder-progress-preview-drip-distance"].firstMatch
            let days = app.descendants(matching: .any)["reminder-progress-preview-drip-days"].firstMatch
            XCTAssertTrue(distance.waitForExistence(timeout: 5))
            XCTAssertTrue((distance.value as? String ?? "").contains("186 / 300 km"))
            XCTAssertTrue((days.value as? String ?? "").contains("18 / 30 天"))
            capture(app, "reminder-detail-" + appearance)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let due = app.descendants(matching: .any)["reminder-row-preview-hot-wax"].firstMatch
            reveal(app, element: due)
            capture(app, "reminder-list-" + appearance)
            due.tap()
            let dueDistance = app.descendants(matching: .any)["reminder-progress-preview-hot-wax-distance"].firstMatch
            XCTAssertTrue(dueDistance.waitForExistence(timeout: 5))
            XCTAssertTrue((dueDistance.value as? String ?? "").contains("412 / 400 km"))
            capture(app, "reminder-overdue-" + appearance)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let scheduled = app.descendants(matching: .any)["reminder-row-preview-date"].firstMatch
            reveal(app, element: scheduled)
            scheduled.tap()
            XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["reminder-progress-preview-date-distance"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["reminder-progress-preview-date-days"].firstMatch.exists)
            capture(app, "reminder-date-" + appearance)
            app.terminate()
        }

        app.launchArguments = ["-preview-route", "reminder-progress", "-preview-light"]
        app.launch()
        let drip = app.descendants(matching: .any)["reminder-row-preview-drip"].firstMatch
        XCTAssertTrue(drip.waitForExistence(timeout: 15))
        reveal(app, element: drip); drip.tap()
        let record = app.buttons["reminder-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        reveal(app, element: record); record.tap()
        XCTAssertTrue(app.navigationBars["添加记录"].waitForExistence(timeout: 5))
        capture(app, "reminder-record-drip")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
        let resetDistance = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND value CONTAINS %@", "reminder-progress-preview-drip-distance", "0 / 300 km")).firstMatch
        XCTAssertTrue(resetDistance.waitForExistence(timeout: 5))
        let resetDays = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND value CONTAINS %@", "reminder-progress-preview-drip-days", "0 / 30 天")).firstMatch
        XCTAssertTrue(resetDays.exists)
        capture(app, "reminder-new-cycle")
        let enabled = app.switches["reminder-enabled"]
        reveal(app, element: enabled)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "identifier == %@ AND value == %@", "reminder-enabled", "0")).firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<4 { if app.staticTexts["已暂停"].isHittable { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["已暂停"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["reminder-progress-preview-drip-distance"].firstMatch.exists)
        capture(app, "reminder-disabled")
        reveal(app, element: enabled)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "identifier == %@ AND value == %@", "reminder-enabled", "1")).firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<4 { if resetDistance.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(resetDistance.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, "reminder-reenabled")
    }

    func testReminderProgressAdditionalStatesAndLongTitle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminder-progress-states", "-preview-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["reminder-row-preview-drip"].firstMatch.waitForExistence(timeout: 15))
        for id in ["preview-total", "preview-paused", "preview-missing", "preview-long"] {
            let row = app.descendants(matching: .any)["reminder-row-" + id].firstMatch
            reveal(app, element: row)
            capture(app, "reminder-row-" + id)
            row.tap()
            let distance = app.descendants(matching: .any)["reminder-progress-" + id + "-distance"].firstMatch
            if id == "preview-paused" {
                XCTAssertTrue(app.staticTexts["已暂停"].waitForExistence(timeout: 5))
                XCTAssertFalse(distance.exists)
            } else if id == "preview-missing" {
                XCTAssertTrue(app.staticTexts["起点记录已删除，请重新选择"].waitForExistence(timeout: 5))
                XCTAssertFalse(distance.exists)
            } else {
                XCTAssertTrue(distance.waitForExistence(timeout: 5))
                XCTAssertTrue((distance.value as? String ?? "").contains(id == "preview-total" ? "412" : "186 / 300 km"))
                XCTAssertLessThanOrEqual(distance.frame.maxX, app.frame.maxX - 16)
                XCTAssertGreaterThanOrEqual(distance.frame.minX, 16)
            }
            capture(app, "reminder-detail-" + id)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testActivitySearchFindsEquipmentAndClearsEmptyResults() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["活动"].waitForExistence(timeout: 15))
        app.tabBars.buttons["活动"].tap()
        let search = app.searchFields.firstMatch
        for _ in 0..<3 { if search.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Propel")
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity-row-demo-virtual"].exists)
        XCTAssertFalse(app.buttons["activity-row-demo-ride2"].exists)
        capture(app, "activities-equipment-search")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "KMC")
        XCTAssertTrue(app.buttons["activity-row-demo-ride2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity-row-demo-ride"].exists)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "no-such-activity\n")
        let clear = app.buttons["activities-clear-search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        capture(app, "activities-search-empty")
        clear.tap()
        XCTAssertTrue(app.buttons["activity-row-demo-ride"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity-row-demo-ride2"].exists)
    }

    func testReminderEditorDismissesNumberKeyboardAndConfirmsDiscard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminder-progress-detail", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 15))
        app.buttons["编辑"].tap()
        let days = app.textFields["reminder-days"]
        XCTAssertTrue(days.waitForExistence(timeout: 5))
        XCTAssertTrue(days.isHittable)
        days.tap()
        let done = app.buttons["reminder-dismiss-keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let title = app.descendants(matching: .any)["reminder-title"].firstMatch
        title.tap(); title.typeText("检查")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃更改"].waitForExistence(timeout: 5))
        capture(app, "reminder-editor-discard")
        app.buttons["继续编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑提醒"].exists)
        app.buttons["取消"].tap()
        app.buttons["放弃更改"].tap()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
        app.buttons["编辑"].tap()
        let savedTitle = app.descendants(matching: .any)["reminder-title"].firstMatch
        XCTAssertTrue(savedTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(savedTitle.value as? String, "滴蜡")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 5))
    }

    func testEquipmentSelectionAndVisibleFilters() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-multiselect"].waitForExistence(timeout: 15))
        app.buttons["gear-filters"].tap()
        app.buttons["显示已隐藏"].tap()
        let hiddenFilter = app.buttons["gear-filter-hidden"]
        XCTAssertTrue(hiddenFilter.waitForExistence(timeout: 5))
        capture(app, "equipment-visible-filter")
        hiddenFilter.tap()
        XCTAssertFalse(hiddenFilter.exists)
        app.buttons["gear-multiselect"].tap()
        XCTAssertTrue(app.staticTexts["gear-selection-count"].waitForExistence(timeout: 5))
        app.buttons["gear-select-visible"].tap()
        let selected = app.staticTexts["gear-selection-count"].label
        XCTAssertFalse(selected.contains(" 0 "))
        XCTAssertTrue(app.buttons["gear-selection-store"].exists)
        capture(app, "equipment-select-visible")
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("no-such-equipment\n")
        let clear = app.buttons["gear-clear-filters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["gear-selection-count"].label, selected)
        capture(app, "equipment-filter-retains-selection")
        clear.tap()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 5))
        app.buttons["gear-clear-selection"].tap()
        XCTAssertEqual(app.staticTexts["gear-selection-count"].label, "已选 0 件")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        app.buttons["gear-multiselect"].tap()
        XCTAssertFalse(app.staticTexts["gear-selection-count"].exists)
    }

    func testComponentSearchRetainsSelectionAndDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
        app.staticTexts["Tarmac SL8 Pro"].tap()
        app.buttons["gear-detail-menu"].tap(); app.buttons["gear-add-component"].tap()
        let search = app.textFields["component-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("IRC\n")
        let choice = app.buttons["component-choice-front"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        let selected = app.descendants(matching: .any)["component-selection-count"].firstMatch
        XCTAssertTrue(selected.exists)
        search.tap(); search.typeText("not-found\n")
        XCTAssertTrue(app.staticTexts["component-empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(selected.exists)
        capture(app, "component-search-selection-dark")
        app.buttons["component-clear-search"].tap()
        XCTAssertTrue(choice.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃更改"].waitForExistence(timeout: 5))
        app.buttons["继续编辑"].tap()
        XCTAssertTrue(selected.exists)
        app.buttons["取消"].tap(); app.buttons["放弃更改"].tap()
        XCTAssertTrue(app.navigationBars["Tarmac SL8 Pro"].waitForExistence(timeout: 5))
    }

    func testGearAndMaintenanceDraftProtection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-add"].waitForExistence(timeout: 15))
        app.buttons["gear-add"].tap()
        let name = app.textFields["gear-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        name.tap(); name.typeText("Test gear")
        let done = app.buttons["gear-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃更改"].waitForExistence(timeout: 5))
        capture(app, "gear-draft-discard")
        app.buttons["继续编辑"].tap()
        XCTAssertEqual(name.value as? String, "Test gear")
        app.buttons["取消"].tap(); app.buttons["放弃更改"].tap()
        XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Test gear"].exists)
        app.staticTexts["Tarmac SL8 Pro"].tap()
        app.buttons["gear-add-record"].tap(); app.buttons["gear-create-event"].tap()
        let notes = app.descendants(matching: .any)["event-notes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap(); notes.typeText("检查链条与轮组")
        app.buttons["event-keyboard-done"].tap()
        capture(app, "maintenance-draft-light")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃更改"].waitForExistence(timeout: 5))
        app.buttons["继续编辑"].tap()
        XCTAssertEqual(notes.value as? String, "检查链条与轮组")
        app.buttons["取消"].tap(); app.buttons["放弃更改"].tap()
        XCTAssertTrue(app.navigationBars["Tarmac SL8 Pro"].waitForExistence(timeout: 5))
    }

    func testSyncAndBackupAppearanceAndNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "tree", appearance == "dark" ? "-preview-dark" : "-preview-light", "-backup-qa", "-hold-backup-export"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["同步"].waitForExistence(timeout: 15))
            app.tabBars.buttons["同步"].tap()
            XCTAssertTrue(app.staticTexts["尚未连接"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["sync-connect"].isEnabled)
            capture(app, "sync-disconnected-" + appearance)
            let backup = app.buttons["backup-settings"]
            reveal(app, element: backup); backup.tap()
            XCTAssertTrue(app.buttons["backup-import"].waitForExistence(timeout: 5))
            let export = app.buttons["backup-export"]
            reveal(app, element: export)
            XCTAssertTrue(export.isEnabled)
            capture(app, "backup-settings-" + appearance)
            export.tap()
            let cancelPreparation = app.buttons["backup-file-cancel"]
            reveal(app, element: cancelPreparation)
            let preparing = app.descendants(matching: .any).matching(identifier: "backup-file-progress").firstMatch
            XCTAssertTrue(preparing.waitForExistence(timeout: 10))
            XCTAssertFalse(export.isEnabled)
            XCTAssertFalse(app.buttons["backup-import"].isEnabled)
            capture(app, "backup-export-preparing-" + appearance)
            cancelPreparation.tap()
            XCTAssertTrue(preparing.waitForNonExistence(timeout: 10))
            XCTAssertTrue(export.isEnabled)
            XCTAssertFalse(app.staticTexts["backup-file-error"].exists)
            reveal(app, element: export); export.tap()
            XCTAssertTrue(preparing.waitForNonExistence(timeout: 15))
            XCTAssertFalse(cancelPreparation.exists)
            let exportFilename = app.textFields["DOCPicker.filenameTextField"]
            XCTAssertTrue(exportFilename.waitForExistence(timeout: 15))
            XCTAssertTrue((exportFilename.value as? String)?.hasPrefix("Gearhouse-") == true)
            XCTAssertTrue(app.buttons["DOCPicker.actionButton"].exists)
            capture(app, "backup-export-ready-" + appearance)
            let sheetTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075))
            let sheetBottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            sheetTop.press(forDuration: 0.1, thenDragTo: sheetBottom)
            XCTAssertTrue(exportFilename.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.buttons["backup-import"].waitForExistence(timeout: 10))
            XCTAssertFalse(preparing.exists)
            capture(app, "backup-export-cancelled-" + appearance)
            let versions = app.buttons["backup-versions"]
            for _ in 0..<5 { if versions.isHittable { break }; app.swipeDown() }
            versions.tap()
            XCTAssertTrue(app.navigationBars["恢复备份"].waitForExistence(timeout: 5))
            capture(app, "backup-versions-" + appearance)
            app.terminate()
            app.launchArguments[1] = "backup-versions-empty"
            app.launch()
            XCTAssertTrue(app.staticTexts["暂无备份"].waitForExistence(timeout: 5))
            capture(app, "backup-versions-empty-" + appearance)
            app.terminate()
        }
        app.launchArguments = ["-preview-route", "import-confirmation", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["导入并替换"].waitForExistence(timeout: 15))
        capture(app, "backup-import-confirmation")
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["backup-import"].exists)
        XCTAssertFalse(app.buttons["导入并替换"].exists)
    }

    func testReminderSnapshotDisablesChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminder-progress-readonly", "-preview-dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 15))
        let enabled = app.switches["reminder-enabled"]
        reveal(app, element: enabled)
        XCTAssertFalse(enabled.isEnabled)
        XCTAssertFalse(app.buttons["编辑"].exists)
        XCTAssertFalse(app.buttons["reminder-record"].exists)
        XCTAssertFalse(app.buttons["删除提醒"].exists)
        capture(app, "reminder-snapshot-readonly")
    }

    func testTimelineSearchAndLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "timeline", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.navigationBars["时间线"].waitForExistence(timeout: 15))
            capture(app, "timeline-" + appearance)
            app.swipeDown()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText("no-such-record\n")
            let clear = app.buttons["timeline-clear-search"]
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            capture(app, "timeline-search-empty-" + appearance)
            clear.tap()
            XCTAssertFalse(app.staticTexts["没有匹配的记录"].exists)
            let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline-record-")).firstMatch
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(record.frame.maxX, app.frame.maxX)
            app.terminate()
        }
    }

    func testCategoryEditorPreservesAndDiscardsChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "categories", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let add = app.buttons["category-add"]
            XCTAssertTrue(add.waitForExistence(timeout: 15))
            capture(app, "categories-" + appearance)
            add.tap()
            XCTAssertTrue(app.navigationBars["新增类别"].waitForExistence(timeout: 5))
            app.buttons["category-cancel"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            add.tap()
            let name = app.descendants(matching: .any)["category-name"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap(); name.typeText("自行车")
            app.buttons["category-keyboard-done"].tap()
            let indoor = app.switches["category-indoor-distance"]
            reveal(app, element: indoor)
            XCTAssertEqual(indoor.value as? String, "0")
            indoor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertEqual(indoor.value as? String, "1")
            let save = app.buttons["category-save"]
            XCTAssertTrue(save.isEnabled)
            save.tap()
            let duplicate = app.staticTexts["已有同名类别，请使用其他名称。"]
            reveal(app, element: duplicate)
            XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["新增类别"].exists)
            capture(app, "category-save-failed-" + appearance)
            for _ in 0..<6 where !name.isHittable { app.swipeDown() }
            reveal(app, element: name)
            XCTAssertEqual(name.value as? String, "自行车")
            reveal(app, element: indoor)
            XCTAssertEqual(indoor.value as? String, "1")
            app.buttons["category-cancel"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.buttons["继续编辑"].tap()
            for _ in 0..<6 where !name.isHittable { app.swipeDown() }
            reveal(app, element: name)
            XCTAssertEqual(name.value as? String, "自行车")
            reveal(app, element: indoor)
            XCTAssertEqual(indoor.value as? String, "1")
            capture(app, "category-save-failure-continued-" + appearance)
            app.buttons["category-cancel"].tap()
            XCTAssertTrue(app.buttons["放弃更改"].waitForExistence(timeout: 5))
            app.buttons["放弃更改"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["category-save"].isEnabled)
            XCTAssertEqual(indoor.value as? String, "0")
            name.tap(); name.typeText("Test category")
            app.buttons["category-keyboard-done"].tap()
            capture(app, "category-editor-" + appearance)
            app.buttons["category-cancel"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.buttons["继续编辑"].tap()
            XCTAssertEqual(name.value as? String, "Test category")
            app.buttons["category-cancel"].tap(); app.buttons["放弃更改"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Test category"].exists)
            app.terminate()
        }
    }

    func testCopiedReminderCanChooseInstallationOrigin() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminder-copied-progress", "-preview-light"]
        app.launch()
        let progress = app.descendants(matching: .any)["reminder-progress-preview-copied-drip-distance"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        XCTAssertTrue((progress.value as? String ?? "").contains("186 / 300 km"))
        app.buttons["编辑"].tap()
        let origin = app.buttons["reminder-anchor"]
        reveal(app, element: origin)
        XCTAssertTrue(origin.label.contains("跟随滴蜡记录"))
        origin.tap()
        app.buttons["装配记录"].tap()
        app.buttons["reminder-installation"].tap()
        app.buttons["Tarmac SL8 Pro · 2024-10-28"].tap()
        capture(app, "reminder-copied-installation-origin")
        app.buttons["保存"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = springboard.alerts.firstMatch.buttons["Allow"]
            if allow.exists { allow.tap() }
        }
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 10))
        XCTAssertTrue((progress.value as? String ?? "").contains("412 / 300 km"))
        capture(app, "reminder-copied-installation-saved")
    }

    func testBatchStockClearsMovedSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "tree", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.buttons["gear-multiselect"].waitForExistence(timeout: 15))
        app.buttons["gear-multiselect"].tap()
        app.staticTexts["功率锁踏"].tap()
        XCTAssertEqual(app.staticTexts["gear-selection-count"].label, "已选 1 件")
        app.buttons["gear-selection-store"].tap()
        XCTAssertTrue(app.navigationBars["放入库存"].waitForExistence(timeout: 5))
        app.buttons["下一步"].tap()
        XCTAssertTrue(app.navigationBars["确认入库"].waitForExistence(timeout: 5))
        app.buttons["inventory-batch-save"].tap()
        if app.buttons["完成"].waitForExistence(timeout: 2), app.navigationBars["确认入库"].exists { app.buttons["完成"].tap() }
        XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["gear-selection-count"].label, "已选 0 件")
        XCTAssertFalse(app.buttons["gear-selection-store"].exists)
        capture(app, "equipment-batch-stock-clears-selection")
        app.buttons["gear-multiselect"].tap()
        app.buttons["库存"].tap()
        XCTAssertTrue(app.staticTexts["功率锁踏"].waitForExistence(timeout: 5))
    }

    func testRecomputePreviewShowsEffectsAndGaps() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "recompute", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let preview = app.buttons["recompute-preview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 15))
            reveal(app, element: preview); preview.tap()
            let totals = app.descendants(matching: .any)["recompute-total-clii"].firstMatch
            XCTAssertTrue(totals.waitForExistence(timeout: 5))
            capture(app, "recompute-preview-" + appearance)
            let gaps = app.buttons["recompute-gaps"]
            reveal(app, element: gaps); gaps.tap()
            XCTAssertTrue(app.buttons["同步活动"].waitForExistence(timeout: 5))
            capture(app, "recompute-gaps-" + appearance)
            app.terminate()
        }
    }

    func testMissingPhotoHasRecoveryAndCanClose() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "photo-missing", "-preview-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        let retry = app.buttons["photo-retry-preview-missing-image"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["无法打开图片"].exists)
        capture(app, "photo-missing-large-text")
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].isHittable)
    }

    func testSyncHistoryAcceptsFractionalTimestamp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "sync-history", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["同步"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["尚未同步"].exists)
        let unchanged = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "没有变化")).firstMatch
        reveal(app, element: unchanged)
        XCTAssertTrue(unchanged.exists)
        capture(app, "sync-history-fractional-timestamp")
    }

    func testEditorAppearanceMatrix() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let routes = [("gear-edit", "添加装备"), ("event", "添加记录"), ("component", "添加组件"), ("installation", "添加装配"), ("reminder", "添加提醒")]
        for appearance in ["light", "dark", "large-text"] {
            for (route, title) in routes {
                app.launchArguments = ["-preview-route", route, appearance == "dark" ? "-preview-dark" : "-preview-light"]
                if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
                app.launch()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
                capture(app, route + "-form-" + appearance)
                app.terminate()
            }
        }
    }

    func testMoveReviewShowsAffectedAndRetainedRanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "move-review", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.navigationBars["保存修改"].waitForExistence(timeout: 15))
            capture(app, "move-review-" + appearance)
            app.buttons["gear-moves-mode"].tap(); app.buttons["整理层级"].tap()
            app.buttons["gear-moves-preview"].tap()
            let ranges = app.descendants(matching: .any)["gear-moves-ranges-front"].firstMatch
            XCTAssertTrue(ranges.waitForExistence(timeout: 5))
            reveal(app, element: ranges)
            capture(app, "move-review-ranges-" + appearance)
            let retained = app.staticTexts["保持原装配的时段"].firstMatch
            XCTAssertTrue(retained.exists)
            reveal(app, element: retained); retained.tap()
            capture(app, "move-review-retained-ranges-" + appearance)
            XCTAssertTrue(app.buttons["gear-moves-save"].isEnabled)
            app.terminate()
        }
    }

    func testReplacementPickerSearchAndLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "large-text"] {
            app.launchArguments = ["-preview-route", "tree", "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.buttons["库存"].waitForExistence(timeout: 15))
            app.buttons["库存"].tap(); app.buttons["gear-add"].tap()
            let name = app.textFields["gear-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap(); name.typeText("备用链条")
            app.buttons["gear-keyboard-done"].tap()
            app.buttons["gear-category"].tap()
            let category = app.buttons["category-choice-Chain"]
            reveal(app, element: category); category.tap()
            app.buttons["保存"].tap()
            XCTAssertTrue(app.navigationBars["装备"].waitForExistence(timeout: 5))
            app.buttons["使用中"].tap()
            let chain = app.staticTexts["KMC Chain"].firstMatch
            reveal(app, element: chain); chain.tap()
            app.buttons["gear-detail-menu"].tap(); app.buttons["gear-replace"].tap()
            app.buttons["replacement-choice"].tap()
            XCTAssertTrue(app.staticTexts["备用链条"].waitForExistence(timeout: 5))
            capture(app, "replacement-picker-" + appearance)
            app.swipeDown()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText("no-such-stock\n")
            let clear = app.buttons["replacement-clear-search"]
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            capture(app, "replacement-picker-empty-" + appearance)
            clear.tap()
            XCTAssertTrue(app.staticTexts["备用链条"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testRecomputeBaselineRequiresConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "recompute-baseline", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let seeded = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "Shimano")).firstMatch
            XCTAssertTrue(seeded.waitForExistence(timeout: 15))
            let preview = app.buttons["recompute-preview"]
            reveal(app, element: preview); preview.tap()
            let confirmation = app.switches["recompute-confirm-baseline"]
            reveal(app, element: confirmation)
            capture(app, "recompute-baseline-confirmation-" + appearance)
            let apply = app.buttons["recompute-apply"]
            reveal(app, element: apply)
            XCTAssertFalse(apply.isEnabled)
            for _ in 0..<5 { if confirmation.isHittable { break }; app.swipeDown() }
            confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            reveal(app, element: apply)
            XCTAssertTrue(apply.isEnabled)
            capture(app, "recompute-baseline-ready-" + appearance)
            app.terminate()
        }
    }

    func testRecomputePreviewExpiresAfterLocalRestore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "recompute-baseline", "-preview-light"]
        app.launch()
        let seeded = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "Shimano")).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 15))
        let preview = app.buttons["recompute-preview"]
        reveal(app, element: preview); preview.tap()
        let gaps = app.buttons["recompute-gaps"]
        reveal(app, element: gaps); gaps.tap()
        app.buttons["同步活动"].tap()
        let backup = app.buttons["backup-settings"]
        reveal(app, element: backup); backup.tap()
        app.buttons["backup-versions"].tap()
        let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-version-")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        version.tap()
        app.buttons["backup-restore"].tap()
        app.buttons["backup-restore-confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["backup-restore"].waitForNonExistence(timeout: 30))
        for _ in 0..<3 { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let stale = app.descendants(matching: .any)["recompute-stale"].firstMatch
        reveal(app, element: stale)
        XCTAssertTrue(stale.exists)
        XCTAssertFalse(app.buttons["recompute-apply"].exists)
        capture(app, "recompute-stale-after-local-restore")
        app.buttons["recompute-preview"].tap()
        XCTAssertTrue(stale.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["recompute-total-tarmac"].firstMatch.exists)
        capture(app, "recompute-refreshed-after-local-restore")
    }

    func testReplacementEditKeepsTransferredChildren() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "inventory-replacement-edit", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.navigationBars["更换轮组"].waitForExistence(timeout: 15))
            let transfer = app.switches["inventory-transfer-children"]
            reveal(app, element: transfer)
            XCTAssertEqual(transfer.value as? String, "1")
            let front = app.switches["inventory-transfer-front"]
            reveal(app, element: front)
            XCTAssertEqual(front.value as? String, "1")
            capture(app, "replacement-edit-transfer-" + appearance)
            app.buttons["inventory-next"].tap()
            let transferred = app.descendants(matching: .any)["inventory-preview-transfer-front"].firstMatch
            reveal(app, element: transferred)
            XCTAssertTrue(transferred.exists)
            app.buttons["inventory-next"].tap()
            XCTAssertTrue(app.navigationBars["已保存"].waitForExistence(timeout: 5))
            app.terminate()
            app.launchArguments += ["-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.navigationBars["更换轮组"].waitForExistence(timeout: 15))
            reveal(app, element: transfer)
            XCTAssertEqual(transfer.value as? String, "1")
            XCTAssertEqual(front.value as? String, "1")
            app.terminate()
        }
    }

    func testComponentEditKeepsInheritedRetirementSeparate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "gear-inherited-retirement", "-preview-light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["KMC Chain"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["已退役"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["gear-detail-menu"].tap(); app.buttons["编辑"].tap()
        let retired = app.switches["已退役"]
        XCTAssertTrue(retired.waitForExistence(timeout: 5))
        XCTAssertEqual(retired.value as? String, "0")
        let notes = app.textFields["gear-notes"]
        notes.tap(); notes.typeText("检查后保存")
        app.buttons["gear-keyboard-done"].tap()
        capture(app, "component-inherited-retirement-edit")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["KMC Chain"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-preview-route", "gear-inherited-reactivated", "-preview-light", "-preserve-preview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["KMC Chain"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["已退役"].exists)
        capture(app, "component-inherited-retirement-reactivated")
        app.buttons["gear-detail-menu"].tap(); app.buttons["编辑"].tap()
        XCTAssertEqual(retired.value as? String, "0")
        XCTAssertEqual(notes.value as? String, "检查后保存")
    }

    func testReminderTitleEditKeepsCompletedAndSnoozedStates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for scenario in ["completed", "snoozed"] {
            app.launchArguments = ["-preview-route", "reminder-edit-" + scenario, scenario == "snoozed" ? "-preview-dark" : "-preview-light"]
            app.launch()
            XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 15))
            let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", scenario == "completed" ? "已完成" : "稍后提醒")).firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            let originalStatus = status.label
            app.buttons["编辑"].tap()
            XCTAssertTrue(app.navigationBars["编辑提醒"].waitForExistence(timeout: 5))
            let title = app.textViews["reminder-title"].exists ? app.textViews["reminder-title"] : app.textFields["reminder-title"]
            title.tap(); title.typeText("（检查后）")
            app.buttons["reminder-dismiss-keyboard"].tap()
            app.buttons["保存"].tap()
            XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, originalStatus)
            XCTAssertTrue(app.staticTexts["reminder-detail-title"].label.contains("检查后"))
            capture(app, "reminder-title-edit-" + scenario)
            app.terminate()
            app.launchArguments += ["-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 15))
            XCTAssertEqual(status.label, originalStatus)
            XCTAssertTrue(app.staticTexts["reminder-detail-title"].label.contains("检查后"))
            app.terminate()
        }
    }

    func testActivityDraftProtectsBackAndCancel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "tree", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["活动"].waitForExistence(timeout: 15))
            app.tabBars.buttons["活动"].tap()
            app.staticTexts["周末公路骑行"].tap()
            let shoe = app.buttons["activity-shoe"]
            reveal(app, element: shoe); shoe.tap(); app.buttons["RC7"].tap()
            app.buttons["activity-back"].tap()
            XCTAssertTrue(app.alerts["放弃未保存的更改？"].waitForExistence(timeout: 5))
            capture(app, "activity-draft-discard-" + appearance)
            app.alerts.buttons["继续编辑"].tap()
            XCTAssertTrue(shoe.label.contains("RC7"))
            let cancel = app.buttons["activity-cancel"]
            reveal(app, element: cancel); cancel.tap()
            app.alerts.buttons["放弃更改"].tap()
            XCTAssertFalse(cancel.exists)
            XCTAssertFalse(app.buttons["activity-save"].isEnabled)
            for _ in 0..<8 { if shoe.isHittable { break }; app.swipeDown() }
            shoe.tap(); app.buttons["RC7"].tap()
            app.buttons["activity-back"].tap(); app.alerts.buttons["放弃更改"].tap()
            XCTAssertTrue(app.navigationBars["活动"].waitForExistence(timeout: 5))
            app.staticTexts["周末公路骑行"].tap()
            XCTAssertFalse(app.buttons["activity-save"].isEnabled)
            XCTAssertFalse(shoe.label.contains("RC7"))
            app.terminate()
        }
    }

    func testBackupReadFailureKeepsLocalRecoveryAndRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            for hasRecovery in [false, true] {
                app.launchArguments = ["-preview-route", hasRecovery ? "backup-read-failure-local" : "backup-read-failure", appearance == "dark" ? "-preview-dark" : "-preview-light"]
                if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
                app.launch()
                XCTAssertTrue(app.navigationBars["恢复备份"].waitForExistence(timeout: 15))
                let retry = app.buttons["backup-reload"]
                XCTAssertTrue(retry.waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["暂无备份"].exists)
                let local = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-version-")).firstMatch
                if hasRecovery { XCTAssertTrue(local.exists) }
                else { XCTAssertTrue(app.staticTexts["无法读取备份"].exists); XCTAssertFalse(local.exists) }
                reveal(app, element: retry)
                capture(app, (hasRecovery ? "backup-read-failure-local-" : "backup-read-failure-") + appearance)
                retry.tap()
                XCTAssertTrue(retry.waitForExistence(timeout: 5))
                if hasRecovery {
                    for _ in 0..<6 { if local.isHittable { break }; app.swipeDown() }
                    local.tap()
                    XCTAssertTrue(app.buttons["backup-restore"].waitForExistence(timeout: 5))
                    capture(app, "backup-local-version-with-cloud-failure-" + appearance)
                }
                app.terminate()
            }
            for scenario in ["pending", "unreadable", "mixed"] {
                app.launchArguments = ["-preview-route", "backup-scan-" + scenario, appearance == "dark" ? "-preview-dark" : "-preview-light"]
                if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
                app.launch()
                XCTAssertTrue(app.navigationBars["恢复备份"].waitForExistence(timeout: 15))
                let message = scenario == "pending" ? "有备份尚未下载完成，请稍后重新读取。"
                    : scenario == "unreadable" ? "有备份无法读取，请重新读取或选择其他备份。"
                    : "有备份尚未下载完成，另有备份无法读取。请稍后重新读取或选择其他备份。"
                let warning = app.staticTexts[message]
                XCTAssertTrue(warning.waitForExistence(timeout: 10))
                XCTAssertFalse(app.staticTexts["暂无备份"].exists)
                let versions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-version-"))
                XCTAssertEqual(versions.count, scenario == "mixed" ? 2 : 0)
                let originalIDs = Set(versions.allElementsBoundByIndex.map(\.identifier))
                let retry = app.buttons["backup-reload"]
                reveal(app, element: retry)
                capture(app, "backup-scan-" + scenario + "-waiting-" + appearance)
                retry.tap()
                XCTAssertTrue(warning.waitForExistence(timeout: 10))
                let repair = app.buttons["backup-fixture-repair"]
                XCTAssertTrue(repair.waitForExistence(timeout: 5)); repair.tap()
                XCTAssertTrue(warning.waitForNonExistence(timeout: 10))
                XCTAssertTrue(retry.waitForNonExistence(timeout: 10))
                XCTAssertEqual(versions.count, scenario == "mixed" ? 2 : 1)
                XCTAssertTrue(originalIDs.isSubset(of: Set(versions.allElementsBoundByIndex.map(\.identifier))))
                capture(app, "backup-scan-" + scenario + "-ready-" + appearance)
                app.terminate()
            }
        }
    }

    func testUnreadableLibraryKeepsRecoveryAvailableUntilDataLoads() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text", "maximum-text"] {
            app.launchArguments = ["-preview-route", "startup-recovery", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityMedium.rawValue] }
            if appearance == "maximum-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue] }
            app.launch()
            XCTAssertTrue(app.staticTexts["本机数据暂不可用"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.tabBars.buttons["装备"].exists)
            capture(app, "startup-unavailable-" + appearance)
            let retry = app.buttons["library-retry"]
            revealRecoveryControl(app, retry); retry.tap()
            XCTAssertTrue(app.staticTexts["本机数据暂不可用"].exists)
            XCTAssertFalse(app.tabBars.buttons["装备"].exists)
            capture(app, "startup-retry-unreadable-" + appearance)
            let recovery = app.buttons["library-recovery"]
            revealRecoveryControl(app, recovery)
            capture(app, "startup-recovery-actions-" + appearance)
            recovery.tap()
            XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
            let enabled = app.switches["backup-enabled"]
            revealRecoveryControl(app, enabled); XCTAssertFalse(enabled.isEnabled)
            let now = app.buttons["backup-now"]
            revealRecoveryControl(app, now); XCTAssertFalse(now.isEnabled)
            capture(app, "startup-backup-automatic-disabled-" + appearance)
            let location = app.buttons["backup-location"]
            revealRecoveryControl(app, location); XCTAssertTrue(location.isEnabled)
            location.tap()
            cancelRecoveryFilePicker(app, "startup-backup-location-" + appearance)
            let export = app.buttons["backup-export"]
            revealRecoveryControl(app, export); XCTAssertFalse(export.isEnabled)
            let importing = app.buttons["backup-import"]
            revealRecoveryControl(app, importing); XCTAssertTrue(importing.isEnabled)
            capture(app, "startup-backup-files-disabled-" + appearance)
            importing.tap()
            cancelRecoveryFilePicker(app, "startup-backup-import-" + appearance)
            let versions = app.buttons["backup-versions"]
            revealRecoveryControl(app, versions); versions.tap()
            let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-version-")).firstMatch
            XCTAssertTrue(version.waitForExistence(timeout: 10))
            revealRecoveryControl(app, version); version.tap()
            XCTAssertTrue(app.navigationBars["备份详情"].waitForExistence(timeout: 5))
            capture(app, "startup-package-detail-" + appearance)
            let restore = app.buttons["backup-restore"]
            revealRecoveryControl(app, restore)
            capture(app, "startup-package-restore-action-" + appearance)
            restore.tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let cancel = alert.buttons["取消"]
            XCTAssertTrue(cancel.isHittable)
            XCTAssertGreaterThanOrEqual(cancel.frame.width, 44)
            XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
            capture(app, "startup-package-confirmation-" + appearance)
            cancel.tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            app.navigationBars["备份详情"].buttons["取消"].tap()
            XCTAssertTrue(app.navigationBars["恢复备份"].waitForExistence(timeout: 5))
            app.navigationBars["恢复备份"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
            app.navigationBars["备份与恢复"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["本机数据暂不可用"].waitForExistence(timeout: 5))
            let repair = app.buttons["library-fixture-repair"]
            XCTAssertTrue(repair.isHittable); repair.tap()
            XCTAssertFalse(repair.isEnabled)
            XCTAssertFalse(app.tabBars.buttons["装备"].exists)
            revealRecoveryControl(app, retry); retry.tap()
            XCTAssertTrue(app.tabBars.buttons["装备"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["本机示例自行车"].exists)
            XCTAssertFalse(app.buttons["library-retry"].exists)
            capture(app, "startup-repaired-library-" + appearance)
            app.terminate()
        }

        app.launchArguments = ["-preview-route", "startup-recovery", "-preview-light"]
        app.launch()
        let recovery = app.buttons["library-recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 15))
        revealRecoveryControl(app, recovery); recovery.tap()
        let versions = app.buttons["backup-versions"]
        revealRecoveryControl(app, versions); versions.tap()
        let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-version-")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 10)); version.tap()
        let restore = app.buttons["backup-restore"]
        revealRecoveryControl(app, restore); restore.tap()
        let confirm = app.alerts.buttons["backup-restore-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.tabBars.buttons["装备"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["备份示例自行车"].exists)
        XCTAssertFalse(app.staticTexts["本机示例自行车"].exists)
        XCTAssertFalse(app.buttons["library-retry"].exists)
        capture(app, "startup-package-restored-light")
        app.terminate()
    }

    private func cancelRecoveryFilePicker(_ app: XCUIApplication, _ name: String) {
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "取消", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertTrue(cancel.isHittable)
        capture(app, name)
        cancel.tap()
        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 10))
    }

    private func revealRecoveryControl(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<14 {
            let top = (app.navigationBars.allElementsBoundByIndex.first(where: { $0.isHittable })?.frame.maxY ?? 30) + 4
            let bottom = app.frame.maxY - 16
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            let towardTop = element.exists && element.frame.minY < top
            let height = max(44, bottom - top)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + height * (towardTop ? 0.2 : 0.8)))
            let to = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + height * (towardTop ? 0.8 : 0.2)))
            from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Recovery control is unreachable")
    }

    func testBatchStorageLetsUserRemoveRetiredSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "inventory-batch-retired", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.navigationBars["放入库存"].waitForExistence(timeout: 15))
            let remove = app.buttons["inventory-batch-remove-retired"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["inventory-batch-save"].isEnabled)
            XCTAssertTrue(app.staticTexts["inventory-batch-retired-tarmac"].exists)
            XCTAssertTrue(app.staticTexts["inventory-batch-retired-chain"].exists)
            reveal(app, element: remove)
            capture(app, "batch-storage-retired-" + appearance)
            remove.tap()
            XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["inventory-batch-item-tarmac"].exists)
            XCTAssertFalse(app.staticTexts["inventory-batch-item-chain"].exists)
            XCTAssertTrue(app.staticTexts["inventory-batch-item-propel"].exists)
            XCTAssertTrue(app.buttons["inventory-batch-save"].isEnabled)
            capture(app, "batch-storage-retired-removed-" + appearance)
            app.buttons["inventory-batch-cancel"].tap()
            XCTAssertTrue(app.alerts["放弃未保存的更改？"].waitForExistence(timeout: 5))
            capture(app, "batch-storage-draft-discard-" + appearance)
            app.buttons["inventory-batch-continue-editing"].firstMatch.tap()
            XCTAssertFalse(remove.exists)
            XCTAssertTrue(app.staticTexts["inventory-batch-item-propel"].exists)
            app.buttons["inventory-batch-save"].tap()
            XCTAssertTrue(app.navigationBars["确认入库"].waitForExistence(timeout: 5))
            app.buttons["inventory-batch-cancel"].tap()
            XCTAssertTrue(app.navigationBars["放入库存"].waitForExistence(timeout: 5))
            XCTAssertFalse(remove.exists)
            app.buttons["inventory-batch-save"].tap()
            XCTAssertTrue(app.navigationBars["确认入库"].waitForExistence(timeout: 5))
            app.buttons["inventory-batch-save"].tap()
            XCTAssertTrue(app.buttons["inventory-batch-save"].waitForNonExistence(timeout: 5))
            app.terminate()
            app.launchArguments = ["-preview-route", "tree", "-preview-light", "-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.buttons["库存"].waitForExistence(timeout: 15))
            app.buttons["库存"].tap()
            XCTAssertTrue(app.staticTexts["Propel Advanced"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Tarmac SL8 Pro"].exists)
            app.terminate()
        }
    }

    func testCoreScreensAccessibilityAudit() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        for route in ["equipment-design", "gear", "activity", "gear-edit", "reminder-progress-detail", "backups", "sync-cancellation", "sync-gear-refresh"] {
            app.launchArguments = ["-preview-route", route, "-preview-light"]
            app.launch()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
            if route == "sync-cancellation" { app.tabBars.buttons["同步"].tap() }
            capture(app, "accessibility-audit-" + route)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion]) { issue in
                let element = issue.element
                print("ACCESSIBILITY_ISSUE route=\(route) type=\(issue.auditType.rawValue) description=\(issue.compactDescription) identifier=\(element?.identifier ?? "nil") label=\(element?.label ?? "nil") enabled=\(element?.isEnabled.description ?? "nil") frame=\(element?.frame.debugDescription ?? "nil")")
                return false
            }
            app.terminate()
        }
    }

    func testEquipmentCanOrganizeWithoutDragging() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "tree", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.buttons["gear-multiselect"].waitForExistence(timeout: 15))
            app.buttons["gear-multiselect"].tap()
            let selectFront = app.buttons["gear-select-front"]
            reveal(app, element: selectFront); selectFront.tap()
            XCTAssertEqual(app.staticTexts["gear-selection-count"].label, "已选 1 件")
            capture(app, "equipment-selection-actions-" + appearance)
            let handle = app.buttons["gear-drag-front"]
            reveal(app, element: handle)
            for _ in 0..<8 {
                if handle.frame.maxY < app.staticTexts["gear-selection-count"].frame.minY - 16 { break }
                app.swipeUp()
            }
            handle.tap()
            capture(app, "equipment-after-handle-tap-" + appearance)
            XCTAssertTrue(app.navigationBars["选择所属装备"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["gear-destination-front"].exists)
            capture(app, "equipment-destination-picker-" + appearance)
            app.buttons["取消"].tap()
            app.buttons["gear-select-destination"].tap()
            let propel = app.buttons["gear-destination-propel"]
            reveal(app, element: propel); propel.tap()
            XCTAssertTrue(app.buttons["gear-moves-review"].waitForExistence(timeout: 5))
            capture(app, "equipment-destination-pending-" + appearance)
            app.buttons["gear-moves-review"].tap()
            app.buttons["gear-moves-mode"].tap(); app.buttons["整理层级"].tap()
            app.buttons["gear-moves-preview"].tap()
            XCTAssertTrue(app.buttons["gear-moves-save"].isEnabled)
            capture(app, "equipment-destination-organize-" + appearance)
            app.buttons["gear-moves-save"].tap()
            XCTAssertTrue(app.buttons["gear-moves-review"].waitForNonExistence(timeout: 10))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.buttons["库存"].tap()
            let addStock = app.buttons["gear-empty-add"]
            XCTAssertTrue(addStock.waitForExistence(timeout: 5))
            XCTAssertTrue(addStock.isHittable)
            capture(app, "equipment-empty-stock-" + appearance)
            addStock.tap()
            XCTAssertTrue(app.textFields["gear-name"].waitForExistence(timeout: 5))
            app.buttons["取消"].tap()
            XCTAssertTrue(addStock.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testPhotoGalleryZoomGesturesAndPaging() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        func readZoom(_ image: XCUIElement) -> Int {
            Int((image.value as? String ?? "").replacingOccurrences(of: "%", with: "")) ?? 0
        }
        func waitForZoom(_ image: XCUIElement, matching condition: @escaping (Int) -> Bool) {
            let predicate = NSPredicate { _, _ in
                guard image.exists else { return false }
                return condition(readZoom(image))
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8), .completed)
        }
        for appearance in ["light", "dark", "large-text", "maximum-text"] {
            app.launchArguments = ["-preview-route", "photo-zoom", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityMedium.rawValue] }
            if appearance == "maximum-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue] }
            app.launch()
            XCTAssertTrue(app.navigationBars["1 / 2"].waitForExistence(timeout: 15))
            let image = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "photo-zoom-")).firstMatch
            XCTAssertTrue(image.waitForExistence(timeout: 10))
            let firstID = image.identifier
            waitForZoom(image) { $0 == 100 }
            capture(app, "photo-zoom-fit-" + appearance)
            image.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).doubleTap()
            waitForZoom(image) { $0 >= 290 }
            capture(app, "photo-zoom-double-tap-" + appearance)
            let beforePan = image.screenshot().pngRepresentation
            image.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).press(forDuration: 0.05, thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
            XCTAssertTrue(app.navigationBars["1 / 2"].exists)
            XCTAssertNotEqual(image.screenshot().pngRepresentation, beforePan)
            capture(app, "photo-zoom-panned-" + appearance)
            image.swipeLeft()
            XCTAssertTrue(app.navigationBars["2 / 2"].waitForExistence(timeout: 8))
            waitForZoom(image) { $0 == 100 }
            XCTAssertNotEqual(image.identifier, firstID)
            capture(app, "photo-zoom-next-page-" + appearance)
            image.swipeRight()
            XCTAssertTrue(app.navigationBars["1 / 2"].waitForExistence(timeout: 8))
            waitForZoom(image) { $0 == 100 }
            XCTAssertEqual(image.identifier, firstID)
            image.doubleTap(); waitForZoom(image) { $0 >= 290 }
            image.doubleTap(); waitForZoom(image) { $0 == 100 }
            print("PHOTO_ZOOM_PINCH_IN_FRAME appearance=\(appearance) frame=\(image.frame)")
            image.pinch(withScale: 1.8, velocity: 1)
            waitForZoom(image) { $0 > 120 }
            capture(app, "photo-zoom-pinch-" + appearance)
            let beforePinchOut = readZoom(image)
            print("PHOTO_ZOOM_PINCH_OUT_FRAME appearance=\(appearance) frame=\(image.frame)")
            image.pinch(withScale: 0.1, velocity: -1)
            print("PHOTO_ZOOM_PINCH_OUT appearance=\(appearance) before=\(beforePinchOut)% after=\(readZoom(image))%")
            capture(app, "photo-zoom-pinch-out-" + appearance)
            waitForZoom(image) { $0 >= 100 && $0 < beforePinchOut }
            if readZoom(image) > 100 { image.doubleTap() }
            waitForZoom(image) { $0 == 100 }
            image.swipeLeft()
            XCTAssertTrue(app.navigationBars["2 / 2"].waitForExistence(timeout: 8))
            image.swipeRight()
            XCTAssertTrue(app.navigationBars["1 / 2"].waitForExistence(timeout: 8))
            waitForZoom(image) { $0 == 100 }
            if appearance == "light" {
                image.doubleTap(); waitForZoom(image) { $0 >= 290 }
                let portrait = image.frame.size
                XCUIDevice.shared.orientation = .landscapeLeft
                let resized = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in image.frame.size != portrait }, object: nil)], timeout: 5) == .completed
                print("PHOTO_ZOOM_SIZE_CHANGE applied=\(resized) before=\(portrait) after=\(image.frame.size)")
                if resized {
                    waitForZoom(image) { $0 == 100 }
                    var previousFrame = CGRect.null
                    var stableCount = 0
                    let stable = NSPredicate { _, _ in
                        guard image.exists else { return false }
                        let frame = image.frame
                        stableCount = frame == previousFrame ? stableCount + 1 : 0
                        previousFrame = frame
                        return stableCount >= 2 && app.buttons["完成"].isHittable
                    }
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stable, object: nil)], timeout: 8), .completed)
                    print("PHOTO_ZOOM_SIZE_STABLE image=\(image.frame) app=\(app.frame) nav=\(app.navigationBars.firstMatch.frame)")
                    XCTAssertGreaterThan(app.frame.width, app.frame.height)
                    XCTAssertEqual(image.frame.midX, app.frame.midX, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(image.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1)
                    XCTAssertEqual(image.frame.width / image.frame.height, 4.0 / 3.0, accuracy: 0.01)
                    let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    screen.name = "photo-zoom-resized-light"; screen.lifetime = .keepAlways; add(screen)
                }
                XCUIDevice.shared.orientation = .portrait
                if resized { waitForZoom(image) { $0 == 100 } }
            }
            XCTAssertTrue(app.buttons["完成"].isHittable)
            app.buttons["完成"].tap()
            XCTAssertTrue(app.navigationBars["1 / 2"].waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }

    func testPhotoSelectionAndDeletedCoverFallbackPersist() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let second = "b1000000-0000-4000-8000-000000000002"
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "equipment-photo-fallback", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
            app.staticTexts["Tarmac SL8 Pro"].tap()
            let cover = app.buttons["gear-cover-photo"]
            XCTAssertTrue(cover.waitForExistence(timeout: 10))
            capture(app, "photo-implicit-cover-" + appearance)
            cover.tap()
            XCTAssertTrue(app.navigationBars["1 / 2"].waitForExistence(timeout: 5))
            app.buttons["完成"].tap()
            app.buttons["gear-photo-actions"].tap()
            app.buttons["photo-open-" + second].tap()
            XCTAssertTrue(app.navigationBars["2 / 2"].waitForExistence(timeout: 5))
            capture(app, "photo-first-open-second-" + appearance)
            app.buttons["完成"].tap()
            app.buttons["gear-manage-photos"].tap()
            app.buttons["gear-photo-cover-" + second].tap()
            XCTAssertEqual(app.buttons["gear-photo-cover-" + second].label, "第 2 张图片，当前封面")
            app.buttons["完成"].tap(); app.buttons["完成"].tap()
            cover.tap()
            XCTAssertTrue(app.navigationBars["2 / 2"].waitForExistence(timeout: 5))
            app.buttons["完成"].tap()
            app.buttons["gear-photo-actions"].tap(); app.buttons["gear-manage-photos"].tap()
            app.buttons["photo-delete-" + second].tap(); app.buttons["删除"].tap()
            XCTAssertTrue(app.buttons["photo-delete-" + second].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["第 1 张图片，当前封面"].exists)
            capture(app, "photo-deleted-cover-fallback-" + appearance)
            app.buttons["完成"].tap(); app.buttons["完成"].tap()
            cover.tap()
            XCTAssertTrue(app.navigationBars["1 / 1"].waitForExistence(timeout: 5))
            capture(app, "photo-deleted-cover-gallery-" + appearance)
            app.terminate()
            app.launchArguments += ["-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Tarmac SL8 Pro"].waitForExistence(timeout: 15))
            app.staticTexts["Tarmac SL8 Pro"].tap()
            XCTAssertTrue(cover.waitForExistence(timeout: 10)); cover.tap()
            XCTAssertTrue(app.navigationBars["1 / 1"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testReplacementDraftSurvivesCancelAndPreviewReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "tree", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let chain = app.staticTexts["KMC Chain"].firstMatch
            XCTAssertTrue(chain.waitForExistence(timeout: 15)); reveal(app, element: chain); chain.tap()
            app.buttons["gear-detail-menu"].tap(); app.buttons["gear-replace"].tap()
            app.buttons["inventory-cancel"].tap()
            XCTAssertTrue(app.navigationBars["KMC Chain"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.buttons["gear-detail-menu"].tap(); app.buttons["gear-replace"].tap()
            app.buttons["replacement-choice"].tap(); app.buttons["新建装备"].tap()
            let name = app.textFields["replacement-name"]
            reveal(app, element: name); name.tap(); name.typeText(" 草稿")
            app.buttons["inventory-keyboard-done"].tap()
            let draftName = name.value as? String
            let condition = app.buttons["replacement-condition"]
            reveal(app, element: condition); condition.tap(); app.buttons["已使用"].tap()
            let purchase = app.switches["replacement-has-purchase"]
            reveal(app, element: purchase)
            purchase.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            app.buttons["inventory-cancel"].tap()
            XCTAssertTrue(app.alerts["放弃未保存的更改？"].waitForExistence(timeout: 5))
            capture(app, "replacement-draft-discard-" + appearance)
            app.buttons["inventory-continue-editing"].firstMatch.tap()
            XCTAssertEqual(purchase.value as? String, "1")
            for _ in 0..<6 { if name.isHittable { break }; app.swipeDown() }
            XCTAssertEqual(name.value as? String, draftName)
            XCTAssertTrue(condition.label.contains("已使用"))
            app.buttons["inventory-next"].tap()
            XCTAssertTrue(app.navigationBars["确认更换链条"].waitForExistence(timeout: 5))
            capture(app, "replacement-draft-preview-" + appearance)
            app.buttons["inventory-cancel"].tap()
            XCTAssertTrue(app.navigationBars["更换链条"].waitForExistence(timeout: 5))
            XCTAssertEqual(name.value as? String, draftName)
            app.swipeDown()
            XCTAssertTrue(app.buttons["inventory-next"].exists)
            app.buttons["inventory-cancel"].tap(); app.buttons["inventory-discard"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["KMC Chain"].waitForExistence(timeout: 5))
            app.terminate()
            app.launchArguments += ["-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.staticTexts["KMC Chain"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.staticTexts[draftName ?? "KMC Chain 新件 草稿"].exists)
            app.terminate()
        }
    }

    func testGearRefreshDisablesSyncUntilReadingFinishes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "sync-gear-refresh", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            let refreshing = app.descendants(matching: .any)["sync-gear-refresh-progress"].firstMatch
            XCTAssertTrue(refreshing.waitForExistence(timeout: 15))
            let sync = app.buttons["sync-now"]
            XCTAssertTrue(sync.waitForExistence(timeout: 5))
            XCTAssertFalse(sync.isEnabled)
            XCTAssertFalse(app.descendants(matching: .any)["sync-progress"].firstMatch.exists)
            capture(app, "sync-gear-refresh-waiting-" + appearance)
            let history = app.buttons["历史补录"]
            reveal(app, element: history); history.tap()
            let read = app.buttons["sync-history-load"]
            for _ in 0..<6 { if read.exists { break }; app.swipeUp() }
            XCTAssertTrue(read.exists)
            XCTAssertFalse(read.isEnabled)
            XCTAssertFalse(app.descendants(matching: .any)["sync-error"].firstMatch.exists)
            app.buttons["sync-preview-finish-refresh"].tap()
            let ready = NSPredicate { _, _ in read.exists && read.isEnabled }
            expectation(for: ready, evaluatedWith: app)
            waitForExpectations(timeout: 10)
            for _ in 0..<6 { if sync.exists && sync.isHittable { break }; app.swipeDown() }
            XCTAssertTrue(sync.exists)
            XCTAssertTrue(sync.isEnabled)
            XCTAssertTrue(refreshing.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["sync-error"].firstMatch.exists)
            capture(app, "sync-gear-refresh-ready-" + appearance)
            app.terminate()
            for populated in [false, true] {
                app.launchArguments = ["-preview-route", populated ? "activity-gear-refresh-populated" : "activity-gear-refresh-empty",
                                       appearance == "dark" ? "-preview-dark" : "-preview-light"]
                if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
                app.launch()
                let syncActivity = app.buttons["activities-sync"]
                let inlineProgress = app.descendants(matching: .any)["activities-gear-refresh-progress"].firstMatch
                let existing = app.buttons["activity-row-gear-refresh-existing-ride"]
                let state = populated ? "populated" : "empty"
                if populated {
                    XCTAssertTrue(inlineProgress.waitForExistence(timeout: 15))
                    XCTAssertTrue(existing.waitForExistence(timeout: 5))
                    XCTAssertFalse(syncActivity.exists)
                } else {
                    XCTAssertTrue(syncActivity.waitForExistence(timeout: 15))
                    XCTAssertEqual(syncActivity.label, "正在读取装备")
                    XCTAssertFalse(syncActivity.isEnabled)
                    XCTAssertFalse(inlineProgress.exists)
                }
                // A pull while the independent catalog request is held must keep its state and existing rows.
                let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
                top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68)))
                if populated { XCTAssertTrue(inlineProgress.exists); XCTAssertTrue(existing.exists) }
                else { XCTAssertFalse(syncActivity.isEnabled); XCTAssertEqual(syncActivity.label, "正在读取装备") }
                XCTAssertFalse(app.alerts.firstMatch.exists)
                capture(app, "activity-gear-refresh-" + state + "-waiting-" + appearance)
                app.buttons["sync-preview-finish-refresh"].tap()
                if populated {
                    XCTAssertTrue(inlineProgress.waitForNonExistence(timeout: 10))
                    XCTAssertTrue(existing.exists)
                    capture(app, "activity-gear-refresh-" + state + "-ready-" + appearance)
                } else {
                    expectation(for: NSPredicate { _, _ in syncActivity.exists && syncActivity.isEnabled }, evaluatedWith: app)
                    waitForExpectations(timeout: 10)
                    XCTAssertEqual(syncActivity.label, "同步活动")
                    capture(app, "activity-gear-refresh-" + state + "-ready-" + appearance)
                    syncActivity.tap()
                    XCTAssertTrue(app.buttons["activity-row-sync-cancel-saved-batch"].waitForExistence(timeout: 15))
                    XCTAssertTrue(syncActivity.waitForNonExistence(timeout: 5))
                    XCTAssertFalse(app.alerts.firstMatch.exists)
                    capture(app, "activity-gear-refresh-synced-" + appearance)
                }
                app.terminate()
            }
        }
    }

    func testSyncCancellationPreservesImportedActivities() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark", "large-text"] {
            app.launchArguments = ["-preview-route", "sync-cancellation", appearance == "dark" ? "-preview-dark" : "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["同步"].waitForExistence(timeout: 15))
            app.tabBars.buttons["活动"].tap()
            let imported = app.descendants(matching: .any)["activity-row-sync-cancel-saved-batch"].firstMatch
            XCTAssertTrue(imported.waitForExistence(timeout: 10))
            app.tabBars.buttons["同步"].tap()
            let progress = app.descendants(matching: .any)["sync-progress"].firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
            let cancel = app.buttons["sync-cancel"]
            reveal(app, element: cancel)
            capture(app, "sync-cancellation-progress-" + appearance)
            cancel.tap()
            XCTAssertTrue(progress.waitForNonExistence(timeout: 15))
            XCTAssertFalse(cancel.exists)
            XCTAssertFalse(app.descendants(matching: .any)["sync-error"].firstMatch.exists)
            XCTAssertTrue(app.buttons["sync-now"].isEnabled)
            capture(app, "sync-cancellation-finished-" + appearance)
            app.tabBars.buttons["活动"].tap()
            XCTAssertTrue(imported.waitForExistence(timeout: 10))
            capture(app, "sync-cancellation-kept-activity-" + appearance)
            app.terminate()
            app.launchArguments += ["-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["活动"].waitForExistence(timeout: 15))
            app.tabBars.buttons["活动"].tap()
            XCTAssertTrue(imported.waitForExistence(timeout: 10))
            app.tabBars.buttons["同步"].tap()
            XCTAssertFalse(progress.exists)
            XCTAssertFalse(app.descendants(matching: .any)["sync-error"].firstMatch.exists)
            app.terminate()
        }
    }

    func testSameNameActivityChoicesRemainDistinct() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "large-text"] {
            app.launchArguments = ["-preview-route", "activity-duplicate-choices", "-preview-light"]
            if appearance == "large-text" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
            app.launch()
            XCTAssertTrue(app.navigationBars["活动详情"].waitForExistence(timeout: 15))
            let main = app.buttons["activity-main"]
            reveal(app, element: main); main.tap()
            XCTAssertTrue(app.buttons["备用车 · 1"].exists)
            XCTAssertTrue(app.buttons["备用车 · 2"].exists)
            capture(app, "activity-duplicate-main-" + appearance)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            for (identifier, name) in [("activity-shoe", "备用锁鞋"), ("activity-trainer", "备用骑行台")] {
                let choice = app.buttons[identifier]
                reveal(app, element: choice); choice.tap()
                XCTAssertTrue(app.buttons[name + " · 1"].exists)
                XCTAssertTrue(app.buttons[name + " · 2"].exists)
                capture(app, identifier + "-duplicate-" + appearance)
                app.buttons[name + " · 2"].tap()
            }
            app.buttons["activity-save"].tap()
            XCTAssertFalse(app.buttons["activity-save"].isEnabled)
            app.terminate()
            app.launchArguments += ["-preserve-preview"]
            app.launch()
            XCTAssertTrue(app.navigationBars["活动详情"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["activity-shoe"].label.contains("备用锁鞋 · 2"))
            XCTAssertTrue(app.buttons["activity-trainer"].label.contains("备用骑行台 · 2"))
            app.terminate()
        }
    }

    func testReminderEventChoiceShowsTimeAndPersistsSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-preview-route", "reminder-origin-times", "-preview-dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 15))
        app.buttons["编辑"].tap()
        let origin = app.buttons["reminder-event"]
        reveal(app, element: origin); origin.tap()
        let morning = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "08:15")).firstMatch
        let evening = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "18:45")).firstMatch
        XCTAssertTrue(morning.exists); XCTAssertTrue(evening.exists)
        capture(app, "reminder-same-day-origin-times")
        evening.tap()
        XCTAssertTrue(origin.label.contains("18:45"))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments += ["-preserve-preview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["提醒"].waitForExistence(timeout: 15))
        app.buttons["编辑"].tap()
        XCTAssertTrue(origin.waitForExistence(timeout: 5))
        XCTAssertTrue(origin.label.contains("18:45"))
        capture(app, "reminder-origin-time-after-relaunch")
    }

    private func reveal(_ app: XCUIApplication, element: XCUIElement) {
        for _ in 0..<10 {
            let selection = app.staticTexts["gear-selection-count"]
            let bottom = selection.exists && selection.isHittable ? selection.frame.minY - 16 : app.frame.maxY - 32
            if element.exists && element.isHittable {
                let navigation = app.navigationBars.firstMatch
                let top = navigation.exists ? navigation.frame.maxY : app.frame.minY
                let visibleHeight = min(element.frame.maxY, bottom) - max(element.frame.minY, top)
                // Large text rows can be taller than the viewport; keep the tappable portion in view.
                if visibleHeight >= min(44, element.frame.height) { return }
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
