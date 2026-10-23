import XCTest
@testable import GearhouseCore

final class GearReminderTests: XCTestCase {
    func testCopiedRuleStartsFreshAndFollowsOnlyNewEquipmentsMaintenance() throws {
        let start = GearReminderEngine.parse("2026-10-14T12:00:00")!
        var source = GearReminder(gearID: "chain")
        source.title = "煮蜡"; source.anchor = .event; source.anchorID = "wax"; source.repeats = true
        source.completedCycle = "old"; source.snoozedCycle = "old"; source.snoozedUntil = start
        let copy = source.copyRule(to: "chain2", state: fixture(), now: start)
        XCTAssertNotEqual(source.id, copy.id)
        XCTAssertEqual(copy.gearID, "chain2")
        XCTAssertTrue(copy.anchorID.isEmpty)
        XCTAssertNil(copy.completedCycle); XCTAssertNil(copy.snoozedUntil)
        XCTAssertEqual(copy.eventKind, "hotWax")
        XCTAssertNoThrow(try copy.validate())
        var state = fixture(); state["gears"] = .array(state["gears"].array + [["id":"chain2"]])
        var result = GearReminderEngine.evaluate(copy, state: state, total: 0, now: now)
        XCTAssertNil(result.issue); XCTAssertEqual(result.distance, 0)
        state["gearEvents"] = .array(state["gearEvents"].array + [["id":"wax2", "gearId":"chain2", "kind":"hotWax", "occurredDate":"2026-10-15"]])
        state["activities"] = .array(state["activities"].array + [["id":"new", "at":"2026-10-16T08:00:00", "distance":25000, "snapshot":[["id":"chain2"]]]])
        result = GearReminderEngine.evaluate(copy, state: state, total: 0, now: now)
        XCTAssertEqual(result.distance, 25000)
        XCTAssertTrue(result.cycle.contains("wax2")); XCTAssertFalse(result.cycle.contains(":wax:"))
    }
    let now = GearReminderEngine.parse("2026-10-16T18:00:00")!
    func fixture() -> Value {
        ["gears": [["id":"chain", "name":"KMC Chain"]], "events": [["id":"install", "gearId":"chain", "parentId":"bike", "at":"2026-10-01T12:00:00"]], "gearEvents": [["id":"wax", "gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-10", "occurredTime":"12:00"]], "activities": [
            ["id":"a", "at":"2026-10-11T08:00:00", "distance":200000, "snapshot":[["id":"chain", "parentId":"bike"]]],
            ["id":"b", "at":"2026-10-12T08:00:00", "distance":100000, "snapshot":[["id":"chain", "parentId":"other-bike"]]],
            ["id":"virtual", "at":"2026-10-13T08:00:00", "distance":900000, "snapshot":[["id":"chain", "distanceIncluded":false]]]
        ]]
    }
    func rule() -> GearReminder { var r = GearReminder(gearID: "chain"); r.title = "煮蜡"; r.startedAt = GearReminderEngine.parse("2026-10-10T12:00:00")!; return r }
    func evaluate(_ r: GearReminder, _ state: Value? = nil, total: Double = 0) -> ReminderOccurrence { GearReminderEngine.evaluate(r, state: state ?? fixture(), total: total, now: now) }
    func testSharedActivityIndexMatchesEvaluationAtTimeAndSnapshotBoundaries() {
        var state = fixture()
        state["activities"] = .array(state["activities"].array + [
            ["id":"future", "at":"2026-12-01T08:00:00", "distance":999999, "snapshot":[["id":"chain"]]],
            ["id":"summary", "summary":true, "at":"2026-10-13T08:00:00", "distance":999999, "snapshot":[["id":"chain"]]],
            ["id":"duplicate-membership", "at":"2026-10-13T08:00:00", "distance":999999, "snapshot":[["id":"chain", "distanceIncluded":false], ["id":"chain"]]],
            ["id":"a", "at":"2026-10-13T08:00:00", "distance":999999, "snapshot":[["id":"chain"]]]
        ])
        let index = GearReminderActivityIndex(state["activities"].array)
        for offset in [0.0, 3600, 86400] {
            for mode in GearReminder.Mode.allCases {
                var r = rule(); r.mode = mode
                let at = now.addingTimeInterval(offset)
                XCTAssertEqual(GearReminderEngine.evaluate(r, state: state, total: 300000, now: at, activities: index),
                               GearReminderEngine.evaluate(r, state: state, total: 300000, now: at))
            }
        }
    }
    func testSavedSnapshotsSurviveMovesAndExcludeTrainer() {
        let result = evaluate(rule()); XCTAssertTrue(result.due); XCTAssertEqual(result.distance, 300000)
    }
    func testDeletionAndReassignmentRetractDue() {
        var state = fixture(); var activities = state["activities"].array
        activities[0]["deleted"] = true; state["activities"] = .array(activities)
        XCTAssertFalse(evaluate(rule(), state).due)
        activities[0]["deleted"] = false; activities[0]["snapshot"] = []; state["activities"] = .array(activities)
        XCTAssertEqual(evaluate(rule(), state).distance, 100000)
    }
    func testNewRuleStartsNowWithoutIncludingHistoricalMileage() {
        var r = rule(); r.startedAt = now
        XCTAssertEqual(evaluate(r, total: 900000).distance, 0)
        r.mode = .total; XCTAssertTrue(evaluate(r, total: 900000).due)
    }
    func testMatchingEventAdvancesCycleButOtherEventDoesNot() {
        var r = rule(); r.anchor = .event; r.anchorID = "wax"; r.repeats = true
        let old = evaluate(r); XCTAssertTrue(old.due)
        var state = fixture(); var events = state["gearEvents"].array
        events.append(["id":"drip", "gearId":"chain", "kind":"dripWax", "occurredDate":"2026-10-14", "occurredTime":"12:00"])
        state["gearEvents"] = .array(events); XCTAssertEqual(evaluate(r, state).cycle, old.cycle)
        events.append(["id":"wax2", "gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-15", "occurredTime":"12:00"])
        state["gearEvents"] = .array(events); XCTAssertFalse(evaluate(r, state).due); XCTAssertNotEqual(evaluate(r, state).cycle, old.cycle)
    }
    func testEditedOrMissingAnchor() {
        var r = rule(); r.anchor = .event; r.anchorID = "wax"
        var state = fixture(); state["gearEvents"] = [["id":"wax", "gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-15", "occurredTime":"12:00"]]
        XCTAssertFalse(evaluate(r, state).due)
        state["gearEvents"] = []; XCTAssertNotNil(evaluate(r, state).issue)
    }
    func testDateOnlyEventStartsNextDay() {
        var r = rule(); r.anchor = .event; r.anchorID = "wax"
        var state = fixture(); state["gearEvents"] = [["id":"wax", "gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-11"]]
        XCTAssertEqual(evaluate(r, state).distance, 100000)
    }
    func testDateOnlyMaintenanceResetsTodayAndUsesActualDayForDeadline() {
        var r = rule(); r.anchor = .event; r.anchorID = "wax"; r.repeats = true; r.days = 1
        var state = fixture(); state["gearEvents"] = .array(state["gearEvents"].array + [["id":"today-wax", "gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-16"]])
        let next = evaluate(r, state)
        XCTAssertFalse(next.due)
        XCTAssertEqual(next.distance, 0)
        XCTAssertEqual(next.fireDate, GearReminderEngine.parse("2026-10-17T09:00:00"))
        XCTAssertTrue(next.cycle.contains("today-wax"))
    }
    func testInstallationAnchorAndDayOrDistance() {
        var r = rule(); r.anchor = .installation; r.anchorID = "install"; r.kilometers = 500; r.days = 10
        XCTAssertTrue(evaluate(r).due)
        r.days = 30; XCTAssertFalse(evaluate(r).due)
    }
    func testRetiredDeletedPauseHiddenDoesNot() {
        var s = fixture(); s["gears"] = [["id":"chain", "hidden":true]]; XCTAssertTrue(evaluate(rule(), s).due)
        s["gears"] = [["id":"chain", "retired":true]]; XCTAssertNotNil(evaluate(rule(), s).issue)
        s["gears"] = [["id":"chain", "deletedAt":"2026-10-16"]]; XCTAssertNil(evaluate(rule(), s).fireDate)
    }
    func testSnoozeDoesNotCompleteOrResetCycle() {
        var r = rule(); let original = evaluate(r); r.snoozedCycle = original.cycle; r.snoozedUntil = now.addingTimeInterval(86400)
        XCTAssertTrue(evaluate(r).due); XCTAssertEqual(evaluate(r).cycle, original.cycle); XCTAssertEqual(evaluate(r).fireDate, r.snoozedUntil)
    }
    func testCompletionAndRepeatUsage() {
        var r = rule(); let complete = GearReminderEngine.complete(r, occurrence: evaluate(r), total: 300000, now: now)
        XCTAssertFalse(complete.enabled)
        r.repeats = true; let repeated = GearReminderEngine.complete(r, occurrence: evaluate(r), total: 300000, now: now)
        XCTAssertEqual(evaluate(repeated).distance, 0); XCTAssertTrue(repeated.enabled)
    }
    func testFixedDateCompletionDoesNotDriftSchedule() {
        var r = rule(); r.mode = .date; r.date = GearReminderEngine.parse("2026-10-10T09:00:00")!; r.days = 3; r.repeats = true
        let current = evaluate(r); XCTAssertEqual(current.fireDate, GearReminderEngine.parse("2026-10-16T09:00:00"))
        let next = GearReminderEngine.complete(r, occurrence: current, total: 0, now: now)
        XCTAssertEqual(evaluate(next).fireDate, GearReminderEngine.parse("2026-10-19T09:00:00"))
    }
    func testRepeatedLifetimeDistancePreservesInterval() {
        var r = rule(); r.mode = .total; r.repeats = true
        r = GearReminderEngine.complete(r, occurrence: evaluate(r, total: 310000), total: 310000, now: now)
        XCTAssertEqual(r.kilometers, 610)
        r = GearReminderEngine.complete(r, occurrence: evaluate(r, total: 620000), total: 620000, now: now)
        XCTAssertEqual(r.kilometers, 920)
    }
    func testRoundTripAndValidation() throws {
        let r = rule(); XCTAssertEqual(try JSONDecoder().decode(GearReminder.self, from: JSONEncoder().encode(r)), r)
        var invalid = r; invalid.kilometers = -1; XCTAssertThrowsError(try invalid.validate())
        invalid = r; invalid.anchor = .event; XCTAssertThrowsError(try invalid.validate())
    }
}
