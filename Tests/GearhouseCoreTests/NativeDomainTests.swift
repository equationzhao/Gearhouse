import XCTest
@testable import GearhouseCore

final class NativeDomainTests: XCTestCase {
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

}
