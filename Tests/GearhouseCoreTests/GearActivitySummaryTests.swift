import XCTest
@testable import GearhouseCore

final class GearActivitySummaryTests: XCTestCase {
    func testActivityFiltersCombineTypeAndAssignmentWithoutTreatingLocalStravaAsPending() {
        let rows: [Value] = [
            ["id": "linked", "type": "Ride", "main": "bike", "remoteId": "remote"],
            ["id": "unlinked", "type": "Ride", "remoteId": "missing"],
            ["id": "indoor", "type": "VirtualRide", "remoteId": "missing"],
            ["id": "none", "type": "Ride"],
            ["id": "pending", "type": "Ride", "pending": true, "mainConflict": true],
            ["id": "local", "type": "Ride", "pending": true, "source": "strava"],
            ["id": "deleted", "type": "Ride", "pending": true, "deleted": true]
        ]
        XCTAssertEqual(rows.filter(GearActivityFilter(type: "Ride", assignment: .unlinked).matchesActivity).map(\.id), ["unlinked"])
        XCTAssertEqual(rows.filter(GearActivityFilter(assignment: .unlinked).matchesActivity).map(\.id), ["unlinked", "indoor"])
        XCTAssertEqual(rows.filter(GearActivityFilter(assignment: .pending).matchesActivity).map(\.id), ["pending"])
        XCTAssertFalse(GearActivityFilter().isActive)
        XCTAssertTrue(GearActivityFilter(type: "VirtualRide").isActive)
        XCTAssertEqual(rows.filter(GearActivityFilter().matchesActivity).count, 6)
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testInclusiveDaysAndGearMembership() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let range = try XCTUnwrap(ActivityDateRange(from: date("2026-10-01T04:00:00Z"), through: date("2026-10-02T04:00:00Z"), calendar: calendar))
        let rows = [
            Activity(id: "first", name: "Start", type: "Ride", at: date("2026-09-30T16:00:00Z"), distance: 20000, seconds: 1000, mainGearID: "bike"),
            Activity(id: "last", name: "End", type: "Ride", at: date("2026-10-02T15:59:59Z"), distance: 30000, seconds: 2000, mainGearID: "bike"),
            Activity(id: "next", name: "Outside", type: "Ride", at: date("2026-10-02T16:00:00Z"), distance: 99999, mainGearID: "bike"),
            Activity(id: "other", name: "Other", type: "Ride", at: date("2026-10-01T00:00:00Z"), distance: 99999, mainGearID: "other"),
            Activity(id: "deleted", name: "Deleted", type: "Ride", at: date("2026-10-01T00:00:00Z"), distance: 99999, mainGearID: "bike", deleted: true)
        ]
        let summary = GearActivitySummary(gearID: "bike", activities: rows, range: range)
        XCTAssertEqual(summary.activities.map(\.id), ["last", "first"])
        XCTAssertEqual(summary.distance, 50000)
        XCTAssertEqual(summary.seconds, 3000)
        XCTAssertNil(ActivityDateRange(from: date("2026-10-03T00:00:00Z"), through: date("2026-10-01T00:00:00Z"), calendar: calendar))
    }
    func testDaylightSavingUsesCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = date("2026-03-08T12:00:00Z")
        let range = try XCTUnwrap(ActivityDateRange(from: day, through: day, calendar: calendar))
        XCTAssertEqual(range.endExclusive.timeIntervalSince(range.start), 23 * 3600)
    }
    func testIndoorDistancePreservesActivityDistanceAndLegacyPolicy() throws {
        let rows = [
            Activity(id: "new", name: "Virtual", type: "VirtualRide", at: Date(), distance: 40000, seconds: 3000, mainGearID: "bike", equipmentDistanceIncluded: false),
            Activity(id: "old", name: "Legacy", type: "VirtualRide", at: Date(), distance: 20000, seconds: 1500, mainGearID: "bike"),
            Activity(id: "unknown", name: "No distance", type: "Ride", at: Date(), mainGearID: "bike")
        ]
        let summary = GearActivitySummary(gearID: "bike", activities: rows)
        XCTAssertEqual(summary.distance, 20000)
        XCTAssertEqual(summary.activities.count, 3)
        XCTAssertEqual(summary.seconds, 4500)
        XCTAssertEqual(summary.missingDistanceCount, 1)
        XCTAssertEqual(rows[0].distance, 40000)
        let oldJSON = #"{"id":"legacy","name":"Virtual","type":"VirtualRide","at":"2026-10-01T00:00:00Z","distance":30000,"deleted":false}"#
        let old = try JSONDecoder.gearhouse.decode(Activity.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(old.equipmentDistance, 30000)
        XCTAssertNil(old.equipmentDistanceIncluded)
    }
    func testMissingDistancesAreNotReportedAsZero() {
        let rows = [Activity(id: "unknown", name: "Missing", type: "Ride", at: Date(), mainGearID: "bike")]
        let summary = GearActivitySummary(gearID: "bike", activities: rows)
        XCTAssertNil(summary.distance)
        XCTAssertEqual(summary.missingDistanceCount, 1)
        XCTAssertEqual(GearActivitySummary(gearID: "other", activities: rows).distance, 0)
    }
}
