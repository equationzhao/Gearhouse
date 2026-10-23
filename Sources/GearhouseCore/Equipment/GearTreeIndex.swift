import Foundation

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

    public init(gears: [Value] = [], events: [Value] = [], at: String = "") {
        self.gears = gears
        byID = Dictionary(gears.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var latest: [String: Value] = [:]
        var future: String?
        for event in events {
            let date = event["at"].text
            guard date <= at else {
                if future == nil || date < future! { future = date }
                continue
            }
            let id = event["gearId"].text
            // Matches the stable date sort: the last event wins when dates tie.
            if latest[id] == nil || latest[id]!["at"].text <= date { latest[id] = event }
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
