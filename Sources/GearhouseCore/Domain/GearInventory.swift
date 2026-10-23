import Foundation

public enum GearInventory {
    public struct StockGroup: Identifiable, Sendable {
        public let id: String
        public let name: String
        public var rows: [GearTreeIndex.Row]
        public var isGrouped: Bool { rows.count > 1 }
    }
    private struct NameKey: Hashable {
        let category: String
        let name: String
        init(_ gear: Value) {
            category = gear["categoryId"].text.isEmpty ? gear["type"].text : gear["categoryId"].text
            name = gear["name"].text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    public static func groupStockRows(_ rows: [GearTreeIndex.Row], parents: [String: String]) -> [StockGroup] {
        let assemblies = Set(parents.values.filter { !$0.isEmpty })
        var result: [StockGroup] = [], positions: [NameKey: Int] = [:]
        for row in rows {
            let key = NameKey(row.gear)
            let canGroup = row.depth == 0 && !row.hasChildren && (parents[row.id] ?? "").isEmpty && !assemblies.contains(row.id) && !key.name.isEmpty
            if canGroup, let index = positions[key] { result[index].rows.append(row) }
            else {
                if canGroup { positions[key] = result.count }
                result.append(StockGroup(id: canGroup ? "group:\(key.category):\(key.name)" : "gear:" + row.id, name: key.name, rows: [row]))
            }
        }
        return result
    }
    public static func buildInstanceNumbers(_ gears: [Value]) -> [String: Int] {
        var result: [String: Int] = [:]
        for members in Dictionary(grouping: gears, by: NameKey.init).values where members.count > 1 {
            let ordered = members.sorted {
                let first = $0["createdAt"].text, second = $1["createdAt"].text
                return first == second ? $0.id < $1.id : first < second
            }
            for (index, gear) in ordered.enumerated() { result[gear.id] = index + 1 }
        }
        return result
    }
    public static func readStatus(state: Value, gearID: String, at: String) -> String {
        let gears = Dictionary(state["gears"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let parents = GearTreeIndex(gears: state["gears"].array, events: state["events"].array, at: at).parents
        var latest: [String: Value] = [:]
        for row in state["gearStates"].array where row["at"].text <= at {
            let id = row["gearId"].text
            if latest[id] == nil || latest[id]!["at"].text <= row["at"].text { latest[id] = row }
        }
        var current = gearID, seen = Set<String>()
        while !current.isEmpty && seen.insert(current).inserted {
            let gear = gears[current] ?? [:]
            let retired = gear["retired"].flag && (gear["retiredAt"].isNull || gear["retiredAt"].text <= at)
            let status = latest[current]?["status"].text ?? (retired ? "retired" : "active")
            if status == "retired" { return status }
            guard let parent = parents[current], !parent.isEmpty else { return status }
            current = parent
        }
        return "active"
    }

    public static func describeStatus(_ status: String) -> String {
        switch status { case "stock": return "库存"; case "retired": return "已退役"; default: return "使用中" }
    }
}
