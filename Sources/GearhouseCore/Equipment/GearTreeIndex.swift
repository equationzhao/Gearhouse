import Foundation

public enum GearTimelineTime {
    public static func compare(_ lhs: Value, _ rhs: Value) -> Int {
        let li = lhs["instant"].text, ri = rhs["instant"].text
        if !li.isEmpty && !ri.isEmpty { return li == ri ? 0 : li < ri ? -1 : 1 }
        let la = lhs["at"].text, ra = rhs["at"].text
        let ld = String(la.prefix(10)), rd = String(ra.prefix(10))
        if ld != rd { return ld < rd ? -1 : 1 }
        if la == ra && la.hasSuffix("T00:00:00") { return 0 }
        if li.isEmpty != ri.isEmpty {
            let plain = li.isEmpty ? lhs : rhs
            if plain["allDay"].flag || plain["at"].text.hasSuffix("T00:00:00") { return li.isEmpty ? -1 : 1 }
            if la != ra { return la < ra ? -1 : 1 }
            return li.isEmpty ? -1 : 1
        }
        return la == ra ? 0 : la < ra ? -1 : 1
    }
    public static func applies(_ row: Value, at: String, instant: String?) -> Bool {
        if !row["instant"].text.isEmpty, let instant { return row["instant"].text <= instant }
        return row["at"].text <= at
    }
}

/// A read model for one displayed tree. Pending moves never change saved events.
public struct GearTreeIndex: Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let gear: Value
        public let depth: Int
        public let hasChildren: Bool
        public var id: String { gear.id }
    }
    public let gears: [Value]
    public let byID: [String: Value]
    public let parents: [String: String]
    public let nextEventAt: String?

    public init(gears: [Value] = [], events: [Value] = [], at: String = "", instant: String? = nil) {
        self.gears = gears
        byID = Dictionary(gears.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var latest: [String: Value] = [:]
        var future: String?
        for event in events {
            let date = event["at"].text
            guard GearTimelineTime.applies(event, at: at, instant: instant) else {
                if future == nil || date < future! { future = date }
                continue
            }
            let id = event["gearId"].text
            // Matches the stable date sort: the last event wins when dates tie.
            if latest[id] == nil || GearTimelineTime.compare(latest[id]!, event) <= 0 { latest[id] = event }
        }
        parents = latest.mapValues { $0["parentId"].text }
        nextEventAt = future
    }

    public func rows(pending: [String: String] = [:], collapsed: Set<String> = [], query: String = "",
                     showRetired: Bool = false, showHidden: Bool = false, trash: Bool = false, placement: String? = nil, statuses: Value = [:], categoryID: String = "") -> [Row] {
        let visible = gears.filter {
            if trash { return !$0["deletedAt"].isNull }
            let status = statuses[$0.id].isNull ? ($0["retired"].flag ? "retired" : "active") : statuses[$0.id].text
            return $0["deletedAt"].isNull && (showRetired || status != "retired") && (showHidden || !$0["hidden"].flag)
                && (placement == nil || status == placement || (showRetired && status == "retired" && placement == "active"))
        }
        let known = Set(visible.map(\.id))
        func parent(_ id: String) -> String { pending[id] ?? parents[id] ?? "" }
        let children = Dictionary(grouping: visible, by: { parent($0.id) })
        var result: [Row] = [], visited = Set<String>()
        func visit(_ gear: Value, _ depth: Int) {
            guard visited.insert(gear.id).inserted else { return }
            if (query.isEmpty || gear["name"].text.localizedCaseInsensitiveContains(query)) && (categoryID.isEmpty || gear["categoryId"].text == categoryID) {
                result.append(Row(gear: gear, depth: query.isEmpty && categoryID.isEmpty ? depth : 0, hasChildren: children[gear.id]?.isEmpty == false))
            }
            if !collapsed.contains(gear.id) || !query.isEmpty || !categoryID.isEmpty {
                for child in children[gear.id] ?? [] { visit(child, depth + 1) }
            }
        }
        for gear in visible where trash || !known.contains(parent(gear.id)) { visit(gear, 0) }
        return result
    }
}
