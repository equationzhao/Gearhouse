import Foundation

public struct GearActivityFilter: Equatable, Sendable {
    public enum Assignment: String, CaseIterable, Sendable {
        case all, unlinked, pending
    }
    public var type: String
    public var assignment: Assignment

    public init(type: String = "", assignment: Assignment = .all) {
        self.type = type
        self.assignment = assignment
    }

    public var isActive: Bool { !type.isEmpty || assignment != .all }

    public func matchesActivity(_ activity: Value) -> Bool {
        guard !activity["deleted"].flag, type.isEmpty || activity["type"].text == type else { return false }
        switch assignment {
        case .all: return true
        case .unlinked: return activity["main"].text.isEmpty && !activity["remoteId"].text.isEmpty
        case .pending: return activity["pending"].flag && activity["source"].text.uppercased() != "STRAVA"
        }
    }
}

/// Calendar dates are inclusive; the internal upper bound is the next midnight.
public struct ActivityDateRange: Equatable, Sendable {
    public let start: Date
    public let endExclusive: Date

    public init?(from: Date, through: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: from)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)),
              start < end else { return nil }
        self.start = start
        self.endExclusive = end
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < endExclusive }
}

public struct GearActivitySummary: Sendable {
    public let activities: [Activity]
    public let distance: Double?
    public let seconds: Int?
    public let missingDistanceCount: Int

    public init(gearID: String, activities: [Activity], range: ActivityDateRange? = nil) {
        self.activities = activities.filter {
            !$0.deleted && $0.mainGearID == gearID && (range?.contains($0.at) ?? true)
        }.sorted { $0.at > $1.at }
        let distances = self.activities.compactMap(\.equipmentDistance)
        let durations = self.activities.compactMap(\.seconds)
        distance = self.activities.isEmpty ? 0 : (distances.isEmpty ? nil : distances.reduce(0, +))
        seconds = self.activities.isEmpty ? 0 : (durations.isEmpty ? nil : durations.reduce(0, +))
        missingDistanceCount = self.activities.count - distances.count
    }
}
