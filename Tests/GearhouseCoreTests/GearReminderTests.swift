import XCTest
@testable import GearhouseCore

final class GearReminderTests: XCTestCase {
    func testPreciseInstallationReminderUsesInstantsAndFlagsUnknownTime() {
        var reminder = GearReminder(gearID: "wheel")
        reminder.title = "Check"; reminder.mode = .usage; reminder.kilometers = 10
        reminder.anchor = .installation; reminder.anchorID = "mount"
        var state: Value = ["gears":[["id":"wheel"]], "events":[["id":"mount", "gearId":"wheel", "at":"1991-09-15T01:30:00", "instant":"1991-09-14T17:30:00.000Z", "allDay":false]],
            "activities":[["id":"before", "at":"1991-09-15T01:45:00", "startInstant":"1991-09-14T16:45:00.000Z", "distance":1000, "snapshot":[["id":"wheel"]]],
                          ["id":"after", "at":"1991-09-15T01:45:00", "startInstant":"1991-09-14T17:45:00.000Z", "distance":2000, "snapshot":[["id":"wheel"]]],
                          ["id":"unknown", "at":"1991-09-15T01:40:00", "distance":3000, "snapshot":[["id":"wheel"]]]]]
        let now = GearReminderEngine.parseInstant("1991-09-14T19:00:00Z")!
        let direct = GearReminderEngine.evaluate(reminder, state: state, total: 0, now: now)
        let indexed = GearReminderEngine.evaluate(reminder, state: state, total: 0, now: now, activities: GearReminderActivityIndex(state["activities"].array))
        XCTAssertEqual(direct, indexed)
        XCTAssertEqual(direct.distance, 2000)
        XCTAssertNotNil(direct.issue)
        var event = state["events"].array[0]; event["instant"] = "1991-09-14T16:30:00.000Z"; state["events"] = [event]
        XCTAssertNotEqual(GearReminderEngine.evaluate(reminder, state: state, total: 0, now: now).cycle, direct.cycle)
    }
    func testOverviewSeparatesSnoozedDueAndExpiredSnoozes() {
        var reminder = rule()
        let due = evaluate(reminder)
        XCTAssertEqual(due.readGroup(for: reminder, now: now), .due)
        reminder.snoozedCycle = due.cycle
        reminder.snoozedUntil = now.addingTimeInterval(60)
        let snoozed = evaluate(reminder)
        XCTAssertTrue(snoozed.due)
        XCTAssertEqual(snoozed.readGroup(for: reminder, now: now), .snoozed)
        XCTAssertEqual(snoozed.readGroup(for: reminder, now: now.addingTimeInterval(60)), .due)
        reminder.snoozedCycle = "previous-cycle"
        XCTAssertEqual(snoozed.readGroup(for: reminder, now: now), .due)
    }
    func testOverviewSeparatesInvalidPausedCompletedAndUpcomingReminders() {
        var reminder = rule()
        reminder.anchor = .event; reminder.anchorID = "missing"
        XCTAssertEqual(evaluate(reminder).readGroup(for: reminder, now: now), .needsReview)
        reminder.enabled = false
        XCTAssertEqual(evaluate(reminder).readGroup(for: reminder, now: now), .inactive)
        reminder = rule()
        for gear: Value in [["id": "chain", "retired": true], ["id": "chain", "deletedAt": "2026-10-16"]] {
            var state = fixture(); state["gears"] = .array([gear])
            XCTAssertEqual(evaluate(reminder, state).readGroup(for: reminder, now: now), .inactive)
        }
        reminder = rule(); reminder.kilometers = 400
        XCTAssertEqual(evaluate(reminder).readGroup(for: reminder, now: now), .upcoming)
        reminder = GearReminderEngine.complete(reminder, occurrence: evaluate(reminder), total: 300000, now: now)
        XCTAssertEqual(evaluate(reminder).readGroup(for: reminder, now: now), .inactive)
        reminder = rule(); reminder.anchor = .event; reminder.anchorID = "wax"; reminder.repeats = true
        reminder.completedCycle = evaluate(reminder).cycle
        XCTAssertTrue(reminder.enabled)
        XCTAssertEqual(evaluate(reminder).readGroup(for: reminder, now: now), .inactive)
    }
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
    func testEditingTitlePreservesSnoozeAndNoOpSaveKeepsCycle() {
        var saved = rule()
        saved.snoozedCycle = evaluate(saved).cycle; saved.snoozedUntil = now.addingTimeInterval(86400)
        XCTAssertEqual(saved.prepareEdit(replacing: saved, now: now), saved)
        var draft = saved; draft.title = "  检查链条  "
        draft.generation = "stale-generation"; draft.snoozedCycle = nil; draft.snoozedUntil = nil
        let edited = draft.prepareEdit(replacing: saved, now: now)
        XCTAssertEqual(edited.title, "检查链条")
        XCTAssertEqual(edited.generation, saved.generation)
        XCTAssertEqual(edited.startedAt, saved.startedAt)
        XCTAssertEqual(evaluate(edited).cycle, evaluate(saved).cycle)
        XCTAssertEqual(evaluate(edited).fireDate, saved.snoozedUntil)
        XCTAssertEqual(edited.snoozedCycle, saved.snoozedCycle)
    }
    func testEditingTitlePreservesCompletedOneTimeAndRepeatedDateOccurrences() {
        let initial = rule()
        let oneTime = GearReminderEngine.complete(initial, occurrence: evaluate(initial), total: 300000, now: now)
        var draft = oneTime; draft.title = "检查传动"
        let editedOneTime = draft.prepareEdit(replacing: oneTime, now: now)
        XCTAssertFalse(editedOneTime.enabled)
        XCTAssertEqual(editedOneTime.completedCycle, oneTime.completedCycle)
        XCTAssertEqual(evaluate(editedOneTime).issue, "已完成")

        var repeated = rule(); repeated.mode = .date; repeated.repeats = true; repeated.days = 3
        repeated.date = GearReminderEngine.parse("2026-10-10T09:00:00")!
        repeated = GearReminderEngine.complete(repeated, occurrence: evaluate(repeated), total: 0, now: now)
        let nextOccurrence = evaluate(repeated)
        draft = repeated; draft.title = "检查轮组"
        let editedDate = draft.prepareEdit(replacing: repeated, now: now)
        XCTAssertEqual(editedDate.generation, repeated.generation)
        XCTAssertEqual(editedDate.completedCycle, repeated.completedCycle)
        XCTAssertEqual(evaluate(editedDate).cycle, nextOccurrence.cycle)
        XCTAssertEqual(evaluate(editedDate).fireDate, GearReminderEngine.parse("2026-10-19T09:00:00"))
        XCTAssertFalse(evaluate(editedDate).due)
    }
    func testEditingReminderConfigurationStartsNewCycleAndClearsPreviousLifecycle() {
        var saved = rule()
        saved.completedCycle = evaluate(saved).cycle
        saved.snoozedCycle = saved.completedCycle; saved.snoozedUntil = now.addingTimeInterval(86400)
        let changes: [(String, (inout GearReminder) -> Void)] = [
            ("distance", { $0.kilometers = 500 }),
            ("days", { $0.days = 30 }),
            ("origin", { $0.anchor = .installation; $0.anchorID = "install" }),
            ("restart", { $0.startedAt = self.now }),
            ("repeat", { $0.repeats = true }),
            ("mode", { $0.mode = .total }),
            ("enabled", { $0.enabled = false })
        ]
        for (name, change) in changes {
            var draft = saved; change(&draft)
            let edited = draft.prepareEdit(replacing: saved, now: now)
            XCTAssertNotEqual(edited.generation, saved.generation, name)
            XCTAssertNil(edited.completedCycle, name)
            XCTAssertNil(edited.snoozedCycle, name)
            XCTAssertNil(edited.snoozedUntil, name)
        }
        var threshold = saved; threshold.kilometers = 500
        let editedThreshold = threshold.prepareEdit(replacing: saved, now: now)
        XCTAssertEqual(editedThreshold.startedAt, saved.startedAt)
        XCTAssertEqual(evaluate(editedThreshold).distance, 300000)
        XCTAssertFalse(evaluate(editedThreshold).due)
    }
    func testEditingTotalThresholdKeepsRepeatIntervalUntilThresholdChanges() {
        var saved = rule(); saved.mode = .total; saved.repeats = true
        saved = GearReminderEngine.complete(saved, occurrence: evaluate(saved, total: 310000), total: 310000, now: now)
        var draft = saved; draft.title = "检查累计使用量"
        let renamed = draft.prepareEdit(replacing: saved, now: now)
        XCTAssertEqual(renamed.repeatKilometers, 300)
        XCTAssertEqual(renamed.kilometers, 610)
        XCTAssertEqual(renamed.generation, saved.generation)
        draft.kilometers = 700
        let changed = draft.prepareEdit(replacing: saved, now: now)
        XCTAssertEqual(changed.repeatKilometers, 700)
        XCTAssertNotEqual(changed.generation, saved.generation)
    }
    func testEditingDateScheduleIgnoresHiddenUsageFieldsButAppliesDateAndIntervalChanges() {
        var saved = rule(); saved.mode = .date; saved.repeats = true; saved.days = 3
        saved.date = GearReminderEngine.parse("2026-10-10T09:00:00")!
        saved = GearReminderEngine.complete(saved, occurrence: evaluate(saved), total: 0, now: now)
        var draft = saved; draft.kilometers = 500; draft.anchorID = "other-record"
        let hiddenEdits = draft.prepareEdit(replacing: saved, now: now)
        XCTAssertEqual(hiddenEdits.generation, saved.generation)
        XCTAssertEqual(evaluate(hiddenEdits).fireDate, evaluate(saved).fireDate)
        draft.date = saved.date.addingTimeInterval(3600)
        XCTAssertNotEqual(draft.prepareEdit(replacing: saved, now: now).generation, saved.generation)
        draft = saved; draft.days = 7
        XCTAssertNotEqual(draft.prepareEdit(replacing: saved, now: now).generation, saved.generation)
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
    func testUsageProgressKeepsIndependentDistanceAndDayTargets() throws {
        var r = rule(); r.kilometers = 500; r.days = 6
        let result = evaluate(r)
        let progress = try XCTUnwrap(result.progress)
        XCTAssertEqual(progress.distance?.current, 300000)
        XCTAssertEqual(progress.distance?.target, 500000)
        XCTAssertEqual(progress.distance?.fraction, 0.6)
        XCTAssertEqual(progress.days?.current, 6)
        XCTAssertEqual(progress.days?.target, 6)
        XCTAssertEqual(progress.days?.fraction, 1)
        XCTAssertTrue(result.due)
        XCTAssertEqual(result.fireDate, now)
        XCTAssertEqual(progress.startedAt, r.startedAt)
        XCTAssertEqual(progress.deadline, GearReminderEngine.parse("2026-10-16T12:00:00"))

        r.snoozedCycle = result.cycle; r.snoozedUntil = now.addingTimeInterval(86400)
        let snoozed = evaluate(r)
        XCTAssertEqual(snoozed.progress, progress)
        XCTAssertEqual(snoozed.fireDate, r.snoozedUntil)
    }
    func testRepeatedEventProgressFollowsLatestMatchingMaintenance() throws {
        var r = rule(); r.anchor = .event; r.anchorID = "wax"; r.repeats = true; r.days = 30
        var state = fixture()
        state["gearEvents"] = .array(state["gearEvents"].array + [
            ["id":"wax2", "gearId":"chain", "kind":"hotWax", "occurredDate":"2026-10-15"],
            ["id":"drip", "gearId":"chain", "kind":"dripWax", "occurredDate":"2026-10-16"]
        ])
        state["activities"] = .array(state["activities"].array + [
            ["id":"new", "at":"2026-10-16T08:00:00", "distance":75000, "snapshot":[["id":"chain"]]]
        ])
        let progress = try XCTUnwrap(evaluate(r, state).progress)
        XCTAssertEqual(progress.distance?.current, 75000)
        XCTAssertEqual(progress.distance?.fraction, 0.25)
        XCTAssertEqual(progress.days?.current, 1)
        XCTAssertEqual(progress.days?.fraction, 1.0 / 30)
        XCTAssertEqual(progress.startedAt, GearReminderEngine.parse("2026-10-15T09:00:00"))
        XCTAssertEqual(progress.deadline, GearReminderEngine.parse("2026-11-14T09:00:00"))
    }
    func testInstallationProgressResetsWhenRepeatedReminderIsCompleted() throws {
        var r = rule(); r.anchor = .installation; r.anchorID = "install"; r.repeats = true; r.days = 30
        let initial = evaluate(r)
        let progress = try XCTUnwrap(initial.progress)
        XCTAssertEqual(progress.startedAt, GearReminderEngine.parse("2026-10-01T12:00:00"))
        XCTAssertEqual(progress.days?.current, 15)
        XCTAssertEqual(progress.days?.fraction, 0.5)
        let repeated = GearReminderEngine.complete(r, occurrence: initial, total: 300000, now: now)
        let reset = try XCTUnwrap(evaluate(repeated).progress)
        XCTAssertEqual(reset.startedAt, now)
        XCTAssertEqual(reset.distance?.current, 0)
        XCTAssertEqual(reset.days?.current, 0)
        XCTAssertEqual(reset.deadline, GearReminderEngine.parse("2026-11-15T18:00:00"))
    }
    func testDateProgressProvidesDeadlineWithoutInventingAPercentage() throws {
        var r = rule(); r.mode = .date; r.date = GearReminderEngine.parse("2026-10-20T09:00:00")!
        let progress = try XCTUnwrap(evaluate(r).progress)
        XCTAssertNil(progress.distance)
        XCTAssertNil(progress.days)
        XCTAssertNil(progress.startedAt)
        XCTAssertEqual(progress.deadline, r.date)
    }
    func testTotalProgressUsesLifetimeDistanceAndNextCumulativeTarget() throws {
        var r = rule(); r.mode = .total; r.repeats = true
        let original = evaluate(r, total: 310000)
        let progress = try XCTUnwrap(original.progress)
        XCTAssertEqual(progress.distance?.current, 310000)
        XCTAssertEqual(progress.distance?.target, 300000)
        XCTAssertEqual(progress.distance?.fraction, 1)
        XCTAssertNil(progress.days)
        XCTAssertNil(progress.startedAt)
        XCTAssertNil(progress.deadline)
        r = GearReminderEngine.complete(r, occurrence: original, total: 310000, now: now)
        let next = try XCTUnwrap(evaluate(r, total: 310000).progress)
        XCTAssertEqual(next.distance?.current, 310000)
        XCTAssertEqual(next.distance?.target, 610000)
        XCTAssertEqual(next.distance?.fraction, 310.0 / 610)
    }
    func testUnavailableReminderDoesNotClaimZeroOrCompletedProgress() {
        var r = rule(); r.enabled = false
        XCTAssertNil(evaluate(r).progress)
        r.enabled = true; r.completedCycle = evaluate(r).cycle
        XCTAssertNil(evaluate(r).progress)
        r.completedCycle = nil; r.anchor = .event; r.anchorID = "missing"
        XCTAssertNil(evaluate(r).progress)
        r.anchor = .installation
        XCTAssertNil(evaluate(r).progress)
        r = rule()
        var state = fixture(); state["gears"] = [["id":"chain", "retired":true]]
        XCTAssertNil(evaluate(r, state).progress)
        state["gears"] = [["id":"chain", "deletedAt":"2026-10-16"]]
        XCTAssertNil(evaluate(r, state).progress)
    }
    func testProgressClampsOverdueAndFutureAnchorValues() throws {
        var r = rule(); r.kilometers = 200; r.days = 2
        var progress = try XCTUnwrap(evaluate(r).progress)
        XCTAssertEqual(progress.distance?.current, 300000)
        XCTAssertEqual(progress.distance?.fraction, 1)
        XCTAssertEqual(progress.days?.current, 6)
        XCTAssertEqual(progress.days?.fraction, 1)

        r.startedAt = now.addingTimeInterval(86400)
        progress = try XCTUnwrap(evaluate(r).progress)
        XCTAssertEqual(progress.distance?.fraction, 0)
        XCTAssertEqual(progress.days?.current, 0)
        XCTAssertEqual(progress.days?.fraction, 0)

        r.kilometers = 0
        XCTAssertNil(evaluate(r).progress?.distance)
        XCTAssertNotNil(evaluate(r).progress?.days)
    }
    func testRoundTripAndValidation() throws {
        let r = rule(); XCTAssertEqual(try JSONDecoder().decode(GearReminder.self, from: JSONEncoder().encode(r)), r)
        var invalid = r; invalid.kilometers = -1; XCTAssertThrowsError(try invalid.validate())
        invalid = r; invalid.anchor = .event; XCTAssertThrowsError(try invalid.validate())
    }
}
