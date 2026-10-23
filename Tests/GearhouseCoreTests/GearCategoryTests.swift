import XCTest
@testable import GearhouseCore

final class GearCategoryTests: XCTestCase {
    private final class Session {
        let engine = try! NativeDomain()
        var state: Value
        init(_ raw: Value = .null) throws { state = try engine.execute(state: raw, action: "initialize")["state"] }
        @discardableResult func run(_ action: String, _ input: Value = [:]) throws -> Value {
            let result = try engine.execute(state: state, action: action, input: input)
            if !result["state"].isNull { state = result["state"] }
            return result["result"]
        }
        func category(_ id: String) -> Value { state["gearCategories"].array.first { $0.id == id }! }
        func distance(_ id: String) throws -> Double { try run("view")["statistics"][id]["distance"].double }
        func gear(_ id: String) -> Value { state["gears"].array.first { $0.id == id }! }
        func activity(_ id: String) -> Value { state["activities"].array.first { $0.id == id }! }
        func saveCategory(_ id: String, indoor: Bool) throws {
            var input = category(id); input["indoorDistance"] = .bool(indoor)
            try run("category-save", input)
        }
        func sync(_ rows: Value, historical: Bool = false) throws {
            try run("sync-rows", ["rows": rows, "historical": .bool(historical), "from":"2026-10-01", "to":"2026-10-10"])
        }
    }
    private func ride(_ id: String, _ type: String = "Ride", distance: Int = 10000, trainer: Bool = false) -> Value {
        ["id": .string(id), "name": .string(id), "type": .string(type), "start_date_local":"2026-10-02T10:00:00", "distance": .number(Double(distance)), "moving_time": 3600, "trainer": .bool(trainer), "gear":["id":"b"]]
    }
    private func equipped() throws -> Session {
        let session = try Session()
        session.state["gears"] = [
            ["id":"bike", "name":"Tarmac", "type":"Bike", "remoteId":"b"],
            ["id":"chain", "name":"KMC", "type":"Chain"],
            ["id":"cassette", "name":"Cassette", "type":"Cassette"],
            ["id":"rings", "name":"Rings", "type":"Chainrings"],
            ["id":"drivetrain", "name":"Drivetrain", "type":"Drivetrain"],
            ["id":"wheel", "name":"CL II", "type":"Wheelset"],
            ["id":"tyre", "name":"IRC", "type":"Tyre"],
            ["id":"pedals", "name":"Power pedals", "type":"PowerMeter"],
            ["id":"trainer", "name":"Trainer", "type":"Trainer"]
        ]
        session.state["events"] = .array(["chain","cassette","rings","drivetrain","wheel","tyre","pedals"].map {
            ["id": .string("e-" + $0), "gearId": .string($0), "parentId":"bike", "at":"2024-01-01T00:00:00"]
        })
        _ = try session.run("initialize")
        return session
    }

    func testMigrationDefaultsAndHistoricalDecisionsAreStable() throws {
        let raw: Value = ["gears":[["id":"chain", "name":"Chain", "type":"Chain"], ["id":"unknown", "name":"Unknown", "type":"ImportedPart"]], "events":[], "activities":[["id":"old", "at":"2026-10-02T10:00:00", "distance":30000, "snapshot":[["id":"chain", "distanceIncluded":false]]]], "gearEvents":[], "photos":[]]
        let session = try Session(raw)
        let builtin = session.state["gearCategories"].array.filter { $0["builtin"].flag }
        XCTAssertEqual(builtin.count, 23)
        XCTAssertEqual(Set(builtin.filter { $0["indoorDistance"].flag }.map(\.id)), Set(["Trainer","Chain","Cassette","Chainrings","Crankset","Spider","FrontDerailleur","RearDerailleur"]))
        XCTAssertEqual(session.category("BrakePads")["name"], "来令片")
        for (id, name) in [("BrakeRotor","碟片"),("Saddle","坐垫"),("Seatpost","坐杆"),("FrontDerailleur","前变速器"),("RearDerailleur","后变速器"),("Crankset","曲柄"),("Spider","盘爪")] {
            XCTAssertEqual(session.category(id)["name"].text, name)
        }
        XCTAssertEqual(session.state["activities"], raw["activities"])
        XCTAssertEqual(session.gear("chain")["categoryId"].text, "Chain")
        let unknownID = session.gear("unknown")["categoryId"].text
        XCTAssertEqual(session.category(unknownID)["name"].text, "ImportedPart")
        XCTAssertFalse(session.category(unknownID)["indoorDistance"].flag)
        try session.saveCategory("Chain", indoor: false)
        let backup = try Value.decode(session.state.jsonData())
        let restored = try Session(backup)
        XCTAssertEqual(restored.state["gearCategories"], session.state["gearCategories"])
        XCTAssertEqual(restored.state["activities"], raw["activities"])
        XCTAssertEqual(restored.gear("unknown")["categoryId"].text, unknownID)
        XCTAssertFalse(restored.category("Chain")["indoorDistance"].flag)
    }

    func testLegacyWheelCategoriesMergeWithoutChangingEquipmentHistoryOrReplacementIdentity() throws {
        let session = try Session()
        let raw = session.state
        var categories = raw["gearCategories"].array
        categories.append(["id":"Wheel", "name":"车轮", "baseType":"Wheel", "builtin":true, "indoorDistance":false])
        categories.append(["id":"custom-wheel", "name":"训练轮组", "baseType":"Wheel", "builtin":false, "indoorDistance":true])
        categories.append(["id":"Drivetrain", "name":"传动系统", "baseType":"Drivetrain", "builtin":true, "indoorDistance":true])
        session.state["gearCategories"] = .array(categories)
        session.state["gears"] = [["id":"bike", "name":"Bike", "type":"Bike", "categoryId":"Bike"],
                                  ["id":"single", "name":"CLX III", "type":"Wheel", "categoryId":"Wheel"],
                                  ["id":"pair", "name":"CL II", "type":"Wheelset", "categoryId":"Wheelset"],
                                  ["id":"custom", "name":"Trainer wheel", "type":"Wheel", "categoryId":"custom-wheel"]]
        session.state["events"] = [["id":"mount", "gearId":"single", "parentId":"bike", "at":"2024-01-01T00:00:00", "allDay":true]]
        session.state["gearStates"] = [["id":"stock", "gearId":"pair", "status":"stock", "at":"2024-01-01T00:00:00"]]
        session.state["activities"] = [["id":"ride", "at":"2024-06-01T10:00:00", "main":"bike", "distance":10000, "seconds":1000, "snapshot":[["id":"bike", "parentId":.null],["id":"single", "parentId":"bike"]]]]
        let events = session.state["events"], activities = session.state["activities"]
        try session.run("initialize")
        XCTAssertEqual(session.gear("single")["categoryId"], "Wheelset")
        XCTAssertEqual(session.gear("single")["type"], "Wheelset")
        XCTAssertEqual(session.gear("custom")["categoryId"], "custom-wheel")
        XCTAssertEqual(session.category("custom-wheel")["baseType"], "Wheelset")
        XCTAssertTrue(session.category("custom-wheel")["indoorDistance"].flag)
        XCTAssertFalse(session.state["gearCategories"].array.contains { ["Wheel","Drivetrain"].contains($0.id) })
        XCTAssertEqual(session.state["events"], events)
        XCTAssertEqual(session.state["activities"], activities)
        XCTAssertEqual(try session.distance("single"), 10000)
        let preview = try session.run("inventory-preview", ["kind":"replace", "gearId":"single", "replacementId":"pair", "at":"2024-07-01"])
        XCTAssertEqual(preview["replacementId"], "pair")
        let restored = try Session(try Value.decode(session.state.jsonData()))
        XCTAssertEqual(restored.state["gears"], session.state["gears"])
        XCTAssertEqual(restored.state["gearCategories"], session.state["gearCategories"])
    }

    func testLegacyDrivetrainAndCustomBrakePadCategoryKeepSettingsAndIdentity() throws {
        let session = try Session(["gears":[["id":"old", "name":"旧传动套件", "type":"Drivetrain"]], "events":[], "activities":[]])
        XCTAssertEqual(session.gear("old")["categoryId"], "Drivetrain")
        XCTAssertEqual(session.gear("old")["type"], "Equipment")
        XCTAssertFalse(session.category("Drivetrain")["builtin"].flag)
        XCTAssertTrue(session.category("Drivetrain")["indoorDistance"].flag)
        var categories = session.state["gearCategories"].array.filter { $0.id != "BrakePads" }
        categories.append(["id":"custom-pads", "name":"来令片", "baseType":"Equipment", "builtin":false, "indoorDistance":false])
        session.state["gearCategories"] = .array(categories)
        var gears = session.state["gears"].array
        gears.append(["id":"pads", "name":"前刹来令片", "type":"Equipment", "categoryId":"custom-pads"])
        session.state["gears"] = .array(gears)
        try session.run("initialize")
        XCTAssertEqual(session.state["gearCategories"].array.filter { $0["name"] == "来令片" }.count, 1)
        XCTAssertEqual(session.gear("pads")["categoryId"], "custom-pads")
        XCTAssertNoThrow(try Session(session.state))
        let fresh = try Session()
        let pads = try fresh.run("gear", ["name":"来令片", "categoryId":"BrakePads", "placement":"stock"])
        XCTAssertEqual(pads["type"], "BrakePads")
        XCTAssertFalse(fresh.category("BrakePads")["indoorDistance"].flag)
    }

    func testNewActivitiesCountDistanceIndependentlyForEveryGearAndEverySummary() throws {
        let session = try equipped()
        try session.sync([ride("outdoor"), ride("virtual", "VirtualRide", distance: 30000), ride("indoor", distance: 20000, trainer: true)])
        for id in ["chain","cassette","rings","drivetrain"] { XCTAssertEqual(try session.distance(id), 60000) }
        for id in ["bike","wheel","tyre","pedals"] { XCTAssertEqual(try session.distance(id), 10000) }
        XCTAssertEqual(try session.distance("trainer"), 0) // Not used by these activity assignments.
        _ = try session.run("assignment", ["id":"virtual", "assignment":["main":"bike", "extras":["trainer"], "excluded":[], "rebuild":true]])
        XCTAssertEqual(try session.distance("trainer"), 30000)
        let view = try session.run("view")
        XCTAssertEqual(view["statistics"]["wheel"]["count"].integer, 3)
        XCTAssertEqual(view["statistics"]["wheel"]["seconds"].double, 10800)
        XCTAssertEqual(try session.run("usage", ["id":"chain", "from":"2026-10-01", "to":"2026-10-03"])["summary"]["distance"].double, 60000)
        XCTAssertEqual(try session.run("usage", ["id":"wheel"])["summary"]["distance"].double, 10000)
        let historical = try session.run("view", ["date":"2026-10-03"])
        XCTAssertEqual(historical["statistics"]["chain"]["distance"].double, 60000)
        XCTAssertEqual(historical["statistics"]["wheel"]["distance"].double, 10000)
        let event = try session.run("event-save", ["requestId": .string(UUID().uuidString), "event":["gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-01"]])
        XCTAssertEqual(try session.run("view")["eventStatistics"][event.id]["distance"].double, 60000)
        var reminder = GearReminder(gearID: "chain")
        reminder.title = "Wax"; reminder.kilometers = 50
        reminder.startedAt = GearReminderEngine.parse("2026-10-01T00:00:00")!
        let now = GearReminderEngine.parse("2026-10-03T00:00:00")!
        let occurrence = GearReminderEngine.evaluate(reminder, state: session.state, total: 60000, now: now)
        XCTAssertEqual(occurrence.distance, 60000); XCTAssertTrue(occurrence.due)
        reminder.gearID = "wheel"
        XCTAssertEqual(GearReminderEngine.evaluate(reminder, state: session.state, total: 10000, now: now).distance, 10000)
    }

    func testTrainerAssignmentDetectsIndoorRideEvenWithoutRemoteFlag() throws {
        let session = try equipped()
        try session.sync([ride("ride")])
        _ = try session.run("assignment", ["id":"ride", "assignment":["main":"bike", "extras":["trainer"], "excluded":[], "rebuild":true]])
        XCTAssertEqual(try session.distance("bike"), 0)
        XCTAssertEqual(try session.distance("chain"), 10000)
        XCTAssertEqual(try session.distance("trainer"), 10000)
    }

    func testChangingCategoryAndResyncNeverRewritesSavedDistanceRules() throws {
        let session = try equipped()
        try session.sync([ride("old", "VirtualRide")])
        let saved = session.activity("old")["snapshot"]
        try session.saveCategory("Chain", indoor: false)
        XCTAssertEqual(session.activity("old")["snapshot"], saved)
        try session.sync([ride("old", "VirtualRide", distance: 12000)])
        XCTAssertEqual(session.activity("old")["snapshot"], saved)
        XCTAssertEqual(try session.distance("chain"), 12000) // Remote distance still refreshes.
        try session.sync([ride("new", "VirtualRide")])
        XCTAssertEqual(try session.distance("chain"), 12000)
        _ = try session.run("recompute", ["gearId":"chain", "from":"2026-10-01", "to":"2026-10-03"])
        XCTAssertEqual(try session.distance("chain"), 0)
        XCTAssertEqual(try session.distance("cassette"), 22000) // Single gear recalculation does not touch its siblings.
    }

    func testCategoryRecomputeTargetsAllMembersIncludingRetiredButNotOtherCategories() throws {
        let session = try equipped()
        var gears = session.state["gears"].array
        gears.append(["id":"spare-chain", "name":"Old Chain", "type":"Chain", "categoryId":"Chain", "retired":true])
        session.state["gears"] = .array(gears)
        var events = session.state["events"].array
        events.append(["id":"spare-install", "gearId":"spare-chain", "parentId":"bike", "at":"2024-01-01T00:00:00"])
        session.state["events"] = .array(events)
        try session.sync([ride("virtual", "VirtualRide")])
        var activity = session.activity("virtual")
        activity["snapshot"] = .array(activity["snapshot"].array.map { row in var row = row; row["distanceIncluded"] = false; return row })
        session.state["activities"] = [activity]
        let input: Value = ["categoryId":"Chain", "from":"2026-10-01", "to":"2026-10-03"]
        let preview = try session.run("recompute-preview", input)
        XCTAssertEqual(Set(preview["gearIds"].array.map(\.text)), Set(["chain","spare-chain"]))
        XCTAssertEqual(preview["totals"].array.count, 2)
        XCTAssertEqual(preview["changed"].integer, 1)
        XCTAssertEqual(try session.distance("chain"), 0) // Preview is read-only.
        _ = try session.run("recompute", input)
        XCTAssertEqual(try session.distance("chain"), 10000)
        XCTAssertEqual(try session.distance("spare-chain"), 10000)
        XCTAssertEqual(try session.distance("cassette"), 0)
        XCTAssertEqual(try session.distance("bike"), 0)
    }

    func testCustomCategoryUsesBaseTypeForPrimaryGearMappingAndTrainerBehavior() throws {
        let session = try equipped()
        session.state["remoteGears"] = [["id":"b", "name":"Tarmac", "type":"Bike"]]
        let road = try session.run("category-save", ["name":"公路车", "baseType":"Bike", "indoorDistance":false])
        let updated = try session.run("gear", ["id":"bike", "name":"Tarmac", "categoryId":road["id"], "remoteId":"b"])
        XCTAssertEqual(updated["type"].text, "Bike")
        let category = try session.run("category-save", ["name":"直驱骑行台", "baseType":"Trainer", "indoorDistance":true])
        let trainer = try session.run("gear", ["name":"Indoor", "categoryId":category["id"]])
        try session.sync([ride("ride")])
        XCTAssertEqual(session.activity("ride")["main"].text, "bike")
        _ = try session.run("assignment", ["id":"ride", "assignment":["main":"bike", "extras":.array([trainer["id"]]), "rebuild":true]])
        XCTAssertEqual(try session.distance(trainer.id), 10000)
        XCTAssertEqual(try session.distance("bike"), 0)
        XCTAssertThrowsError(try session.run("gear", ["name":"Wrong mapping", "categoryId":category["id"], "remoteId":"b"]))
    }

    func testCategoryDeletionRequiresReplacementIncludingRecycleBinAndPreservesHistory() throws {
        let session = try equipped()
        let category = try session.run("category-save", ["name":"室内链条", "baseType":"Chain", "indoorDistance":true])
        _ = try session.run("gear", ["id":"chain", "name":"KMC", "categoryId":category["id"]])
        try session.sync([ride("ride", "VirtualRide")])
        let activities = session.state["activities"]
        _ = try session.run("delete", ["id":"chain"])
        let input: Value = ["id":category["id"], "confirmed":true]
        XCTAssertThrowsError(try session.run("category-delete", input))
        XCTAssertThrowsError(try session.run("category-save", ["id":category["id"], "name":"室内链条", "baseType":"Cassette", "indoorDistance":true]))
        var wrong = input; wrong["replacementId"] = "Cassette"
        XCTAssertThrowsError(try session.run("category-delete", wrong))
        var confirmed = input; confirmed["replacementId"] = "Chain"
        XCTAssertEqual(try session.run("category-delete", confirmed)["moved"].integer, 1)
        XCTAssertEqual(session.gear("chain")["categoryId"].text, "Chain")
        XCTAssertFalse(session.gear("chain")["deletedAt"].isNull)
        XCTAssertEqual(session.state["activities"], activities)
        _ = try session.run("restore", ["id":"chain"])
        XCTAssertEqual(try session.distance("chain"), 10000)
    }

    func testCategoryRecomputeRequiresBaselineConfirmationAndPreservesManualAssignments() throws {
        let session = try equipped()
        try session.sync([ride("virtual", "VirtualRide")])
        var gears = session.state["gears"].array
        let index = gears.firstIndex { $0.id == "chain" }!
        gears[index]["importedTotals"] = ["distance":100000,"seconds":10000,"count":10,"through":"2026-10-05T00:00:00"]
        session.state["gears"] = .array(gears)
        let input: Value = ["categoryId":"Chain", "from":"2026-10-01", "to":"2026-10-03"]
        let preview = try session.run("recompute-preview", input)
        XCTAssertEqual(preview["totals"].array[0]["before"]["distance"].double, 100000)
        XCTAssertEqual(preview["totals"].array[0]["after"]["distance"].double, 10000)
        XCTAssertTrue(preview["totals"].array[0]["baselineDisabled"].flag)
        XCTAssertThrowsError(try session.run("recompute", input))
        XCTAssertEqual(try session.distance("chain"), 100000)
        var confirmed = input; confirmed["baselineConfirmed"] = true
        _ = try session.run("recompute", confirmed)
        XCTAssertEqual(try session.distance("chain"), 10000)
        XCTAssertEqual(session.gear("chain")["totalsMode"].text, "local")
        _ = try session.run("assignment", ["id":"virtual", "assignment":["main":"bike", "extras":["trainer"], "rebuild":true]])
        try session.saveCategory("Chain", indoor: false)
        XCTAssertEqual(try session.run("recompute-preview", input)["skipped"]["manual"].integer, 1)
        _ = try session.run("recompute", input)
        XCTAssertEqual(try session.distance("chain"), 10000)
        var recalculate = input; recalculate["manual"] = "recalculate"
        _ = try session.run("recompute", recalculate)
        XCTAssertEqual(try session.distance("chain"), 0)
        XCTAssertEqual(try session.distance("trainer"), 10000)
    }

    func testInvalidCategoriesFailWithoutMutatingData() throws {
        let session = try equipped()
        let before = session.state
        XCTAssertThrowsError(try session.run("category-save", ["name":"链条", "baseType":"Chain", "indoorDistance":true]))
        XCTAssertThrowsError(try session.run("category-save", ["name":"  ", "baseType":"Chain", "indoorDistance":true]))
        XCTAssertThrowsError(try session.run("category-save", ["name":"Custom", "baseType":"NotAType", "indoorDistance":true]))
        XCTAssertThrowsError(try session.run("category-save", ["name":"Custom", "baseType":"Chain", "indoorDistance":"true"]))
        XCTAssertThrowsError(try session.run("category-save", ["id":"Bike", "name":"Bike", "baseType":"Trainer", "indoorDistance":true]))
        XCTAssertThrowsError(try session.run("category-delete", ["id":"Chain", "confirmed":true]))
        XCTAssertThrowsError(try session.run("gear", ["name":"Missing", "categoryId":"missing"]))
        XCTAssertEqual(session.state, before)
        var invalid = before
        var gears = invalid["gears"].array
        gears[0]["categoryId"] = "missing"
        invalid["gears"] = .array(gears)
        XCTAssertThrowsError(try Session(invalid))
    }
}
