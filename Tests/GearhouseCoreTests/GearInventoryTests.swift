import XCTest
@testable import GearhouseCore

final class GearInventoryTests: XCTestCase {
    private final class Session {
        let engine = try! NativeDomain()
        var state: Value
        init() throws {
            let raw: Value = ["gears":[
                ["id":"bike", "name":"Road Bike", "type":"Bike", "remoteId":"remote-bike", "purchased":"2024-01-01"],
                ["id":"old", "name":"Chain A", "type":"Chain", "purchased":"2024-01-01"],
                ["id":"new", "name":"Chain B", "type":"Chain", "purchased":"2024-01-01"],
                ["id":"wheel", "name":"Wheels A", "type":"Wheelset", "purchased":"2024-01-01"],
                ["id":"spare-wheel", "name":"Wheels B", "type":"Wheelset", "purchased":"2024-01-01"],
                ["id":"tyre", "name":"Front Tyre", "type":"Tyre", "purchased":"2024-01-01"]],
                "events":[["id":"old-mount", "gearId":"old", "parentId":"bike", "at":"2024-01-01T00:00:00"],
                          ["id":"wheel-mount", "gearId":"wheel", "parentId":"bike", "at":"2024-01-01T00:00:00"],
                          ["id":"tyre-mount", "gearId":"tyre", "parentId":"wheel", "at":"2024-01-01T00:00:00"]],
                "gearStates":[["id":"new-stock", "gearId":"new", "status":"stock", "at":"2024-01-01T00:00:00"],
                              ["id":"wheel-stock", "gearId":"spare-wheel", "status":"stock", "at":"2024-01-01T00:00:00"]],
                "activities":[["id":"saved", "at":"2024-06-01T10:00:00", "main":"bike", "distance":2430000, "seconds":3600,
                               "snapshot":[["id":"bike", "parentId":.null],["id":"old", "parentId":"bike"]]]]]
            state = try engine.execute(state: raw, action: "initialize")["state"]
        }
        @discardableResult func run(_ action: String, _ input: Value = [:]) throws -> Value {
            let response = try engine.execute(state: state, action: action, input: input)
            if !response["state"].isNull { state = response["state"] }
            return response["result"]
        }
        func replacement(_ at: String = "2024-07-01") -> Value { ["kind":"replace", "gearId":"old", "replacementId":"new", "at":.string(at), "destination":"stock"] }
        func status(_ id: String, _ at: String = "2024-08-01T12:00:00") -> String { GearInventory.readStatus(state: state, gearID: id, at: at) }
        func sync(_ id: String, _ at: String) throws {
            try run("sync-rows", ["from":"2024-01-01", "to":"2024-12-31", "rows":[["id":.string(id), "type":"Ride", "name":"Ride", "start_date_local":.string(at), "distance":10000, "moving_time":3600, "gear":["id":"remote-bike"]]]])
        }
    }
    func testReplacementPreservesIndependentUsageAndCanRotateBack() throws {
        let s = try Session(), original = s.state["activities"]
        let preview = try s.run("inventory-preview", s.replacement())
        XCTAssertEqual(s.state["activities"], original)
        XCTAssertEqual(s.status("old"), "active")
        var input = s.replacement(); input["revision"] = preview["revision"]
        try s.run("inventory-save", input)
        XCTAssertEqual(s.status("old"), "stock"); XCTAssertEqual(s.status("new"), "active")
        XCTAssertEqual(s.state["activities"], original)
        XCTAssertEqual(try s.run("view")["statistics"]["old"]["distance"].double, 2430000)
        try s.sync("after", "2024-07-02T10:00:00")
        XCTAssertEqual(try s.run("view")["statistics"]["new"]["distance"].double, 10000)
        try s.run("inventory-save", ["kind":"replace", "gearId":"new", "replacementId":"old", "at":"2024-08-01"])
        try s.sync("back", "2024-08-02T10:00:00")
        XCTAssertEqual(try s.run("view")["statistics"]["old"]["distance"].double, 2440000)
        XCTAssertEqual(try s.run("view")["statistics"]["new"]["distance"].double, 10000)
    }
    func testExactCategoryRestrictionAndFailedNewGearAreAtomic() throws {
        let s = try Session(), before = s.state
        var invalid = s.replacement(); invalid["replacementId"] = "spare-wheel"
        XCTAssertThrowsError(try s.run("inventory-save", invalid))
        invalid["newGear"] = ["name":"Wrong", "categoryId":"Tyre"]
        XCTAssertThrowsError(try s.run("inventory-save", invalid))
        XCTAssertEqual(s.state, before)
        invalid["newGear"] = ["name":"New", "categoryId":"Chain", "purchased":"2025-01-01"]
        XCTAssertThrowsError(try s.run("inventory-save", invalid))
        XCTAssertEqual(s.state, before)
        let custom = try s.run("category-save", ["name":"Race chain", "baseType":"Chain", "indoorDistance":true])
        var gears = s.state["gears"].array; gears[2]["categoryId"] = custom["id"]; s.state["gears"] = .array(gears)
        XCTAssertThrowsError(try s.run("inventory-save", s.replacement()))
    }
    func testNewReplacementAndBackupRoundTripKeepAllRecords() throws {
        let s = try Session()
        var input = s.replacement(); input["newGear"] = ["name":"Fresh chain", "categoryId":"Chain", "condition":""]
        let operation = try s.run("inventory-save", input)
        let created = operation["replacementId"].text
        XCTAssertEqual(s.state["gears"].array.first { $0.id == created }?["condition"], "")
        XCTAssertEqual(s.status(created), "active")
        XCTAssertEqual(try s.run("view")["statistics"][created]["distance"].double, 0)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = try GearBackupArchive.create(state: s.state, media: root.appendingPathComponent("media"), in: root.appendingPathComponent("backups"))
        let restored = try GearBackupArchive.validate(at: backup).state
        XCTAssertEqual(restored, s.state)
        XCTAssertNoThrow(try s.engine.execute(state: restored, action: "initialize"))
        try s.run("inventory-delete", ["id":operation["id"], "confirmed":true])
        XCTAssertEqual(s.status(created), "stock")
        XCTAssertEqual(s.status("old"), "active")
    }
    func testStockAssemblyInheritsStatusAndSelectiveTransferKeepsIdentity() throws {
        let s = try Session()
        try s.run("inventory-save", ["kind":"store", "gearId":"wheel", "at":"2024-06-10"])
        XCTAssertEqual(s.status("wheel"), "stock"); XCTAssertEqual(s.status("tyre"), "stock")
        XCTAssertEqual(s.status("bike"), "active")
        try s.run("inventory-save", ["kind":"install", "gearId":"wheel", "parentId":"bike", "at":"2024-06-11"])
        try s.run("inventory-save", ["kind":"replace", "gearId":"wheel", "replacementId":"spare-wheel", "childIds":["tyre"], "at":"2024-07-01"])
        let index = GearTreeIndex(gears: s.state["gears"].array, events: s.state["events"].array, at:"2024-08-01")
        XCTAssertEqual(index.parents["tyre"], "spare-wheel")
        XCTAssertEqual(s.status("wheel"), "stock"); XCTAssertEqual(s.status("tyre"), "active")
    }
    func testEditingReplacementPreservesTransferredChildrenAndSavedActivities() throws {
        for date in ["2024-07-01", "2024-07-02"] {
            let session = try Session()
            let operation = try session.run("inventory-save", ["kind":"replace", "gearId":"wheel", "replacementId":"spare-wheel", "childIds":["tyre"], "at":"2024-07-01"])
            let savedActivities = session.state["activities"]
            let options = try session.run("inventory-options", ["gearId":"wheel", "operationId":operation["id"], "at":.string(date)])
            XCTAssertEqual(options["parentId"], "bike")
            XCTAssertTrue(options["children"].array.contains { $0.id == "tyre" })
            XCTAssertTrue(options["candidates"].array.contains { $0.id == "spare-wheel" })
            let childIDs = operation["childIds"].array.filter { child in options["children"].array.contains { $0["id"] == child } }
            XCTAssertEqual(childIDs, ["tyre"])
            var edit: Value = ["kind":"replace", "gearId":"wheel", "replacementId":operation["replacementId"], "operationId":operation["id"],
                               "childIds":.array(childIDs), "destination":operation["destination"], "at":.string(date)]
            let preview = try session.run("inventory-preview", edit)
            XCTAssertEqual(preview["transferred"].array.map(\.id), ["tyre"])
            edit["revision"] = preview["revision"]
            let saved = try session.run("inventory-save", edit)
            XCTAssertEqual(saved["childIds"], ["tyre"])
            XCTAssertEqual(saved["id"], operation["id"])
            XCTAssertEqual(session.state["gearOperations"].array.count, 1)
            let index = GearTreeIndex(gears: session.state["gears"].array, events: session.state["events"].array, at: "2024-07-03T00:00:00")
            XCTAssertEqual(index.parents["tyre"], "spare-wheel")
            XCTAssertEqual(index.parents["spare-wheel"], "bike")
            XCTAssertEqual(session.status("wheel"), "stock")
            XCTAssertEqual(session.status("tyre"), "active")
            XCTAssertEqual(session.state["activities"], savedActivities)
        }
    }
    func testHistoricalImportAndRemoteConflictUseActivityDate() throws {
        let s = try Session()
        try s.run("inventory-save", ["kind":"store", "gearId":"wheel", "at":"2024-06-10"])
        try s.sync("late", "2024-06-09T10:00:00")
        try s.sync("during", "2024-06-11T10:00:00")
        let rows = s.state["activities"].array
        XCTAssertTrue(rows.first { $0.id == "late" }!["snapshot"].array.contains { $0.id == "tyre" })
        XCTAssertFalse(rows.first { $0.id == "during" }!["snapshot"].array.contains { $0.id == "tyre" })
        try s.run("inventory-save", ["kind":"store", "gearId":"bike", "at":"2024-07-01"])
        try s.sync("conflict", "2024-07-02T10:00:00")
        let activity = s.state["activities"].array.first { $0.id == "conflict" }!
        XCTAssertEqual(activity["main"], "bike")
        XCTAssertTrue(activity["snapshot"].array.contains { $0.id == "bike" })
        XCTAssertFalse(activity["snapshot"].array.contains { $0.id == "old" })
        XCTAssertTrue(try s.run("view")["inventoryConflicts"].array.contains("conflict"))
        XCTAssertEqual(s.status("bike"), "stock")
        XCTAssertEqual(try s.run("view", ["date":"2024-06-01"])["gearStatuses"]["bike"], "active")
    }
    func testReplacementEditDeleteAndGenericHistoryCannotSplitOperation() throws {
        let s = try Session(), beforeEvents = s.state["events"], beforeStates = s.state["gearStates"]
        let op = try s.run("inventory-save", s.replacement())
        let event = s.state["events"].array.first { $0["operationId"] == op["id"] }!
        XCTAssertThrowsError(try s.run("history-delete", ["id":event["id"], "gearId":event["gearId"]]))
        XCTAssertThrowsError(try s.run("moves", ["at":"2024-07-01", "changes":[["gearId":"old", "parentId":"bike"]]]))
        var edited = s.replacement("2024-07-02"); edited["operationId"] = op["id"]
        try s.run("inventory-save", edited)
        XCTAssertEqual(s.state["gearOperations"].array.count, 1)
        XCTAssertEqual(s.status("old", "2024-07-01T12:00:00"), "active")
        try s.run("inventory-delete", ["id":op["id"], "confirmed":true])
        XCTAssertEqual(s.state["events"], beforeEvents)
        XCTAssertEqual(s.state["gearStates"], beforeStates)
    }
    func testFutureDependentsAndStalePreviewAreRejected() throws {
        let s = try Session(), preview = try s.run("inventory-preview", s.replacement())
        try s.run("hidden", ["id":"wheel", "hidden":true])
        var stale = s.replacement(); stale["revision"] = preview["revision"]
        XCTAssertThrowsError(try s.run("inventory-save", stale))
        let op = try s.run("inventory-save", s.replacement())
        try s.run("inventory-save", ["kind":"store", "gearId":"new", "at":"2024-08-01"])
        XCTAssertThrowsError(try s.run("inventory-delete", ["id":op["id"], "confirmed":true]))
        XCTAssertThrowsError(try s.run("inventory-save", s.replacement("2024-06-01")))
    }
    func testEditedReplacementRecomputeIncludesEarlierDateAndRespectsSavedSnapshots() throws {
        let s = try Session()
        let operation = try s.run("inventory-save", s.replacement())
        try s.sync("between", "2024-07-02T10:00:00")
        let saved = s.state["activities"]
        var edit = s.replacement("2024-07-03"); edit["operationId"] = operation["id"]
        let preview = try s.run("inventory-preview", edit)
        XCTAssertEqual(preview["affectedActivities"].integer, 1)
        XCTAssertEqual(preview["recomputeFrom"], "2024-07-01T00:00:00")
        XCTAssertEqual(preview["recomputeGearIds"], ["bike"])
        try s.run("inventory-save", edit)
        XCTAssertEqual(s.state["activities"], saved)
        let recompute = try s.run("recompute-preview", ["gearId":"bike", "scope":"subtree", "from":"2024-07-01", "to":"2024-07-03"])
        XCTAssertEqual(recompute["changed"].integer, 1)
        let changed = recompute["rows"].array.first { $0.id == "between" }!
        XCTAssertTrue(changed["added"].array.contains("old"))
        XCTAssertTrue(changed["removed"].array.contains("new"))

        let unchanged = try Session()
        try unchanged.sync("already-matches", "2024-07-02T10:00:00")
        let op = try unchanged.run("inventory-save", unchanged.replacement())
        edit["operationId"] = op["id"]
        XCTAssertEqual(try unchanged.run("inventory-preview", edit)["affectedActivities"].integer, 0)
    }
    func testRetirementHasDateAndRemindersResumeWithoutLosingUsage() throws {
        let s = try Session(); var input = s.replacement(); input["destination"] = "retired"
        try s.run("inventory-save", input)
        XCTAssertEqual(s.status("old", "2024-06-01T12:00:00"), "active")
        XCTAssertEqual(s.status("old"), "retired")
        var reminder = GearReminder(gearID:"old"); reminder.title = "Wax"; reminder.kilometers = 100
        reminder.startedAt = GearReminderEngine.parse("2024-01-01T00:00:00")!
        let now = GearReminderEngine.parse("2024-08-01T00:00:00")!
        XCTAssertEqual(GearReminderEngine.evaluate(reminder, state:s.state, total:2430000, now:now).issue, "装备已退役，提醒已暂停")
        try s.run("inventory-save", ["kind":"activate", "gearId":"old", "at":"2024-07-03"])
        XCTAssertEqual(s.status("old"), "active")
        XCTAssertTrue(GearReminderEngine.evaluate(reminder, state:s.state, total:2430000, now:now).due)
    }
    func testSavingChildMetadataDoesNotPersistInheritedRetirement() throws {
        let session = try Session(), latest = "9999-12-31T23:59:59"
        var parent = session.state["gears"].array.first { $0.id == "bike" }!
        parent["retired"] = true
        try session.run("gear", parent)
        XCTAssertEqual(session.status("old", latest), "retired")
        XCTAssertEqual(GearInventory.readOwnStatus(state: session.state, gearID: "old", at: latest), "active")
        let originalChildStates = session.state["gearStates"].array.filter { $0["gearId"] == "old" }
        var child = session.state["gears"].array.first { $0.id == "old" }!
        child["notes"] = "Cleaned the drivetrain"
        child["retired"] = .bool(GearInventory.readOwnStatus(state: session.state, gearID: "old", at: latest) == "retired")
        try session.run("gear", child)
        XCTAssertEqual(session.state["gearStates"].array.filter { $0["gearId"] == "old" }, originalChildStates)
        XCTAssertEqual(session.state["gears"].array.first { $0.id == "old" }?["notes"], "Cleaned the drivetrain")
        parent = session.state["gears"].array.first { $0.id == "bike" }!
        parent["retired"] = false
        try session.run("gear", parent)
        XCTAssertEqual(session.status("bike", latest), "active")
        XCTAssertEqual(session.status("old", latest), "active")
    }
    func testOwnStatusHonorsLegacyRetirementAndDatedStatesWithoutInheritingParent() {
        let state: Value = [
            "gears":[["id":"legacy", "retired":true], ["id":"parent", "retired":true], ["id":"child"]],
            "events":[["id":"mount", "gearId":"child", "parentId":"parent", "at":"2024-01-01T00:00:00"]],
            "gearStates":[["id":"restore", "gearId":"legacy", "status":"active", "at":"2024-02-01T00:00:00"],
                          ["id":"retire", "gearId":"legacy", "status":"retired", "at":"2024-03-01T00:00:00"]]
        ]
        XCTAssertEqual(GearInventory.readOwnStatus(state: state, gearID: "legacy", at: "2024-01-15T00:00:00"), "retired")
        XCTAssertEqual(GearInventory.readOwnStatus(state: state, gearID: "legacy", at: "2024-02-15T00:00:00"), "active")
        XCTAssertEqual(GearInventory.readOwnStatus(state: state, gearID: "legacy", at: "2024-03-15T00:00:00"), "retired")
        XCTAssertEqual(GearInventory.readOwnStatus(state: state, gearID: "child", at: "2024-02-15T00:00:00"), "active")
        XCTAssertEqual(GearInventory.readStatus(state: state, gearID: "child", at: "2024-02-15T00:00:00"), "retired")
    }
    func testTimelineGroupsReplacementAndSnapshotDoesNotLeakIt() throws {
        let s = try Session(), op = try s.run("inventory-save", s.replacement())
        for id in ["bike", "old", "new"] {
            let rows = GearTimeline.buildRows(state:s.state, gearID:id)
            XCTAssertEqual(rows.filter { $0.id == op.id }.count, 1)
            XCTAssertFalse(rows.contains { $0["entryType"] == "installation" && $0["operationId"] == op["id"] })
        }
        let snapshot = try s.run("view", ["date":"2024-06-15"])
        XCTAssertFalse(GearTimeline.buildRows(state:snapshot, gearID:"bike").contains { $0.id == op.id })
    }
    func testTopLevelLegacyGearIsActiveAndUnusedIsNotInferredFromZeroDistance() throws {
        let s = try Session(), original = s.state["gears"]
        try s.run("initialize")
        XCTAssertEqual(s.state["gears"], original)
        XCTAssertEqual(s.status("bike"), "active")
        let gear = try s.run("gear", ["name":"Bought spare", "categoryId":"Tyre", "placement":"stock", "condition":"unused"])
        XCTAssertEqual(GearInventory.readStatus(state:s.state, gearID:gear.id, at:"9999-12-31"), "stock")
        XCTAssertTrue(s.state["events"].array.allSatisfy { $0["gearId"] != gear["id"] })
        XCTAssertEqual(gear["condition"], "unused")
        XCTAssertTrue(s.state["gears"].array.first { $0.id == "new" }!["condition"].isNull)
    }
    func testBatchStorageKeepsSubtreeAndRollsBackOnInvalidMember() throws {
        let s = try Session(), before = s.state
        XCTAssertThrowsError(try s.run("inventory-batch", ["gearIds":["old","missing"], "at":"2024-07-01"]))
        XCTAssertEqual(s.state, before)
        let preview = try s.run("inventory-batch-preview", ["gearIds":["wheel","tyre","old"], "at":"2024-07-01"])
        XCTAssertEqual(preview["rows"].array.count, 2)
        try s.run("inventory-batch", ["gearIds":["wheel","tyre","old"], "at":"2024-07-01", "revision":preview["revision"]])
        XCTAssertEqual(s.status("wheel"), "stock"); XCTAssertEqual(s.status("tyre"), "stock")
        XCTAssertEqual(s.status("old"), "stock"); XCTAssertEqual(s.status("bike"), "active")
        XCTAssertEqual(s.state["activities"], before["activities"])
    }
    func testStockTreeDragKeepsDetachedChildrenInStockAndEarlierEditsAreGuarded() throws {
        let s = try Session()
        try s.run("inventory-save", ["kind":"store", "gearId":"wheel", "at":"2024-06-10"])
        try s.run("moves", ["at":"2024-06-11", "changes":[["gearId":"tyre", "parentId":.null]]])
        XCTAssertEqual(s.status("tyre"), "stock")
        try s.run("moves", ["at":"2024-06-12", "changes":[["gearId":"tyre", "parentId":"bike"]]])
        XCTAssertEqual(s.status("tyre"), "active")
        try s.run("inventory-save", s.replacement())
        XCTAssertThrowsError(try s.run("history-delete", ["gearId":"old", "id":"old-mount"]))
        XCTAssertThrowsError(try s.run("moves", ["at":"2024-05-01", "changes":[["gearId":"old", "parentId":.null]]]))
    }
    func testCorruptOperationBackupIsRejectedAndPurgeDoesNotRestoreReferences() throws {
        let s = try Session(), op = try s.run("inventory-save", s.replacement())
        var broken = s.state
        broken["events"] = .array(broken["events"].array.filter { $0["operationId"] != op["id"] })
        XCTAssertThrowsError(try s.engine.execute(state:broken, action:"initialize"))
        try s.run("delete", ["id":"old"])
        try s.run("purge", ["id":"old", "confirmed":true])
        XCTAssertNoThrow(try s.run("initialize"))
        XCTAssertFalse(s.state["gearOperations"].array.contains { $0.id == op.id })
        XCTAssertEqual(s.status("new"), "active")
    }

    func testLegacyRetirementWithoutDateDoesNotInventPastActivityConflict() throws {
        let s = try Session(); var gears = s.state["gears"].array
        gears[0]["retired"] = true; s.state["gears"] = .array(gears)
        XCTAssertTrue(try s.run("view")["inventoryConflicts"].array.isEmpty)
    }
    func testStockListIncludesNestedComponentsWithoutTopLevelBike() throws {
        let s = try Session()
        try s.run("inventory-save", ["kind":"store", "gearId":"wheel", "at":"2024-06-10"])
        let view = try s.run("view")
        let index = GearTreeIndex(gears:view["gears"].array, events:view["events"].array, at:"2024-08-01T00:00:00")
        let rows = index.rows(placement:"stock", statuses:view["gearStatuses"])
        XCTAssertFalse(rows.contains { $0.id == "bike" })
        XCTAssertEqual(rows.first { $0.id == "tyre" }?.depth, 1)
        XCTAssertEqual(rows.filter { $0.id == "tyre" }.count, 1)
    }

    func testIdenticalStockItemsGroupWithoutMergingHistoryAndKeepNumbersAfterInstallation() throws {
        let s = try Session()
        let first = try s.run("gear", ["name":"L05A-RF", "categoryId":"BrakePads", "placement":"stock", "condition":"unused"])
        let second = try s.run("gear", ["name":"L05A-RF", "categoryId":"BrakePads", "placement":"stock", "condition":"used"])
        let other = try s.run("gear", ["name":"L05A-RF", "categoryId":"BrakeRotor", "placement":"stock"])
        let original = s.state
        let view = try s.run("view")
        let index = GearTreeIndex(gears:view["gears"].array, events:view["events"].array, at:"9999-12-31")
        let rows = index.rows(placement:"stock", statuses:view["gearStatuses"])
        let groups = GearInventory.groupStockRows(rows, parents:index.parents)
        XCTAssertEqual(groups.first { $0.isGrouped }?.rows.map(\.id), [first.id,second.id])
        XCTAssertTrue(groups.contains { $0.rows.count == 1 && $0.rows[0].id == other.id })
        XCTAssertEqual(s.state, original)
        let numbers = GearInventory.buildInstanceNumbers(s.state["gears"].array)
        XCTAssertEqual(Set([numbers[first.id]!,numbers[second.id]!]), [1,2])
        try s.run("inventory-save", ["kind":"install", "gearId":first["id"], "parentId":"bike"])
        let next = try s.run("view")
        let nextIndex = GearTreeIndex(gears:next["gears"].array, events:next["events"].array, at:"9999-12-31")
        let remaining = GearInventory.groupStockRows(nextIndex.rows(placement:"stock", statuses:next["gearStatuses"]), parents:nextIndex.parents)
        XCTAssertFalse(remaining.contains { $0.isGrouped })
        XCTAssertTrue(remaining.contains { $0.rows.contains { $0.id == second.id } })
        XCTAssertEqual(GearInventory.buildInstanceNumbers(s.state["gears"].array), numbers)
    }

    func testStockGroupingKeepsAssembliesAndAttachedComponentsSeparateWhenFiltered() throws {
        let gears: [Value] = [["id":"assembly", "name":"Same", "categoryId":"Wheelset"],
                              ["id":"spare", "name":"Same", "categoryId":"Wheelset"],
                              ["id":"attached", "name":"Same", "categoryId":"Wheelset"],
                              ["id":"hidden", "name":"Child", "categoryId":"Tyre", "hidden":true]]
        let events: [Value] = [["id":"e1", "gearId":"attached", "parentId":"assembly", "at":"2024-01-01"],
                               ["id":"e2", "gearId":"hidden", "parentId":"spare", "at":"2024-01-01"]]
        let index = GearTreeIndex(gears:gears, events:events, at:"2024-02-01")
        let rows = index.rows(categoryID:"Wheelset")
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 })
        XCTAssertTrue(GearInventory.groupStockRows(rows, parents:index.parents).allSatisfy { !$0.isGrouped })
    }

}
