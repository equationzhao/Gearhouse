import XCTest
import JavaScriptCore
@testable import GearhouseCore

final class NativeDomainTests: XCTestCase {
    func testOrganizePreservesRepeatedHourBoundaries() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "type":"Bike"], ["id":"wheel", "type":"Wheelset"], ["id":"tyre", "type":"Tyre"]]
        state["events"] = [["id":"mount", "gearId":"wheel", "parentId":"bike", "at":"1990-01-01T00:00:00", "allDay":true],
                           ["id":"tyre-mount", "gearId":"tyre", "parentId":"bike", "at":"1990-01-01T00:00:00", "allDay":true],
                           ["id":"remove", "gearId":"wheel", "parentId":.null, "at":"1991-09-15T01:30:00", "instant":"1991-09-14T16:30:00.000Z", "allDay":false],
                           ["id":"install", "gearId":"wheel", "parentId":"bike", "at":"1991-09-15T01:30:00", "instant":"1991-09-14T17:30:00.000Z", "allDay":false]]
        let result = try engine.execute(state: state, action: "organize", input: ["changes":[["gearId":"tyre", "fromParentId":"bike", "parentId":"wheel"]]])
        let rows = result["state"]["events"].array.filter { $0["gearId"] == "tyre" }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { $0["parentId"].text }, ["wheel", "bike", "wheel"])
        XCTAssertEqual(rows[1]["instant"], "1991-09-14T16:30:00.000Z")
        XCTAssertEqual(rows[2]["instant"], "1991-09-14T17:30:00.000Z")
        XCTAssertNoThrow(try engine.execute(state: result["state"], action: "initialize"))
    }
    func testTimedReplacementAcrossRepeatedShanghaiHourUsesUTC() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "type":"Bike", "remoteId":"remote"], ["id":"old", "type":"Wheelset", "categoryId":"Wheelset"], ["id":"new", "type":"Wheelset", "categoryId":"Wheelset"]]
        state["events"] = [["id":"mount", "gearId":"old", "parentId":"bike", "at":"1990-01-01T00:00:00", "allDay":true]]
        state["gearStates"] = [["id":"stock", "gearId":"new", "status":"stock", "at":"1990-01-01T00:00:00"]]
        state = try engine.execute(state: state, action: "inventory-save", input: ["kind":"replace", "gearId":"old", "replacementId":"new", "at":"1991-09-15", "instant":"1991-09-14T17:00:00Z"])["state"]
        let rows: Value = [["id":"first", "type":"Ride", "start_date_local":"1991-09-15T01:30:00", "start_date":"1991-09-14T16:30:00Z", "gear":["id":"remote"]],
                           ["id":"second", "type":"Ride", "start_date_local":"1991-09-15T01:30:00", "start_date":"1991-09-14T17:30:00Z", "gear":["id":"remote"]]]
        state = try engine.execute(state: state, action: "sync-rows", input: ["rows":rows, "historical":true, "from":"1991-09-15", "to":"1991-09-15", "next":"1991-09-16"])["state"]
        let first = state["activities"].array.first { $0.id == "first" }!, second = state["activities"].array.first { $0.id == "second" }!
        XCTAssertEqual(Set(first["snapshot"].array.map(\.id)), Set(["bike", "old"]))
        XCTAssertEqual(Set(second["snapshot"].array.map(\.id)), Set(["bike", "new"]))
    }
    func testTimedReplacementDoesNotRewriteExistingSnapshotsUntilConfirmedRecompute() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "type":"Bike", "remoteId":"remote"], ["id":"old", "type":"Wheelset", "categoryId":"Wheelset"], ["id":"new", "type":"Wheelset", "categoryId":"Wheelset"]]
        state["events"] = [["id":"mount", "gearId":"old", "parentId":"bike", "at":"2024-01-01T00:00:00", "allDay":true]]
        state["gearStates"] = [["id":"stock", "gearId":"new", "status":"stock", "at":"2024-01-01T00:00:00"]]
        let rows: Value = [["id":"early", "type":"Ride", "start_date_local":"2025-01-01T08:00:00", "start_date":"2025-01-01T00:00:00Z", "gear":["id":"remote"]],
                           ["id":"late", "type":"Ride", "start_date_local":"2025-01-01T18:00:00", "start_date":"2025-01-01T10:00:00Z", "gear":["id":"remote"]]]
        let input: Value = ["rows":rows, "historical":false, "from":"2025-01-01", "to":"2025-01-01", "next":"2025-01-02"]
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        let snapshots = state["activities"].array.map { $0["snapshot"] }
        let operation: Value = ["kind":"replace", "gearId":"old", "replacementId":"new", "at":"2025-01-01", "instant":"2025-01-01T04:00:00Z"]
        state = try engine.execute(state: state, action: "inventory-save", input: operation)["state"]
        XCTAssertEqual(state["activities"].array.map { $0["snapshot"] }, snapshots)
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        XCTAssertEqual(state["activities"].array.map { $0["snapshot"] }, snapshots)
        let recompute: Value = ["gearId":"bike", "scope":"subtree", "from":"2025-01-01", "to":"2025-01-01"]
        let preview = try engine.execute(state: state, action: "recompute-preview", input: recompute)["result"]
        XCTAssertEqual(preview["changed"].integer, 1)
        XCTAssertEqual(state["activities"].array.map { $0["snapshot"] }, snapshots)
        state = try engine.execute(state: state, action: "recompute", input: recompute)["state"]
        let early = state["activities"].array.first { $0.id == "early" }!, late = state["activities"].array.first { $0.id == "late" }!
        XCTAssertEqual(Set(early["snapshot"].array.map(\.id)), Set(["bike", "old"]))
        XCTAssertEqual(Set(late["snapshot"].array.map(\.id)), Set(["bike", "new"]))
    }
    func testTimedReplacementAssignsLateImportedRidesByInstant() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "name":"Bike", "type":"Bike", "remoteId":"remote"],
                          ["id":"old", "name":"Old", "type":"Wheelset", "categoryId":"Wheelset"],
                          ["id":"new", "name":"New", "type":"Wheelset", "categoryId":"Wheelset"]]
        state["events"] = [["id":"mount", "gearId":"old", "parentId":"bike", "at":"2024-01-01T00:00:00", "allDay":true]]
        state["gearStates"] = [["id":"stock", "gearId":"new", "status":"stock", "at":"2024-01-01T00:00:00"]]
        let operation: Value = ["kind":"replace", "gearId":"old", "replacementId":"new", "at":"2025-01-01", "instant":"2025-01-01T04:00:00Z"]
        state = try engine.execute(state: state, action: "inventory-save", input: operation)["state"]
        let afterReplacement = state
        XCTAssertThrowsError(try engine.execute(state: state, action: "inventory-save", input: operation))
        XCTAssertEqual(state, afterReplacement)
        state = try engine.execute(state: state, action: "inventory-save", input: ["kind":"store", "gearId":"new", "at":"2025-01-01", "instant":"2025-01-01T07:00:00Z"])["state"]
        state = try engine.execute(state: state, action: "inventory-save", input: ["kind":"install", "gearId":"new", "parentId":"bike", "at":"2025-01-01", "instant":"2025-01-01T09:00:00Z"])["state"]
        let firstOperation = state["gearOperations"].array.first!["id"]
        XCTAssertThrowsError(try engine.execute(state: state, action: "inventory-delete-preview", input: ["id":firstOperation]))
        var editFirst = operation; editFirst["operationId"] = firstOperation; editFirst["instant"] = "2025-01-01T03:00:00Z"
        XCTAssertThrowsError(try engine.execute(state: state, action: "inventory-preview", input: editFirst))
        state["gears"] = .array(state["gears"].array + [["id":"other", "type":"Bike", "remoteId":"other-remote"]])
        state["activities"] = [["id":"changed", "name":"Ride", "type":"Ride", "at":"2025-01-01T18:00:00", "main":"other", "remoteId":"other-remote", "manual":false, "snapshot":[["id":"other", "parentId":.null]], "extras":[], "excluded":[]]]
        let rows: Value = [["id":"early", "type":"Ride", "start_date_local":"2025-01-01T08:00:00", "start_date":"2025-01-01T00:00:00Z", "gear":["id":"remote"]],
                           ["id":"travel-before", "type":"Ride", "start_date_local":"2024-12-31T22:00:00", "start_date":"2025-01-01T03:00:00Z", "gear":["id":"remote"]],
                           ["id":"boundary", "type":"Ride", "start_date_local":"2025-01-01T12:00:00", "start_date":"2025-01-01T04:00:00Z", "gear":["id":"remote"]],
                           ["id":"travel-after", "type":"Ride", "start_date_local":"2025-01-01T00:00:00", "start_date":"2025-01-01T05:00:00Z", "gear":["id":"remote"]],
                           ["id":"removed", "type":"Ride", "start_date_local":"2025-01-01T16:00:00", "start_date":"2025-01-01T08:00:00Z", "gear":["id":"remote"]],
                           ["id":"late", "type":"Ride", "start_date_local":"2025-01-01T18:00:00", "start_date":"2025-01-01T10:00:00Z", "gear":["id":"remote"]],
                           ["id":"changed", "type":"Ride", "start_date_local":"2025-01-01T18:00:00", "gear":["id":"remote"]],
                           ["id":"unknown", "type":"Ride", "start_date_local":"2025-01-01T18:00:00", "gear":["id":"remote"]]]
        let input: Value = ["rows":rows, "historical":true, "from":"2025-01-01", "to":"2025-01-01", "next":"2025-01-02"]
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        func read(_ id: String) -> Value { state["activities"].array.first { $0.id == id } ?? [:] }
        XCTAssertEqual(Set(read("early")["snapshot"].array.map(\.id)), Set(["bike", "old"]))
        XCTAssertEqual(Set(read("travel-before")["snapshot"].array.map(\.id)), Set(["bike", "old"]))
        XCTAssertEqual(Set(read("boundary")["snapshot"].array.map(\.id)), Set(["bike", "new"]))
        XCTAssertEqual(Set(read("travel-after")["snapshot"].array.map(\.id)), Set(["bike", "new"]))
        XCTAssertEqual(read("removed")["snapshot"].array.map(\.id), ["bike"])
        XCTAssertEqual(Set(read("late")["snapshot"].array.map(\.id)), Set(["bike", "new"]))
        XCTAssertEqual(read("unknown")["snapshot"].array.map(\.id), ["bike"])
        XCTAssertTrue(read("unknown")["assemblyTimeUnknown"].flag)
        XCTAssertEqual(read("changed")["snapshot"].array.map(\.id), ["bike"])
        XCTAssertTrue(read("changed")["assemblyTimeUnknown"].flag)
        let before = state["activities"]
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        XCTAssertEqual(state["activities"], before)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseTimedBackup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try GearBackupArchive.create(state: state, media: root.appendingPathComponent("media"), in: root)
        let recovered = try GearBackupArchive.validate(at: package).state
        let restored = try engine.execute(state: recovered, action: "initialize")["state"]
        XCTAssertEqual(restored["events"], state["events"])
        XCTAssertEqual(restored["gearStates"], state["gearStates"])
        XCTAssertEqual(restored["gearOperations"], state["gearOperations"])
        XCTAssertEqual(restored["activities"], state["activities"])
        var invalid = state, operations = invalid["gearOperations"].array, first = operations[0]
        var afterEvents = first["afterEvents"].array, altered = afterEvents[0]
        altered["instant"] = "2025-01-01T04:01:00.000Z"; altered["at"] = "2025-01-01T12:01:00"
        afterEvents[0] = altered; first["afterEvents"] = .array(afterEvents); operations[0] = first
        invalid["gearOperations"] = .array(operations)
        invalid["events"] = .array(invalid["events"].array.map { $0.id == altered.id ? altered : $0 })
        XCTAssertThrowsError(try engine.execute(state: invalid, action: "initialize"))
        let recompute: Value = ["gearId":"bike", "scope":"subtree", "from":"2025-01-01", "to":"2025-01-01"]
        let uncertainPreview = try engine.execute(state: state, action: "recompute-preview", input: recompute)["result"]
        XCTAssertEqual(uncertainPreview["skipped"]["timeUnknown"].integer, 2)
        XCTAssertTrue(uncertainPreview["rows"].array.contains { $0.id == "travel-before" })
        var complete = input
        complete["rows"] = [["id":"unknown", "type":"Ride", "start_date_local":"2025-01-01T18:00:00", "start_date":"2025-01-01T10:00:00Z", "gear":["id":"remote"]]]
        state = try engine.execute(state: state, action: "sync-rows", input: complete)["state"]
        XCTAssertEqual(read("unknown")["snapshot"].array.map(\.id), ["bike"])
        XCTAssertTrue(read("unknown")["assemblyTimeUnknown"].flag)
        let result = try engine.execute(state: state, action: "recompute", input: recompute)
        state = result["state"]
        XCTAssertEqual(Set(read("unknown")["snapshot"].array.map(\.id)), Set(["bike", "new"]))
        XCTAssertFalse(read("unknown")["assemblyTimeUnknown"].flag)
        var later = complete
        later["rows"] = [["id":"unknown", "type":"Ride", "start_date_local":"2025-01-01T19:00:00", "start_date":"2025-01-01T11:00:00Z", "gear":["id":"remote"]]]
        let changedTime = try engine.execute(state: state, action: "sync-rows", input: later)["state"]
        XCTAssertTrue(changedTime["activities"].array.first { $0.id == "unknown" }?["assemblyTimeUnknown"].flag == true)
        XCTAssertEqual(changedTime["activities"].array.first { $0.id == "unknown" }?["snapshot"], read("unknown")["snapshot"])
        XCTAssertThrowsError(try engine.execute(state: changedTime, action: "recompute-undo", input: ["id": result["result"]["id"]]))
        state = try engine.execute(state: state, action: "recompute-undo", input: ["id": result["result"]["id"]])["state"]
        XCTAssertEqual(read("unknown")["snapshot"].array.map(\.id), ["bike"])
        XCTAssertTrue(read("unknown")["assemblyTimeUnknown"].flag)
        let savedActivities = state["activities"], last = state["gearOperations"].array.last!
        let deletion = try engine.execute(state: state, action: "inventory-delete-preview", input: ["id":last["id"]])["result"]
        state = try engine.execute(state: state, action: "inventory-delete", input: ["id":last["id"], "confirmed":true, "revision":deletion["revision"]])["state"]
        XCTAssertEqual(state["activities"], savedActivities)
        let options = try engine.execute(state: state, action: "inventory-options", input: ["gearId":"new", "at":"2025-01-01", "instant":"2025-01-01T10:00:00Z"])["result"]
        XCTAssertEqual(options["status"], "stock")
    }
    func testTimedInstallationKeepsDistinctRepeatedWallClockInstants() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike-a", "type":"Bike"], ["id":"bike-b", "type":"Bike"], ["id":"wheel", "type":"Wheelset"]]
        let first: Value = ["gearId":"wheel", "parentId":"bike-a", "at":"1991-09-15", "instant":"1991-09-14T16:30:00Z"]
        let second: Value = ["gearId":"wheel", "parentId":"bike-b", "at":"1991-09-15", "instant":"1991-09-14T17:30:00Z"]
        state = try engine.execute(state: state, action: "history-save", input: first)["state"]
        state = try engine.execute(state: state, action: "history-save", input: second)["state"]
        let events = state["events"].array
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map { $0["at"].text }, ["1991-09-15T01:30:00", "1991-09-15T01:30:00"])
        XCTAssertEqual(events.map { $0["instant"].text }, ["1991-09-14T16:30:00.000Z", "1991-09-14T17:30:00.000Z"])
        XCTAssertThrowsError(try engine.execute(state: state, action: "history-save", input: second))
        XCTAssertThrowsError(try engine.execute(state: state, action: "history-save", input: ["gearId":"wheel", "parentId":"bike-a", "at":"1991-09-15"]))
        state = try engine.execute(state: state, action: "history-save", input: ["gearId":"wheel", "parentId":.null, "at":"1991-09-16"])["state"]
        XCTAssertEqual(state["events"].array.count, 3)
        XCTAssertTrue(state["events"].array.last?["allDay"].flag == true)
        XCTAssertEqual(try engine.execute(state: state, action: "initialize")["state"]["events"], state["events"])
    }
    func testSyncRetainsOnlyReliableActivityInstantsWithoutRewritingSnapshots() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "name":"Bike", "type":"Bike", "remoteId":"r"]]
        let rows: Value = [["id":"first", "type":"Ride", "start_date_local":"2025-11-02T01:30:00", "start_date":"2025-11-02T01:30:00-04:00", "gear":["id":"r"]],
                           ["id":"second", "type":"Ride", "start_date_local":"2025-11-02T01:30:00", "start_date":"2025-11-02T01:30:00-05:00", "gear":["id":"r"]],
                           ["id":"unknown", "type":"Ride", "start_date_local":"2025-11-02T01:30:00", "start_date":"2025-11-02T01:30:00", "gear":["id":"r"]],
                           ["id":"boundary", "type":"Ride", "start_date_local":"2025-11-02T00:10:00", "start_date":"2025-11-02T00:10:00+08:00", "gear":["id":"r"]],
                           ["id":"invalid", "type":"Ride", "start_date_local":"2025-11-02T01:30:00", "start_date":"2025-02-30T01:30:00Z", "gear":["id":"r"]]]
        var input: Value = ["rows":rows, "historical":false, "from":"2025-11-02", "to":"2025-11-02", "next":"2025-11-03"]
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        func read(_ id: String) -> Value { state["activities"].array.first { $0.id == id } ?? [:] }
        XCTAssertEqual(read("first")["startInstant"], "2025-11-02T05:30:00.000Z")
        XCTAssertEqual(read("second")["startInstant"], "2025-11-02T06:30:00.000Z")
        XCTAssertEqual(read("boundary")["startInstant"], "2025-11-01T16:10:00.000Z")
        XCTAssertTrue(read("unknown")["startInstant"].isNull)
        XCTAssertTrue(read("invalid")["startInstant"].isNull)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseInstantBackup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try GearBackupArchive.create(state: state, media: root.appendingPathComponent("media"), in: root)
        let recovered = try GearBackupArchive.validate(at: package).state
        let initialized = try engine.execute(state: recovered, action: "initialize")["state"]
        XCTAssertEqual(initialized["activities"], state["activities"])
        let prototype: Value = ["gears":[], "activities":[["id":"legacy", "at":"1991-09-14T16:30:00Z", "mainGearID":.null]]]
        let migrated = try engine.execute(state: prototype, action: "initialize")["state"]
        XCTAssertEqual(migrated["activities"].array.first?["startInstant"], "1991-09-14T16:30:00.000Z")
        XCTAssertEqual(migrated["activities"].array.first?["at"], "1991-09-15T01:30:00")
        let snapshot = read("first")["snapshot"]
        input["rows"] = [["id":"first", "type":"Ride", "start_date_local":"2025-11-02T01:30:00", "gear":["id":"r"]]]
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        XCTAssertEqual(read("first")["startInstant"], "2025-11-02T05:30:00.000Z")
        XCTAssertEqual(read("first")["snapshot"], snapshot)
        input["rows"] = [["id":"first", "type":"Ride", "start_date_local":"2025-11-02T02:30:00", "gear":["id":"r"]]]
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        XCTAssertTrue(read("first")["startInstant"].isNull)
        XCTAssertEqual(read("first")["snapshot"], snapshot)
    }
    func testNewAndRepeatedSyncApplySameDatedRemoteGearMapping() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "name":"Bike", "type":"Bike", "remoteId":"remote-bike", "deletedAt":"2025-02-01T00:00:00"],
                          ["id":"chain", "name":"Chain", "type":"Chain", "remoteId":"remote-chain"]]
        let rows: Value = [["id":"before", "type":"Ride", "start_date_local":"2025-01-31T12:00:00", "gear":["id":"remote-bike"]],
                           ["id":"after", "type":"Ride", "start_date_local":"2025-02-01T12:00:00", "gear":["id":"remote-bike"]],
                           ["id":"wrong-type", "type":"Ride", "start_date_local":"2025-01-31T12:00:00", "gear":["id":"remote-chain"]]]
        var input: Value = ["rows":rows, "historical":true, "from":"2025-01-01", "to":"2025-02-02", "next":"2025-02-03"]
        let initial = state
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        func activity(_ id: String) -> Value { state["activities"].array.first { $0.id == id } ?? [:] }
        XCTAssertEqual(activity("before")["main"], "bike")
        XCTAssertEqual(activity("before")["snapshot"].array.first?["id"], "bike")
        for id in ["after", "wrong-type"] {
            XCTAssertTrue(activity(id)["main"].isNull)
            XCTAssertTrue(activity(id)["unknown"].flag)
            XCTAssertTrue(activity(id)["snapshot"].array.isEmpty)
        }
        let stats = try engine.execute(state: state, action: "view")["result"]["statistics"]
        XCTAssertEqual(stats["bike"]["count"].integer, 1)
        XCTAssertEqual(stats["chain"]["count"].integer, 0)
        let assignments = state["activities"].array.map { ($0.id, $0["main"], $0["snapshot"]) }
        state = try engine.execute(state: state, action: "sync-rows", input: input)["state"]
        for (id, main, snapshot) in assignments {
            XCTAssertEqual(activity(id)["main"], main)
            XCTAssertEqual(activity(id)["snapshot"], snapshot)
        }
        input["historical"] = false
        state = try engine.execute(state: initial, action: "sync-rows", input: input)["state"]
        XCTAssertEqual(activity("before")["main"], "bike")
        for id in ["after", "wrong-type"] {
            XCTAssertTrue(activity(id)["main"].isNull)
            XCTAssertTrue(activity(id)["unknown"].flag)
            XCTAssertTrue(activity(id)["snapshot"].array.isEmpty)
        }
    }
    private func buildPhotoRecord(ownerType: String = "gear", ownerID: String = "gear", gearID: String? = nil) -> Value {
        var record: Value = ["id":.string(UUID().uuidString.lowercased()), "ownerType":.string(ownerType), "ownerId":.string(ownerID),
                             "metadata":["width":640, "height":480, "bytes":1024, "hash":.string(String(repeating: "a", count: 64))]]
        if let gearID { record["gearId"] = .string(gearID) }
        return record
    }

    func testPhotoBatchKeepsResultOrderOwnershipAndSingleRevision() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"gear", "type":"Chain"]]
        state["activities"] = [["id":"activity", "type":"Ride", "snapshot":[]]]
        let draftID = UUID().uuidString.lowercased()
        let records = [buildPhotoRecord(), buildPhotoRecord(ownerType: "activity", ownerID: "activity"),
                       buildPhotoRecord(ownerType: "draft", ownerID: draftID, gearID: "gear")]
        let response = try engine.execute(state: state, action: "photo-add-batch", input: ["records":.array(records)])
        let photos = response["result"].array
        XCTAssertEqual(photos.map(\.id), records.map(\.id))
        XCTAssertEqual(response["state"]["photos"], .array(photos))
        XCTAssertEqual(response["state"]["revision"].integer, state["revision"].integer + 1)
        for (record, photo) in zip(records, photos) {
            XCTAssertEqual(photo["ownerType"], record["ownerType"])
            XCTAssertEqual(photo["ownerId"], record["ownerId"])
            for (key, value) in record["metadata"].object { XCTAssertEqual(photo[key], value) }
            XCTAssertFalse(photo["createdAt"].text.isEmpty)
        }
        XCTAssertTrue(photos[0]["gearId"].isNull)
        XCTAssertTrue(photos[1]["gearId"].isNull)
        XCTAssertEqual(photos[2]["gearId"], "gear")
        let repeated = try engine.execute(state: response["state"], action: "photo-add-batch", input: ["records":.array(records.reversed())])
        XCTAssertEqual(repeated["result"], .array(photos.reversed()))
        XCTAssertEqual(repeated["state"]["photos"], response["state"]["photos"])
    }

    func testPhotoBatchFailureDoesNotCommitEarlierRecords() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"gear", "type":"Chain"]]
        let valid = buildPhotoRecord()
        var invalidID = buildPhotoRecord(); invalidID["id"] = "invalid"
        let invalidRecords = [invalidID, buildPhotoRecord(ownerID: "missing"), buildPhotoRecord(ownerType: "event", ownerID: "missing")]
        for invalid in invalidRecords {
            XCTAssertThrowsError(try engine.execute(state: state, action: "photo-add-batch", input: ["records":.array([valid, invalid])]))
            XCTAssertTrue(state["photos"].array.isEmpty)
            let retried = try engine.execute(state: state, action: "photo-add-batch", input: ["records":.array([valid])])
            XCTAssertEqual(retried["state"]["photos"].array.map(\.id), [valid.id])
            XCTAssertEqual(retried["state"]["revision"].integer, state["revision"].integer + 1)
        }
    }

    func testPhotoBatchBoundsAndExistingOwnerLimitRemainAtomic() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"gear", "type":"Chain"]]
        let records = (0..<40).map { _ in buildPhotoRecord() }
        for invalid: Value in [.null, [:], [], .array(records + [buildPhotoRecord()])] {
            XCTAssertThrowsError(try engine.execute(state: state, action: "photo-add-batch", input: ["records":invalid]))
        }
        XCTAssertThrowsError(try engine.execute(state: state, action: "photo-add-batch"))
        let full = try engine.execute(state: state, action: "photo-add-batch", input: ["records":.array(records)])
        XCTAssertEqual(full["state"]["photos"].array.map(\.id), records.map(\.id))
        XCTAssertThrowsError(try engine.execute(state: full["state"], action: "photo-add-batch", input: ["records":.array([buildPhotoRecord()])]))
        let partial = try engine.execute(state: state, action: "photo-add-batch", input: ["records":.array(Array(records.prefix(39)))])["state"]
        XCTAssertThrowsError(try engine.execute(state: partial, action: "photo-add-batch", input: ["records":.array([records[39], buildPhotoRecord()])]))
        XCTAssertEqual(partial["photos"].array.count, 39)
        let completed = try engine.execute(state: partial, action: "photo-add-batch", input: ["records":.array([records[39]])])
        XCTAssertEqual(completed["state"]["photos"].array.map(\.id), records.map(\.id))
        XCTAssertEqual(completed["state"]["revision"].integer, partial["revision"].integer + 1)
    }

    func testDraftPhotoRemovalRequiresExactOwnershipAndPreservesSavedEventImages() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"gear", "type":"Chain"], ["id":"other", "type":"Chain"]]
        state["gearEvents"] = [["id":"saved-event", "gearId":"gear", "kind":"maintenance", "occurredDate":"2024-01-01"]]
        let draftID = UUID().uuidString.lowercased(), photoID = UUID().uuidString.lowercased()
        let savedPhoto: Value = ["id":.string(UUID().uuidString.lowercased()), "ownerType":"event", "ownerId":"saved-event", "gearId":"gear"]
        let draftPhoto: Value = ["id":.string(photoID), "ownerType":"draft", "ownerId":.string(draftID), "gearId":"gear", "createdAt":.string(ISO8601DateFormatter().string(from: Date()))]
        state["photos"] = .array([savedPhoto, draftPhoto])
        let input: Value = ["ownerType":"draft", "ownerId":.string(draftID), "gearId":"gear", "id":.string(photoID), "action":"delete", "confirmed":true]
        let invalidFields: [(String, Value)] = [
            ("ownerId", .string(UUID().uuidString.lowercased())),
            ("gearId", "other"),
            ("id", savedPhoto["id"]),
            ("confirmed", false),
            ("action", "cover"),
            ("action", "reorder")
        ]
        for (field, value) in invalidFields {
            var invalid = input; invalid[field] = value
            XCTAssertThrowsError(try engine.execute(state: state, action: "photo-edit", input: invalid), field)
        }
        let response = try engine.execute(state: state, action: "photo-edit", input: input)
        XCTAssertEqual(response["state"]["photos"], .array([savedPhoto]))
        XCTAssertEqual(response["state"]["gearEvents"], state["gearEvents"])
        XCTAssertEqual(state["photos"], .array([savedPhoto, draftPhoto]))
    }

    func testRemovingDraftPhotoFreesSlotForReplacementImage() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"gear", "type":"Chain"]]
        let draftID = UUID().uuidString.lowercased()
        let created = ISO8601DateFormatter().string(from: Date())
        let photos: [Value] = (0..<40).map { _ in
            ["id":.string(UUID().uuidString.lowercased()), "ownerType":"draft", "ownerId":.string(draftID), "gearId":"gear", "createdAt":.string(created)]
        }
        state["photos"] = .array(photos)
        let replacementID = UUID().uuidString.lowercased()
        let input: Value = ["id":.string(replacementID), "ownerType":"draft", "ownerId":.string(draftID), "gearId":"gear",
                            "metadata":["width":1, "height":1, "bytes":100, "hash":.string(String(repeating: "a", count: 64))]]
        XCTAssertThrowsError(try engine.execute(state: state, action: "photo-add", input: input))
        state = try engine.execute(state: state, action: "photo-edit", input: ["ownerType":"draft", "ownerId":.string(draftID), "gearId":"gear", "id":photos[0]["id"], "action":"delete", "confirmed":true])["state"]
        XCTAssertEqual(state["photos"].array.count, 39)
        state = try engine.execute(state: state, action: "photo-add", input: input)["state"]
        XCTAssertEqual(state["photos"].array.count, 40)
        XCTAssertTrue(state["photos"].array.contains { $0.id == replacementID })
        XCTAssertFalse(state["photos"].array.contains { $0.id == photos[0].id })
        XCTAssertTrue(Set(photos.dropFirst().map(\.id)).isSubset(of: Set(state["photos"].array.map(\.id))))
    }

    func testAllDayMigrationKeepsLastSameDayPlacementAndReminderAnchor() throws {
        let engine = try NativeDomain()
        let raw: Value = ["gears":[["id":"b", "type":"Bike"],["id":"c", "type":"Bike"],["id":"w", "type":"Wheelset"]],
            "events":[["id":"first", "gearId":"w", "parentId":"b", "at":"2024-01-01T08:00:00"],
                      ["id":"last", "gearId":"w", "parentId":"c", "at":"2024-01-01T18:00:00"]],
            "activities":[["id":"a", "snapshot":[["id":"w", "parentId":"b"]]]],
            "reminders":[["id":"r", "anchor":"installation", "anchorID":"first"]]]
        let migrated = try engine.execute(state: raw, action: "initialize")["state"]
        XCTAssertEqual(migrated["events"].array.count, 1)
        XCTAssertEqual(migrated["events"].array[0]["id"], "last")
        XCTAssertEqual(migrated["events"].array[0]["at"], "2024-01-01T00:00:00")
        XCTAssertTrue(migrated["events"].array[0]["allDay"].flag)
        XCTAssertEqual(migrated["reminders"].array[0]["anchorID"], "last")
        XCTAssertEqual(migrated["activities"], raw["activities"])
        let repeated = try engine.execute(state: migrated, action: "initialize")["state"]
        XCTAssertEqual(repeated["events"], migrated["events"])
        XCTAssertEqual(repeated["installationDatesMigration"], migrated["installationDatesMigration"])
    }
    func testAllDayMovesReuseRecordAndRetainReminderIdentity() throws {
        let engine = try NativeDomain()
        var s: Value = ["gears":[["id":"b", "type":"Bike"],["id":"w", "type":"Wheelset"]], "activities":[], "events":[]]
        s = try engine.execute(state: s, action: "moves", input: ["changes":[["gearId":"w", "parentId":"b"]], "at":"2024-01-01"])["state"]
        let id = s["events"].array[0].id
        s = try engine.execute(state: s, action: "moves", input: ["changes":[["gearId":"w", "parentId":.null]], "at":"2024-01-01T16:30:00"])["state"]
        XCTAssertEqual(s["events"].array.count, 1)
        XCTAssertEqual(s["events"].array[0].id, id)
        XCTAssertEqual(s["events"].array[0]["at"], "2024-01-01T00:00:00")
        XCTAssertThrowsError(try engine.execute(state: s, action: "history-save", input: ["gearId":"w", "parentId":"b", "at":"2024-01-01"]))
    }
    func testCopyGearStartsIndependentAndDoesNotCopyRemoteOrUsage() throws {
        let engine = try NativeDomain()
        var s = try engine.execute(state: .null, action: "initialize")["state"]
        s["gears"] = [["id":"chain", "name":"Chain 1", "type":"Chain", "categoryId":"Chain", "notes":"12 speed", "retired":true, "hidden":true, "purchased":"2024-01-01", "remoteId":"remote", "sourceGearId":"import", "importedTotals":["distance":100000], "coverPhotoId":"photo"]]
        s["photos"] = [["id":"photo", "ownerType":"gear", "ownerId":"chain"]]
        let original = s["gears"].array[0]
        let response = try engine.execute(state: s, action: "gear-copy", input: ["sourceId":"chain", "gear":["name":"Chain 2", "condition":"unused"]])
        let copy = response["result"]
        XCTAssertNotEqual(copy.id, "chain")
        XCTAssertEqual(copy["notes"], "12 speed")
        XCTAssertEqual(copy["categoryId"], "Chain")
        XCTAssertEqual(copy["condition"], "unused")
        for key in ["remoteId", "sourceGearId", "importedTotals", "coverPhotoId", "purchased", "hidden"] { XCTAssertTrue(copy[key].isNull) }
        XCTAssertFalse(copy["retired"].flag)
        XCTAssertEqual(response["state"]["gears"].array[0], original)
        XCTAssertTrue(response["state"]["events"].array.isEmpty)
        XCTAssertEqual(GearInventory.readStatus(state: response["state"], gearID: copy.id, at: "9999-12-31"), "stock")
        let stats = try engine.execute(state: response["state"], action: "view")["result"]["statistics"][copy.id]
        XCTAssertEqual(stats["distance"].double, 0)
    }
    func testCopyMountedComponentAndMainGearAlwaysEnterStock() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "name":"Tarmac", "type":"Bike", "categoryId":"Bike"],
                          ["id":"chain", "name":"KMC Chain", "type":"Chain", "categoryId":"Chain"]]
        state["events"] = [["id":"mount", "gearId":"chain", "parentId":"bike", "at":"2024-01-01T00:00:00", "allDay":true]]
        for sourceID in ["bike", "chain"] {
            let response = try engine.execute(state: state, action: "gear-copy", input: ["sourceId":.string(sourceID), "gear":["placement":"active", "purchased":"2024-02-01"]])
            let copiedState = response["state"], copy = response["result"]
            XCTAssertEqual(copy["name"], state["gears"].array.first { $0.id == sourceID }?["name"])
            XCTAssertEqual(GearInventory.readStatus(state: copiedState, gearID: copy.id, at: "9999-12-31"), "stock")
            XCTAssertEqual(copiedState["events"], state["events"])
            XCTAssertEqual(Array(copiedState["gears"].array.prefix(2)), state["gears"].array)
            XCTAssertEqual(copiedState["gearStates"].array.first { $0["gearId"].text == copy.id }?["at"], "2024-02-01T00:00:00")
            XCTAssertFalse(copiedState["events"].array.contains { $0["gearId"].text == copy.id || $0["parentId"].text == copy.id })
        }
    }
    func testReadOnlyDeviceMigrationWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["GEARHOUSE_MIGRATION_SOURCE"] else { throw XCTSkip("Optional device migration fixture not supplied") }
        let raw = try Value.decode(Data(contentsOf: URL(fileURLWithPath: path))), engine = try NativeDomain()
        let migrated = try engine.execute(state: raw, action: "initialize")["state"]
        XCTAssertTrue(migrated["events"].array.allSatisfy { $0["allDay"].flag && $0["at"].text.hasSuffix("T00:00:00") })
        XCTAssertEqual(migrated["activities"], raw["activities"])
        for key in ["gearEvents", "photos"] { XCTAssertEqual(migrated[key], raw[key]) }
        let expectedGears = raw["gears"].array.map { original -> Value in
            var gear = original
            if gear["categoryId"] == "Wheel" { gear["categoryId"] = "Wheelset" }
            if gear["type"] == "Wheel" { gear["type"] = "Wheelset" }
            return gear
        }
        XCTAssertEqual(migrated["gears"], .array(expectedGears))
        XCTAssertEqual(try engine.execute(state: raw, action: "view")["result"]["statistics"], try engine.execute(state: migrated, action: "view")["result"]["statistics"])
    }
    func testUserFacingErrorsHideDiagnosticsAndPreserveActions() {
        XCTAssertEqual(URLError(.notConnectedToInternet).userFacingMessage, "网络已断开，请连接网络后重试。")
        XCTAssertEqual(ICUClientError.badResponse(429).userFacingMessage, "请求过于频繁，请稍后重试。")
        XCTAssertEqual(DomainError("请求标识无效").userFacingMessage, "无法保存记录，请重新打开后重试。")
        XCTAssertEqual(DomainError("TypeError: undefined is not an object").userFacingMessage, "操作未完成，请重试。")
        XCTAssertEqual(DomainError("该时间已有装配记录，请编辑原记录").userFacingMessage, "该时间已有装配记录，请编辑原记录")
        XCTAssertEqual(UserFacingError.text("Intervals.icu 请求失败（HTTP 403）"), "连接已失效，请检查并更新 API Key。")
        for raw in ["ICU 活动返回格式无效", "备份图片校验失败", "网络已断开，请连接网络后重试。"] {
            let message = UserFacingError.text(raw)
            XCTAssertEqual(UserFacingError.text(message), message)
        }
    }

    func testValidationCoversEarlierCyclesAndDoesNotTrustAnUnchangedRevision() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"a"], ["id":"b"]]
        state["events"] = [["gearId":"a", "parentId":"b", "at":"2024-01-01T00:00:00"]]
        XCTAssertNoThrow(try engine.execute(state: state, action: "view"))
        // The current graph is acyclic, but an earlier instant contains a cycle.
        state["events"] = .array(state["events"].array + [
            ["gearId":"b", "parentId":"a", "at":"2024-02-01T00:00:00"],
            ["gearId":"a", "parentId":.null, "at":"2024-03-01T00:00:00"]
        ])
        XCTAssertThrowsError(try engine.execute(state: state, action: "view"))
        XCTAssertThrowsError(try engine.execute(state: state, action: "initialize"))
        state["events"] = []
        XCTAssertNoThrow(try engine.execute(state: state, action: "view"))
    }
    func testValidationAppliesSameInstantAsOneBatchAndHonorsLastTie() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"a"], ["id":"b"]]
        state["events"] = [
            ["gearId":"b", "parentId":"a", "at":"2024-01-01T00:00:00"],
            ["gearId":"a", "parentId":"b", "at":"2024-02-01T00:00:00"],
            ["gearId":"b", "parentId":.null, "at":"2024-02-01T00:00:00"]
        ]
        XCTAssertNoThrow(try engine.execute(state: state, action: "view"))
        state["events"] = .array(state["events"].array + [["gearId":"b", "parentId":"a", "at":"2024-02-01T00:00:00"]])
        XCTAssertThrowsError(try engine.execute(state: state, action: "view"))
    }

    func testSharedRulesTreeHistoryAndRecompute() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        func run(_ action: String, _ input: Value) throws -> Value {
            let response = try engine.execute(state: state, action: action, input: input)
            state = response["state"]; return response["result"]
        }
        let bike = try run("gear", ["name":"Tarmac","type":"Bike"])
        let wheel = try run("component", ["parentId":bike["id"],"at":"2024-10-28T16:30:00","gear":["name":"CL II","type":"Wheelset"]])
        let second = try run("gear", ["name":"Propel","type":"Bike"])
        _ = try run("history-save", ["gearId":wheel["id"],"parentId":.null,"at":"2026-02-07T16:30:00"])
        _ = try run("history-save", ["gearId":wheel["id"],"parentId":second["id"],"at":"2026-09-28T20:59:00"])
        let snapshot = try run("view", ["date":"2025-01-01"])
        XCTAssertEqual(snapshot["events"].array.count, 1)
        XCTAssertThrowsError(try run("moves", ["changes":[["gearId":second["id"],"parentId":wheel["id"]]],"at":"2026-10-01T00:00:00"]))
        XCTAssertEqual(state["events"].array.count, 3)
        let preview = try run("recompute-preview", ["gearId":wheel["id"],"from":"2024-10-01","to":"2026-10-01"])
        XCTAssertEqual(preview["gearIds"].array, [wheel["id"]])
    }
    func testEventAndPhotoLifecycleSharedWithWeb() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        func run(_ action: String, _ input: Value) throws -> Value {
            let response = try engine.execute(state: state, action: action, input: input)
            state = response["state"]; return response["result"]
        }
        let gear = try run("gear", ["name":"KMC Chain","type":"Chain"])
        let event: Value = ["gearId":gear["id"],"kind":"hotWax","occurredDate":"2026-10-01","notes":"测试"]
        let saved = try run("event-save", ["requestId":.string(UUID().uuidString),"event":event])
        XCTAssertEqual(state["gearEvents"].array.count,1)
        _ = try run("event-delete", ["requestId":.string(UUID().uuidString),"id":saved["id"],"confirmed":true])
        XCTAssertTrue(state["gearEvents"].array.isEmpty)
        _ = try run("delete", ["id":gear["id"]])
        XCTAssertThrowsError(try run("purge", ["id":gear["id"],"confirmed":false]))
        _ = try run("purge", ["id":gear["id"],"confirmed":true])
        XCTAssertTrue(state["gears"].array.isEmpty)
    }
    func testCLIIIntervalsBaselineAndIndoorRecompute() throws {
        let engine = try NativeDomain()
        var s = try engine.execute(state: .null, action: "initialize")["state"]
        func run(_ action:String,_ input:Value) throws -> Value {
            let response=try engine.execute(state:s,action:action,input:input);s=response["state"];return response["result"]
        }
        _ = try run("gear-import", ["rows":[
            ["id":"t","name":"Tarmac","type":"Bike","component_ids":["w"]],
            ["id":"p","name":"Propel","type":"Bike"],
            ["id":"w","name":"CL II","type":"Wheelset","component":true,"distance":100000,"time":10000,"activities":10]
        ]])
        let t=s["gears"].array.first{$0["sourceGearId"].text=="t"}!,p=s["gears"].array.first{$0["sourceGearId"].text=="p"}!,w=s["gears"].array.first{$0["sourceGearId"].text=="w"}!
        // Replace the unknown import-time installation with the user's explicit timeline.
        s["events"] = []
        for (at,parent) in [("2024-10-28T16:30:00",t["id"]),("2026-02-07T16:30:00",Value.null),("2026-09-28T20:59:00",p["id"])] {
            _ = try run("history-save",["gearId":w["id"],"parentId":parent,"at":.string(at)])
        }
        let rows:Value = [
            ["id":"before","type":"Ride","start_date_local":"2024-10-27T23:59:59","distance":99999,"moving_time":100,"gear":["id":"t"]],
            ["id":"on-tarmac","type":"Ride","start_date_local":"2024-10-28T00:00:00","distance":10000,"moving_time":100,"gear":["id":"t"]],
            ["id":"removed","type":"Ride","start_date_local":"2026-02-07T00:00:00","distance":99999,"moving_time":100,"gear":["id":"t"]],
            ["id":"on-propel","type":"Ride","start_date_local":"2026-09-28T00:00:00","distance":20000,"moving_time":100,"gear":["id":"p"]],
            ["id":"virtual","type":"VirtualRide","start_date_local":"2026-10-01T10:00:00","distance":50000,"moving_time":100,"gear":["id":"p"]]
        ]
        _ = try run("sync-rows",["rows":rows,"historical":true,"from":"2024-01-01","to":"2026-10-16","next":"2026-10-17"])
        let input:Value=["gearId":w["id"],"from":"2024-01-01","to":"2026-10-16"]
        let preview=try run("recompute-preview",input)
        XCTAssertTrue(preview["totals"].array[0]["baselineDisabled"].flag)
        XCTAssertThrowsError(try run("recompute",input))
        var confirmed=input;confirmed["baselineConfirmed"]=true
        _ = try run("recompute",confirmed)
        let view=try run("view",[:]);XCTAssertEqual(view["statistics"][w.id]["distance"].double,30000)
        XCTAssertEqual(view["statistics"][w.id]["count"].integer,3)
        let usage=try run("usage",["id":w["id"],"from":"2026-09-28","to":"2026-10-16"])
        XCTAssertEqual(usage["summary"]["distance"].double,20000)
        XCTAssertEqual(usage["rows"].array.count,2)
    }
    func testOrganizationPreservesActivitySnapshotsAndRootTimeline() throws {
        let engine=try NativeDomain()
        var s=try engine.execute(state:.null,action:"initialize")["state"]
        s["gears"]=[["id":"bike","name":"Bike","type":"Bike"],["id":"wheel","name":"Wheel","type":"Wheelset"],["id":"front","name":"IRC Front","type":"Tyre"],["id":"rear","name":"IRC Rear","type":"Tyre"]]
        s["events"]=[["id":"e1","gearId":"wheel","parentId":"bike","at":"2024-01-01T00:00:00"],["id":"e2","gearId":"front","parentId":"bike","at":"2024-01-02T00:00:00"],["id":"e3","gearId":"rear","parentId":"bike","at":"2024-01-02T00:00:00"],["id":"e4","gearId":"wheel","parentId":.null,"at":"2025-01-01T00:00:00"]]
        s["activities"]=[["id":"ride","at":"2024-02-01T00:00:00","snapshot":[["id":"front","parentId":"bike"]]]]
        let oldActivities=s["activities"]
        let changes:Value=[["gearId":"front","fromParentId":"bike","parentId":"wheel"],["gearId":"rear","fromParentId":"bike","parentId":"wheel"]]
        let result=try engine.execute(state:s,action:"organize",input:["changes":changes])
        XCTAssertEqual(result["state"]["activities"],oldActivities)
        XCTAssertEqual(result["result"]["changed"].integer,2)
        for row in result["result"]["rows"].array {XCTAssertEqual(row["ranges"].array[0]["to"].text,"2025-01-01T00:00:00")}
    }
    func testBatchAPIsDistinguishEmptySelectionFromLimitOverflow() throws {
        let engine = try NativeDomain()
        let state = try engine.execute(state: .null, action: "initialize")["state"]
        let changes: [Value] = (0..<500).map { ["gearId": .string("gear-\($0)"), "parentId":"target", "fromParentId":"original"] }
        let ids = changes.map { $0["gearId"] }
        let overflowMessage = "每次最多调整 499 件装备，请减少选择后重试。"
        for action in ["moves", "organize-preview", "organize", "inventory-batch-preview", "inventory-batch"] {
            let inventory = action.hasPrefix("inventory-")
            for count in [0, 500] {
                let input: Value = inventory
                    ? ["gearIds": .array(Array(ids.prefix(count))), "at":"2024-02-01"]
                    : ["changes": .array(Array(changes.prefix(count))), "at":"2024-02-01"]
                XCTAssertThrowsError(try engine.execute(state: state, action: action, input: input), "\(action) \(count)") { error in
                    let expected = count == 500 ? overflowMessage : inventory ? "请选择要移动的装备。" : "没有可保存的修改"
                    XCTAssertEqual((error as? DomainError)?.message, expected)
                    if count == 500 { XCTAssertEqual(UserFacingError.message(error), expected) }
                }
            }
        }
    }
    func testBatchAPIsAccept499AndInventoryPreservesSubtreeDeduplication() throws {
        let engine = try NativeDomain()
        let ids = (0..<500).map { "gear-\($0)" }
        let gears: [Value] = [["id":"original", "name":"Bike", "type":"Bike"], ["id":"target", "name":"Wheel", "type":"Wheelset"]]
            + ids.map { ["id":.string($0), "name":.string($0), "type":"Chain"] }
        let events: [Value] = (["target"] + ids).map { ["id":.string("mount-" + $0), "gearId":.string($0), "parentId":"original", "at":"2024-01-01T00:00:00"] }
        let state = try engine.execute(state: ["gears":.array(gears), "events":.array(events), "activities":[]], action: "initialize")["state"]
        let changes: [Value] = ids.prefix(499).map { ["gearId":.string($0), "parentId":"target", "fromParentId":"original"] }
        let moved = try engine.execute(state: state, action: "moves", input: ["changes":.array(changes), "at":"2024-02-01"])
        XCTAssertEqual(moved["state"]["events"].array.filter { $0["at"].text == "2024-02-01T00:00:00" }.count, 499)
        let organization = try engine.execute(state: state, action: "organize-preview", input: ["changes":.array(changes)])["result"]
        XCTAssertEqual(organization["changed"].integer, 499)
        let organized = try engine.execute(state: state, action: "organize", input: ["changes":.array(changes), "revision":organization["revision"]])
        XCTAssertEqual(organized["result"]["changed"].integer, 499)

        let selection = [Value.string("original")] + ids.prefix(498).map(Value.string)
        let preview = try engine.execute(state: state, action: "inventory-batch-preview", input: ["gearIds":.array(selection), "at":"2024-02-01"])["result"]
        XCTAssertEqual(preview["rows"].array.map { $0["gearId"].text }, ["original"])
        let stored = try engine.execute(state: state, action: "inventory-batch", input: ["gearIds":.array(selection), "at":"2024-02-01", "revision":preview["revision"]])["state"]
        XCTAssertEqual(stored["gearOperations"].array.count, 1)
        XCTAssertEqual(GearInventory.readStatus(state: stored, gearID: ids[0], at: "2024-02-02T00:00:00"), "stock")
        let overflow = selection + [Value.string(ids[498])]
        XCTAssertThrowsError(try engine.execute(state: state, action: "inventory-batch-preview", input: ["gearIds":.array(overflow), "at":"2024-02-01"])) { error in
            XCTAssertEqual((error as? DomainError)?.message, "每次最多调整 499 件装备，请减少选择后重试。")
        }
    }
    func testDeletionConfirmationHandlesJSONKeyOrderAndConcurrentEdit() throws {
        let engine=try NativeDomain()
        var s=try engine.execute(state:.null,action:"initialize")["state"]
        let activity:Value=["id":"a","name":"Ride","at":"2026-10-01T10:00:00","snapshot":[]]
        s["activities"]=[activity]
        let before=try activity.jsonString()
        let input:Value=["rows":[],"from":"2026-10-01","to":"2026-10-02","deleted":[["id":"a","before":.string(before)]]]
        let removed=try engine.execute(state:s,action:"sync-rows",input:input)
        XCTAssertTrue(removed["state"]["activities"].array[0]["deleted"].flag)
        var changed=activity;changed["name"]="Changed";s["activities"]=[changed]
        let retained=try engine.execute(state:s,action:"sync-rows",input:input)
        XCTAssertFalse(retained["state"]["activities"].array[0]["deleted"].flag)
    }

    func testReadOnlyWebDataParityWhenFixtureProvided() throws {
        guard let source=ProcessInfo.processInfo.environment["GEARHOUSE_PARITY_SOURCE"],let expected=ProcessInfo.processInfo.environment["GEARHOUSE_PARITY_EXPECTED"] else { throw XCTSkip("Optional local data parity fixture not supplied") }
        let raw=try Value.decode(Data(contentsOf:URL(fileURLWithPath:source)))
        let metrics=try Value.decode(Data(contentsOf:URL(fileURLWithPath:expected)))
        let engine=try NativeDomain()
        let view=try engine.execute(state:raw,action:"view")["result"]
        XCTAssertEqual(view["statistics"],metrics)
        for field in ["events","gearEvents","activities","photos"] { XCTAssertEqual(view[field],raw[field]) }
        XCTAssertEqual(view["gears"].array.count, raw["gears"].array.count)
        for old in raw["gears"].array {
            var fields = view["gears"].array.first { $0.id == old.id }!.object
            if old["categoryId"].isNull { fields.removeValue(forKey: "categoryId") }
            XCTAssertEqual(Value.object(fields), old)
        }
    }

    func testPrototypeMigrationImportsRetirementAndComponentMetadataOnce() throws {
        let engine=try NativeDomain()
        let raw:Value=["gears":[["id":"old-bike","name":"Old Bike","type":"Bike","remoteID":"bike","retired":false]],"activities":[]]
        let initial=try engine.execute(state:raw,action:"initialize")["state"]
        let rows:Value=[["id":"bike","name":"Old Bike","type":"Bike","retired":"2025-10-01T00:00:00"]]
        let next=try engine.execute(state:initial,action:"gear-import",input:["rows":rows])["state"]
        XCTAssertTrue(next["gears"].array[0]["retired"].flag)
        XCTAssertEqual(next["gears"].array[0]["retiredAt"].text,"2025-10-01T00:00:00")
        var edited=next
        var gear=edited["gears"].array[0];gear["retired"]=false;edited["gears"]=[gear]
        let repeated=try engine.execute(state:edited,action:"gear-import",input:["rows":rows])["state"]
        XCTAssertFalse(repeated["gears"].array[0]["retired"].flag)
    }

    private final class AssignmentSession {
        let engine: NativeDomain
        var state: Value
        init() throws {
            engine = try NativeDomain()
            state = try engine.execute(state: .null, action: "initialize")["state"]
            state["gears"] = [["id":"a", "name":"Bike A", "type":"Bike", "remoteId":"remote-a"],
                              ["id":"b", "name":"Bike B", "type":"Bike", "remoteId":"remote-b"],
                              ["id":"c", "name":"Bike C", "type":"Bike", "remoteId":"remote-c"],
                              ["id":"shoe", "name":"Shoes", "type":"CyclingShoes"],
                              ["id":"trainer", "name":"Trainer", "type":"Trainer"],
                              ["id":"chain", "name":"Chain", "type":"Chain"]]
            try sync("remote-a")
        }
        @discardableResult func run(_ action: String, _ input: Value = [:]) throws -> Value {
            let response = try engine.execute(state: state, action: action, input: input)
            state = response["state"]; return response["result"]
        }
        func sync(_ remote: String) throws {
            try run("sync-rows", ["rows":[["id":"ride", "name":"Ride", "type":"Ride", "start_date_local":"2026-07-04T08:00:00", "distance":10000, "moving_time":1000, "gear":remote.isEmpty ? .null : ["id":.string(remote)]]], "from":"2026-07-01", "to":"2026-07-10"])
        }
        @discardableResult func assign(_ patch: Value) throws -> Value { try run("assignment", ["id":"ride", "assignment":patch]) }
        var activity: Value { state["activities"].array[0] }
    }
    func testShoePatchKeepsFrozenMainAssemblyAndFollowsICUChanges() throws {
        let session = try AssignmentSession()
        var activity = session.activity
        activity["snapshot"] = [["id":"a", "parentId":.null], ["id":"chain", "parentId":"a", "distanceIncluded":false]]
        session.state["activities"] = [activity]
        try session.assign(["shoe":"shoe"])
        XCTAssertEqual(session.activity["main"], "a")
        XCTAssertTrue(session.activity["snapshot"].array.contains { $0.id == "chain" && $0["distanceIncluded"] == false })
        XCTAssertFalse(session.activity["pending"].flag)
        try session.sync("remote-b")
        XCTAssertEqual(session.activity["main"], "b")
        XCTAssertEqual(session.activity["extras"], ["shoe"])
        XCTAssertEqual(Set(session.activity["snapshot"].array.map(\.id)), ["b", "shoe"])
        XCTAssertFalse(session.activity["pending"].flag)
    }
    func testAssignmentPatchPreservesOtherFieldsWhenSyncFinishesDuringEditing() throws {
        let session = try AssignmentSession()
        try session.assign(["trainer":"trainer"])
        try session.sync("remote-b") // The form was originally opened on A.
        try session.assign(["shoe":"shoe"])
        XCTAssertEqual(session.activity["main"], "b")
        XCTAssertEqual(Set(session.activity["extras"].array.map(\.text)), ["shoe", "trainer"])
        try session.assign(["shoe":.null])
        try session.sync("remote-c")
        XCTAssertEqual(session.activity["main"], "c")
        XCTAssertEqual(session.activity["extras"], ["trainer"])
        XCTAssertTrue(session.activity["assignmentOverrides"]["shoe"].flag)
        XCTAssertFalse(session.activity["pending"].flag)
    }
    func testLocalMainKeepsOriginalSyncBaseAndConflictAcrossOrdinaryReads() throws {
        let session = try AssignmentSession()
        try session.assign(["main":"b", "shoe":"shoe"])
        let editID = session.activity["mainEditId"]
        try session.sync("remote-c")
        try session.sync("remote-c")
        try session.assign(["trainer":"trainer"])
        XCTAssertEqual(session.activity["mainSyncBase"], "remote-a")
        XCTAssertEqual(session.activity["mainEditId"], editID)
        XCTAssertEqual(session.activity["main"], "b")
        XCTAssertEqual(session.activity["remoteId"], "remote-c")
        XCTAssertTrue(session.activity["mainConflict"].flag)
        XCTAssertThrowsError(try session.run("assignment-rebase", ["id":"ride", "remoteId":"remote-a"]))
        try session.run("assignment-rebase", ["id":"ride", "remoteId":"remote-c"])
        XCTAssertFalse(session.activity["mainConflict"].flag)
        try session.sync("remote-a")
        XCTAssertTrue(session.activity["mainConflict"].flag)
        try session.assign(["followRemote":true])
        XCTAssertEqual(session.activity["main"], "a")
        XCTAssertEqual(Set(session.activity["extras"].array.map(\.text)), ["shoe", "trainer"])
        XCTAssertFalse(session.activity["pending"].flag)
        XCTAssertTrue(session.activity["mainSyncBase"].isNull)
    }
    func testExplicitNoMainRemainsAnOverrideAndDoesNotRestoreADefault() throws {
        let session = try AssignmentSession()
        try session.assign(["main":.null])
        XCTAssertTrue(session.activity["main"].isNull)
        XCTAssertTrue(session.activity["pending"].flag)
        try session.sync("remote-c")
        XCTAssertTrue(session.activity["main"].isNull)
        XCTAssertTrue(session.activity["mainConflict"].flag)
        try session.sync("")
        XCTAssertFalse(session.activity["pending"].flag)
        try session.sync("remote-a")
        XCTAssertTrue(session.activity["main"].isNull)
        XCTAssertTrue(session.activity["pending"].flag)
    }
    func testLegacyAssignmentMigrationPreservesIntentAndSnapshotUntilReleased() throws {
        let session = try AssignmentSession()
        var legacy = session.activity
        var fields = legacy.object; fields.removeValue(forKey:"assignmentOverrides")
        legacy = .object(fields); legacy["manual"] = true
        legacy["snapshot"] = [["id":"a", "parentId":.null], ["id":"chain", "parentId":"a"]]
        session.state["activities"] = [legacy]
        let original = session.state["activities"]
        try session.run("initialize")
        try session.run("initialize")
        XCTAssertEqual(session.state["activities"], original)
        try session.sync("remote-b")
        XCTAssertEqual(session.activity["main"], "a")
        XCTAssertTrue(session.activity["mainConflict"].flag)
        try session.assign(["shoe":"shoe"])
        XCTAssertEqual(session.activity["assignmentOverrides"]["main"], "legacy")
        XCTAssertTrue(session.activity["snapshot"].array.contains { $0.id == "chain" })
        let backup = try Value.decode(session.state.jsonData())
        XCTAssertEqual(try session.engine.execute(state:backup,action:"initialize")["state"]["activities"], session.state["activities"])
        try session.assign(["followRemote":true])
        XCTAssertEqual(session.activity["main"], "b")
        XCTAssertEqual(session.activity["extras"], ["shoe"])
        XCTAssertFalse(session.activity["pending"].flag)
    }
    func testShoePatchAllowsUnrelatedAssemblyHistoryRecompute() throws {
        let session = try AssignmentSession()
        try session.assign(["shoe":"shoe"])
        try session.run("history-save", ["gearId":"chain", "parentId":"a", "at":"2026-07-01"])
        let input: Value = ["gearId":"chain", "from":"2026-07-01", "to":"2026-07-10"]
        let preview = try session.run("recompute-preview", input)
        XCTAssertEqual(preview["skipped"]["manual"].integer, 0)
        XCTAssertEqual(preview["changed"].integer, 1)
        try session.run("recompute", input)
        XCTAssertEqual(try session.run("view")["statistics"]["chain"]["distance"].double, 10000)
        XCTAssertEqual(session.activity["extras"], ["shoe"])
    }
    func testWriteConfirmationRejectsStaleIntentAndRecoversLostConfirmation() throws {
        let session = try AssignmentSession()
        try session.assign(["main":"b"])
        let first = session.activity["mainEditId"]
        try session.assign(["main":"c"])
        XCTAssertThrowsError(try session.run("write-result", ["id":"ride", "editId":first, "main":"b", "target":"remote-b"]))
        try session.sync("remote-c") // A successful write whose confirmation was lost.
        XCTAssertFalse(session.activity["pending"].flag)
        XCTAssertFalse(session.activity["mainConflict"].flag)
        XCTAssertEqual(session.activity["main"], "c")
        XCTAssertEqual(session.activity["mainSyncBase"], "remote-c")
    }
    func testCatalogRefreshUpdatesOnlyCatalogAndDoesNotRepeatImport() throws {
        let session = try AssignmentSession()
        let rows: Value = [["id":"source", "name":"Imported Bike", "type":"Bike", "component_ids":["part"]],
                           ["id":"part", "name":"Imported Chain", "type":"Chain", "component":true, "distance":1000, "time":100, "activities":1]]
        try session.run("gear-import", ["rows":rows])
        let gears = session.state["gears"], events = session.state["events"], activities = session.state["activities"]
        let next: Value = [["id":"source", "name":"Renamed Bike", "type":"Bike"], ["id":"new", "name":"New Bike", "type":"Bike"]]
        for _ in 0..<3 { try session.run("gear-import", ["rows":next]) }
        XCTAssertEqual(session.state["gears"], gears)
        XCTAssertEqual(session.state["events"], events)
        XCTAssertEqual(session.state["activities"], activities)
        XCTAssertEqual(session.state["remoteGears"].array.map(\.id), ["source", "new"])
        XCTAssertEqual(session.state["remoteGears"].array[0]["name"], "Renamed Bike")
        let saved = session.state
        for invalid: Value in [.null, [:], [["id":"bad"]], [next.array[0], next.array[0]]] {
            XCTAssertThrowsError(try session.run("gear-refresh", ["rows":invalid]))
            XCTAssertEqual(session.state, saved)
        }
    }
    func testLinkingUnknownRemoteResolvesActivitiesWithoutDiscardingShoes() throws {
        let session = try AssignmentSession()
        try session.assign(["shoe":"shoe"])
        try session.sync("new")
        XCTAssertTrue(session.activity["unknown"].flag)
        try session.run("gear-refresh", ["rows":[["id":"new", "name":"New Bike", "type":"Bike"]]])
        let originalCount = session.state["gears"].array.count
        var gear = session.state["gears"].array.first { $0.id == "b" }!
        gear["remoteId"] = "new"
        try session.run("gear", gear)
        XCTAssertEqual(session.activity["main"], "b")
        XCTAssertEqual(session.activity["extras"], ["shoe"])
        XCTAssertFalse(session.activity["unknown"].flag)
        XCTAssertEqual(session.state["gears"].array.count, originalCount)
    }
    func testViewStatisticsPreserveBaselineAndFirstSnapshotDistanceDecision() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        let baseline: Value = ["distance":1000, "seconds":100, "count":4, "through":"2024-01-02T12:00:00"]
        state["gears"] = [["id":"chain", "type":"Chain", "importedTotals":baseline],
                          ["id":"local", "type":"Chain", "totalsMode":"local", "importedTotals":baseline],
                          ["id":"empty", "type":"Chain"]]
        func buildActivity(_ id: String, _ at: String, _ distance: Value, _ seconds: Value) -> Value {
            ["id":.string(id), "at":.string(at), "distance":distance, "seconds":seconds,
             "snapshot":[["id":"chain"], ["id":"local"]]]
        }
        var rows = [buildActivity("before", "2024-01-01T12:00:00", 100, 10),
                    buildActivity("equal", "2024-01-02T12:00:00", 200, 20),
                    buildActivity("after", "2024-01-02T13:00:00", 300, 30),
                    buildActivity("excluded-distance", "2024-01-03T12:00:00", 400, 40),
                    buildActivity("missing-distance", "2024-01-04T12:00:00", .null, 50),
                    buildActivity("negative-distance", "2024-01-05T12:00:00", -10, -2)]
        rows[3]["snapshot"] = [["id":"chain", "distanceIncluded":false], ["id":"chain", "distanceIncluded":true], ["id":"local"]]
        for flag in ["deleted", "summary", "unavailable"] {
            var ignored = buildActivity(flag, "2024-01-06T12:00:00", 10000, 10000)
            ignored[flag] = true; rows.append(ignored)
        }
        state["activities"] = .array(rows)
        let response = try engine.execute(state: state, action: "view")
        let statistics = response["result"]["statistics"]
        XCTAssertEqual(statistics["chain"], ["distance":1290, "seconds":218, "count":8])
        XCTAssertEqual(statistics["local"], ["distance":990, "seconds":148, "count":6])
        XCTAssertEqual(statistics["empty"], ["distance":0, "seconds":0, "count":0])
        XCTAssertEqual(response["result"]["activities"], state["activities"])
        XCTAssertEqual(response["state"], state)
        rows[2]["distance"] = 350; state["activities"] = .array(rows)
        XCTAssertEqual(try engine.execute(state: state, action: "view")["result"]["statistics"]["chain"]["distance"].integer, 1340)
    }

    func testViewEventMetricsPreserveTimeBoundariesAndGlobalLimitedStatus() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"chain", "type":"Chain", "createdAt":"2020-01-01T00:00:00",
                           "importedTotals":["distance":1000, "through":"2024-01-02T12:00:00"]],
                          ["id":"local", "type":"Chain", "createdAt":"2020-01-01T00:00:00", "totalsMode":"local",
                           "importedTotals":["distance":1000, "through":"2024-01-02T12:00:00"]],
                          ["id":"other", "type":"Chain", "createdAt":"2020-01-01T00:00:00"]]
        state["gearEvents"] = [["id":"timed", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-03", "occurredTime":"12:00"],
                               ["id":"all-day", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-03"],
                               ["id":"blocked", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-01"],
                               ["id":"local-timed", "gearId":"local", "kind":"maintenance", "occurredDate":"2024-01-03", "occurredTime":"12:00"]]
        let dates = ["2024-01-02T12:00:00", "2024-01-02T13:00:00", "2024-01-03T11:59:59",
                     "2024-01-03T12:00:00", "2024-01-03T23:59:59", "2024-01-04T00:00:00", "2099-01-01T00:00:00"]
        var rows: [Value] = dates.enumerated().map { index, at in
            ["id":.string("a\(index)"), "at":.string(at), "distance":.number(Double((index + 1) * 100)),
             "snapshot":[["id":"chain"], ["id":"local"]]]
        }
        rows.append(["id":"excluded-distance", "at":"2024-01-04T12:00:00", "distance":700,
                     "snapshot":[["id":"chain", "distanceIncluded":false], ["id":"local", "distanceIncluded":false]]])
        rows.append(["id":"negative-distance", "at":"2024-01-04T12:00:00", "distance":-800,
                     "snapshot":[["id":"chain"], ["id":"local"]]])
        rows.append(["id":"unrelated-missing", "at":"2024-01-04T12:00:00", "distance":.null, "snapshot":[["id":"other"]]])
        state["activities"] = .array(rows)
        let current = try engine.execute(state: state, action: "view")["result"]["eventStatistics"]
        XCTAssertEqual(current["timed"]["distance"].integer, 1500)
        XCTAssertEqual(current["timed"]["total"].integer, 1500)
        XCTAssertEqual(current["all-day"]["distance"].integer, 600)
        XCTAssertEqual(current["all-day"]["total"].integer, 1200)
        XCTAssertTrue(current["blocked"]["total"].isNull)
        XCTAssertEqual(current["local-timed"]["total"].integer, 600)
        XCTAssertTrue(current["timed"]["limited"].flag)
        let historical = try engine.execute(state: state, action: "view", input: ["date":"2024-01-03"])["result"]
        XCTAssertEqual(historical["eventStatistics"]["timed"]["distance"].integer, 900)
        XCTAssertEqual(historical["eventStatistics"]["timed"]["total"].integer, 1500)
        XCTAssertEqual(historical["eventStatistics"]["timed"]["days"].integer, 0)
        XCTAssertEqual(historical["eventStatistics"]["all-day"]["distance"].integer, 0)
        XCTAssertFalse(historical["eventStatistics"]["timed"]["limited"].flag)
        XCTAssertEqual(historical["statistics"]["chain"]["distance"].integer, 2400)
        XCTAssertEqual(historical["statistics"]["local"]["distance"].integer, 1500)
        XCTAssertEqual(historical["activities"].array.count, 5)
    }

    func testRemovedCatalogEntryKeepsExistingLinkEditable() throws {
        let session = try AssignmentSession()
        try session.run("gear-refresh", ["rows":[]])
        var gear = session.state["gears"].array.first { $0.id == "a" }!
        gear["name"] = "My Bike"
        try session.run("gear", gear)
        XCTAssertEqual(session.state["gears"].array.first { $0.id == "a" }?["remoteId"], "remote-a")
        gear["id"] = "b" // An absent catalog row cannot be used for a new link.
        XCTAssertThrowsError(try session.run("gear", gear))
    }

    func testValueCodecPreservesJSONTypesWithoutCoercion() throws {
        let data = Data(#"{"yes":true,"no":false,"zero":0,"one":1,"fraction":1.5,"numberText":"1","boolText":"true","null":null,"nullText":"null","nested":[false,0,"0",null,[],{}]}"#.utf8)
        let expected: Value = ["yes":true, "no":false, "zero":0, "one":1, "fraction":.number(1.5),
                               "numberText":"1", "boolText":"true", "null":.null, "nullText":"null",
                               "nested":[false, 0, "0", .null, [], [:]]]
        XCTAssertEqual(try Value.decode(data), expected)
        let fragments: [(String, Value)] = [("true", true), ("false", false), ("0", 0), ("1", 1),
                                            (#""1""#, "1"), (#""true""#, "true"), ("null", .null)]
        for (json, expected) in fragments { XCTAssertEqual(try Value.decode(Data(json.utf8)), expected, json) }
    }

    func testValueCodecKeepsDoubleBitsAtPrecisionAndRangeBoundaries() throws {
        let cases: [(String, UInt64)] = [
            ("-0", 0x8000000000000000), ("-0.0", 0x8000000000000000), ("-0e0", 0x8000000000000000),
            ("5e-324", 0x0000000000000001), ("2.2250738585072014e-308", 0x0010000000000000),
            ("1.7976931348623157e308", 0x7fefffffffffffff),
            ("9007199254740993", 0x4340000000000000), ("18446744073709551615", 0x43f0000000000000),
            ("0.1000000000000000055511151231257827021181583404541015625", 0x3fb999999999999a),
            ("1.23456789012345678901234567890123456789", 0x3ff3c0ca428c59fb),
            ("-0.0011954113153202983", 0xbf5395eb204adbe1)
        ]
        for (json, expectedBits) in cases {
            guard case .number(let value) = try Value.decode(Data(json.utf8)) else {
                XCTFail("Expected a number for " + json); continue
            }
            XCTAssertEqual(value.bitPattern, expectedBits, json)
        }
    }

    func testValueCodecKeepsUnicodeScalarsAndCanonicalDuplicateKeySemantics() throws {
        let data = Data(#"{"é":1,"e\u0301":2,"escaped":"\u4e2d\u6587\ud83d\udeb2","decomposed":"e\u0301","nul":"\u0000"}"#.utf8)
        let decoded = try Value.decode(data)
        XCTAssertEqual(decoded.object.count, 4)
        XCTAssertEqual(decoded["é"], 1)
        XCTAssertEqual(decoded["e\u{0301}"], 1)
        XCTAssertEqual(decoded["escaped"], "中文🚲")
        XCTAssertEqual(Array(decoded["decomposed"].text.utf8), [0x65, 0xcc, 0x81])
        XCTAssertEqual(Array(decoded["nul"].text.utf8), [0])
    }

    func testValueCodecPreservesParserAcceptanceBoundaries() throws {
        let accepted: [(String, Value)] = [("[1,]", [1]), (#"{"a":1,}"#, ["a":1])]
        for (json, expected) in accepted { XCTAssertEqual(try Value.decode(Data(json.utf8)), expected) }
        let utf8BOM = Data([0xef, 0xbb, 0xbf]) + Data(#"{"a":true}"#.utf8)
        XCTAssertEqual(try Value.decode(utf8BOM), ["a":true])
        let utf16BOM = Data([0xff, 0xfe]) + (try XCTUnwrap(#"{"中文":true}"#.data(using: .utf16LittleEndian)))
        XCTAssertEqual(try Value.decode(utf16BOM), ["中文":true])
        for json in ["", "NaN", "Infinity", "-Infinity", "+1", "01", "1.", "1e309", "-1e309", "1e-324",
                     "//comment\n1", "true false", #""\ud800""#, #""\udc00""#] {
            XCTAssertThrowsError(try Value.decode(Data(json.utf8)), json)
        }
        XCTAssertThrowsError(try Value.decode(Data([0x22, 0xff, 0x22])))
    }

    func testEventMetricsReusedIndexRespectsExactCutoffAndUnindexedResults() throws {
        let context = try XCTUnwrap(JSContext())
        let rules = try XCTUnwrap(Bundle.module.url(forResource: "gearhouse-rules", withExtension: "js"))
        context.evaluateScript(try String(contentsOf: rules, encoding: .utf8))
        XCTAssertNil(context.exception)
        let output = context.evaluateScript(#"""
        (() => {
            const {buildActivityIndex,calculateEventMetrics}=require('public/snapshot.js');
            const state={gears:[{id:'chain'},{id:'other'}],activities:[
                {id:'early',at:'2024-01-02T10:00:00',distance:100,snapshot:[{id:'chain'}]},
                {id:'late',at:'2024-01-02T12:00:00',distance:200,snapshot:[{id:'chain'}]},
                {id:'tomorrow',at:'2024-01-03T00:00:00',distance:400,snapshot:[{id:'chain'}]},
                {id:'unrelated-missing',at:'2024-01-02T08:00:00',distance:null,snapshot:[{id:'other'}]}
            ]};
            const event={gearId:'chain',occurredDate:'2024-01-01',occurredTime:'12:00'};
            const otherEvent={gearId:'chain',occurredDate:'2024-01-02',occurredTime:'11:00'};
            const before=JSON.stringify(state);
            const index=buildActivityIndex(state);
            const noon=calculateEventMetrics(state,event,'2024-01-02T12:00:00',index);
            const sameNoon=calculateEventMetrics(state,otherEvent,'2024-01-02T12:00:00',index);
            const earlier=calculateEventMetrics(state,event,'2024-01-02T10:00:00',index);
            const noonAgain=calculateEventMetrics(state,event,'2024-01-02T12:00:00',index);
            const tomorrow=calculateEventMetrics(state,event,'2024-01-03T00:00:00',index);
            const unindexed=calculateEventMetrics(state,event,'2024-01-02T12:00:00');
            return JSON.stringify({noon,sameNoon,earlier,noonAgain,tomorrow,unindexed,stateUnchanged:before===JSON.stringify(state)});
        })()
        """#)?.toString()
        XCTAssertNil(context.exception)
        let metrics = try Value.decode(Data(try XCTUnwrap(output).utf8))
        XCTAssertEqual(metrics["noon"]["distance"], 300)
        XCTAssertEqual(metrics["sameNoon"]["distance"], 200)
        XCTAssertEqual(metrics["sameNoon"]["total"], 100)
        XCTAssertEqual(metrics["earlier"]["distance"], 100)
        XCTAssertEqual(metrics["noonAgain"], metrics["noon"])
        XCTAssertEqual(metrics["tomorrow"]["distance"], 700)
        XCTAssertEqual(metrics["unindexed"], metrics["noon"])
        XCTAssertTrue(metrics["sameNoon"]["limited"].flag)
        XCTAssertTrue(metrics["stateUnchanged"].flag)
    }

    func testEventMetricsKeepFirstDuplicateDistanceDecisionForEveryRecord() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"chain", "type":"Chain"], ["id":"other", "type":"Chain"]]
        state["gearEvents"] = [["id":"before", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-01", "occurredTime":"12:00"],
                               ["id":"mid", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-02", "occurredTime":"12:00"],
                               ["id":"all-day", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-02"],
                               ["id":"other-record", "gearId":"other", "kind":"maintenance", "occurredDate":"2024-01-01"]]
        state["activities"] = [
            ["id":"first-true", "at":"2024-01-02T11:00:00", "distance":100,
             "snapshot":[["id":"chain", "distanceIncluded":true], ["id":"chain", "distanceIncluded":false]]],
            ["id":"first-false", "at":"2024-01-02T13:00:00", "distance":900,
             "snapshot":[["id":"chain", "distanceIncluded":false], ["id":"chain", "distanceIncluded":true]]],
            ["id":"normal", "at":"2024-01-02T13:00:00", "distance":200,
             "snapshot":[["id":"chain"], ["id":"other", "distanceIncluded":false]]],
            ["id":"unavailable", "at":"2024-01-03T12:00:00", "distance":400, "unavailable":true, "snapshot":[["id":"chain"]]]
        ]
        let metrics = try engine.execute(state: state, action: "view")["result"]["eventStatistics"]
        XCTAssertEqual(metrics["before"]["distance"], 300)
        XCTAssertEqual(metrics["mid"]["distance"], 200)
        XCTAssertEqual(metrics["mid"]["total"], 100)
        XCTAssertEqual(metrics["all-day"]["distance"], 0)
        XCTAssertEqual(metrics["other-record"]["distance"], 0)
        XCTAssertTrue(metrics["before"]["limited"].flag)
        XCTAssertEqual(try engine.execute(state: state, action: "view", input: ["date":"2024-01-02"])["result"]["eventStatistics"]["mid"]["distance"], 200)
    }

    func testGearStateIndexKeepsFirstGearStableTiesAndUnindexedResults() throws {
        let context = try XCTUnwrap(JSContext())
        let rules = try XCTUnwrap(Bundle.module.url(forResource: "gearhouse-rules", withExtension: "js"))
        context.evaluateScript(try String(contentsOf: rules, encoding: .utf8))
        XCTAssertNil(context.exception)
        let output = context.evaluateScript(#"""
        (() => {
            const api=require('lib/gear-state.mjs');
            const state={gears:[{id:'duplicate',retired:false},{id:'duplicate',retired:true},
                {id:'child'},{id:'legacy',retired:true},{id:'dated',retired:true,retiredAt:'2024-02-01T00:00:00'},
                {id:'stocked'},{id:'cycle-a'},{id:'cycle-b'}],events:[
                {gearId:'child',parentId:'legacy',at:'2024-01-01T00:00:00'},
                {gearId:'child',parentId:'dated',at:'2024-01-01T00:00:00'},
                {gearId:'cycle-a',parentId:'cycle-b',at:'2020-01-01T00:00:00'},
                {gearId:'cycle-b',parentId:'cycle-a',at:'2020-01-01T00:00:00'}],gearStates:[
                {gearId:'stocked',status:'active',at:'2024-01-01T00:00:00'},
                {gearId:'stocked',status:'stock',at:'2024-01-01T00:00:00'},
                {gearId:'stocked',status:'active',at:'2024-03-01T00:00:00'}]};
            const before=JSON.stringify(state),index=api.buildGearStateIndex(state);
            let equal=true;
            for(const at of ['2024-03-01T00:00:00','2023-12-31T23:59:59','2024-01-01T00:00:00','2024-02-01T00:00:00']){
                for(const id of ['duplicate','child','legacy','dated','stocked','cycle-a','missing'])for(const include of [true,false]){
                    equal&&=api.readOwnGearStatus(state,id,at,include,index)===api.readOwnGearStatus(state,id,at,include);
                    equal&&=api.readGearStatus(state,id,at,include,index)===api.readGearStatus(state,id,at,include);
                }
                equal&&=JSON.stringify(api.readGearStatuses(state,at,index))===JSON.stringify(api.readGearStatuses(state,at));
                const activity={main:null,extras:['stocked','child','stocked'],at};
                equal&&=api.readInventoryConflict(state,activity,index)===api.readInventoryConflict(state,activity);
            }
            return JSON.stringify({equal,stateUnchanged:before===JSON.stringify(state),
                duplicate:api.readOwnGearStatus(state,'duplicate','2024-01-01T00:00:00',true,index),
                tiedParent:api.readGearStatus(state,'child','2024-01-01T00:00:00',true,index),
                retiredAncestor:api.readGearStatus(state,'child','2024-02-01T00:00:00',false,index),
                legacyExcluded:api.readGearStatus(state,'legacy','2024-01-01T00:00:00',false,index),
                legacyIncluded:api.readGearStatus(state,'legacy','2024-01-01T00:00:00',true,index),
                tiedState:api.readOwnGearStatus(state,'stocked','2024-01-01T00:00:00',true,index),
                cycle:api.readGearStatus(state,'cycle-a','2024-01-01T00:00:00',true,index)});
        })()
        """#)?.toString()
        XCTAssertNil(context.exception)
        let result = try Value.decode(Data(try XCTUnwrap(output).utf8))
        XCTAssertTrue(result["equal"].flag)
        XCTAssertTrue(result["stateUnchanged"].flag)
        XCTAssertEqual(result["duplicate"], "active")
        XCTAssertEqual(result["tiedParent"], "active")
        XCTAssertEqual(result["retiredAncestor"], "retired")
        XCTAssertEqual(result["legacyExcluded"], "active")
        XCTAssertEqual(result["legacyIncluded"], "retired")
        XCTAssertEqual(result["tiedState"], "stock")
        XCTAssertEqual(result["cycle"], "active")
    }

    func testGearStateViewRebuildsIndexAcrossHistoricalAndChangedStates() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"root", "type":"Bike", "createdAt":"2020-01-01T00:00:00"],
                          ["id":"child", "type":"Chain", "createdAt":"2020-01-01T00:00:00"],
                          ["id":"later", "type":"Bike", "purchased":"2024-06-01", "retired":true, "retiredAt":"2024-06-01T00:00:00"]]
        state["events"] = [["id":"mount", "gearId":"child", "parentId":"later", "at":"2024-01-01T00:00:00", "allDay":true]]
        state["gearStates"] = [["id":"stock", "gearId":"root", "status":"stock", "at":"2024-01-01T00:00:00"],
                               ["id":"activate", "gearId":"root", "status":"active", "at":"2024-08-01T00:00:00"]]
        state["activities"] = [["id":"conflict", "at":"2024-02-01T00:00:00", "main":.null, "extras":["root","root"], "snapshot":[["id":"root"]]],
                               ["id":"restored", "at":"2024-09-01T00:00:00", "main":"root", "extras":[], "snapshot":[["id":"root"]]],
                               ["id":"old-snapshot", "at":"2024-02-01T00:00:00", "main":.null, "extras":[], "snapshot":[["id":"root"]]],
                               ["id":"deleted", "at":"2024-02-01T00:00:00", "main":"root", "deleted":true, "extras":[], "snapshot":[["id":"root"]]]]
        let current = try engine.execute(state: state, action: "view")["result"]
        XCTAssertEqual(current["gearStatuses"]["root"], "active")
        XCTAssertEqual(current["gearStatuses"]["child"], "retired")
        XCTAssertEqual(current["inventoryConflicts"], ["conflict"])
        XCTAssertEqual(current["activities"], state["activities"])
        let historical = try engine.execute(state: state, action: "view", input: ["date":"2024-02-01"])["result"]
        XCTAssertEqual(historical["gearStatuses"]["root"], "stock")
        XCTAssertEqual(historical["gearStatuses"]["child"], "active")
        XCTAssertTrue(historical["gearStatuses"]["later"].isNull)
        XCTAssertTrue(historical["events"].array[0]["parentId"].isNull)
        XCTAssertEqual(try engine.execute(state: state, action: "view")["result"]["gearStatuses"], current["gearStatuses"])
        state["gearStates"] = []
        let changed = try engine.execute(state: state, action: "view")["result"]
        XCTAssertTrue(changed["inventoryConflicts"].array.isEmpty)
        XCTAssertEqual(changed["gearStatuses"]["root"], "active")
        XCTAssertEqual(changed["activities"], state["activities"])
    }

    func testEventMetricsPreserveFloatingPointSourceOrderAcrossViews() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"chain", "type":"Chain", "createdAt":"2020-01-01T00:00:00",
                           "importedTotals":["distance":.number(0.3), "through":"2024-01-01T00:00:00"]]]
        state["gearEvents"] = [["id":"first", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-01", "occurredTime":"12:00"],
                               ["id":"second", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-02", "occurredTime":"12:00"],
                               ["id":"later", "gearId":"chain", "kind":"maintenance", "occurredDate":"2024-01-04", "occurredTime":"12:00"]]
        let distances = [1e16, 1.0, 1.0, 0.1]
        let activities: [Value] = distances.enumerated().map { index, distance in
            ["id":.string("a\(index)"), "at":"2024-01-03T12:00:00", "distance":.number(distance), "snapshot":[["id":"chain"]]]
        }
        state["activities"] = .array(activities)
        let forward = try engine.execute(state: state, action: "view")["result"]["eventStatistics"]
        XCTAssertEqual(forward["first"]["distance"].double.bitPattern, Double(1e16).bitPattern)
        XCTAssertEqual(forward["second"]["distance"], forward["first"]["distance"])
        XCTAssertEqual(forward["later"]["total"].double.bitPattern, Double(1e16).bitPattern)
        state["activities"] = .array(activities.reversed())
        let reversed = try engine.execute(state: state, action: "view")["result"]["eventStatistics"]
        let expected = Double(10_000_000_000_000_002 as Int)
        XCTAssertEqual(reversed["first"]["distance"].double.bitPattern, expected.bitPattern)
        XCTAssertEqual(reversed["second"]["distance"], reversed["first"]["distance"])
        XCTAssertEqual(reversed["later"]["total"].double.bitPattern, expected.bitPattern)
        let historical = try engine.execute(state: state, action: "view", input: ["date":"2024-01-03"])["result"]["eventStatistics"]
        XCTAssertEqual(historical["first"]["distance"].double.bitPattern, expected.bitPattern)
        state["activities"] = .array(activities)
        XCTAssertEqual(try engine.execute(state: state, action: "view")["result"]["eventStatistics"]["first"]["distance"], forward["first"]["distance"])
    }

}
