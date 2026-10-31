import Foundation

public enum GearTimeline {
    /// Attribute a component's record to the equipment it belonged to when it happened.
    public static func buildRows(state: Value, gearID: String) -> [Value] {
        let gears = Dictionary(state["gears"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        func compare(_ lhs: Value, _ rhs: Value) -> Int {
            let li = lhs["instant"].text, ri = rhs["instant"].text
            if !li.isEmpty && !ri.isEmpty { return li == ri ? 0 : li < ri ? -1 : 1 }
            let ld = String(lhs["at"].text.prefix(10)), rd = String(rhs["at"].text.prefix(10))
            if ld != rd { return ld < rd ? -1 : 1 }
            if lhs["at"] == rhs["at"] && lhs["at"].text.hasSuffix("T00:00:00") { return 0 }
            if li.isEmpty != ri.isEmpty {
                let dateOnly = li.isEmpty ? lhs : rhs
                if dateOnly["allDay"].flag || dateOnly["at"].text.hasSuffix("T00:00:00") { return li.isEmpty ? -1 : 1 }
            }
            let la = lhs["at"].text, ra = rhs["at"].text
            return la == ra ? 0 : la < ra ? -1 : 1
        }
        let histories = Dictionary(grouping: state["events"].array, by: { $0["gearId"].text })
            .mapValues { $0.sorted { compare($0, $1) < 0 } }
        func parent(_ id: String, point: Value, inclusive: Bool) -> String {
            let events = histories[id] ?? []
            var low = 0, high = events.count
            while low < high {
                let middle = (low + high) / 2, order = compare(events[middle], point)
                if order < 0 || (inclusive && order == 0) { low = middle + 1 } else { high = middle }
            }
            return low == 0 ? "" : events[low - 1]["parentId"].text
        }
        func belongs(_ id: String, point: Value, inclusive: Bool = true) -> Bool {
            var current = id, seen = Set<String>()
            while !current.isEmpty && seen.insert(current).inserted {
                if current == gearID { return true }
                current = parent(current, point: point, inclusive: inclusive)
            }
            return false
        }
        func decorate(_ value: Value, kind: String, subject: String, at: String) -> Value {
            var row = value
            row["entryType"] = .string(kind)
            row["timelineID"] = .string(kind + ":" + value.id)
            row["subjectGearId"] = .string(subject)
            row["subjectName"] = gears[subject]?["name"] ?? .string("装备")
            row["at"] = .string(at)
            return row
        }
        var rows: [Value] = []
        for event in state["events"].array {
            if !event["operationId"].isNull { continue }
            let subject = event["gearId"].text, at = event["at"].text
            if belongs(subject, point: event) || belongs(subject, point: event, inclusive: false) {
                var row = decorate(event, kind: "installation", subject: subject, at: at)
                row["fromParentId"] = .optional(parent(subject, point: event, inclusive: false))
                rows.append(row)
            }
        }
        for operation in state["gearOperations"].array {
            let at = operation["at"].text
            let members = operation["gearIds"].array.map(\.text)
            let parentID = operation["parentId"].text
            if members.contains(where: { belongs($0, point: operation) || belongs($0, point: operation, inclusive: false) }) || (!parentID.isEmpty && belongs(parentID, point: operation)) {
                let subject = members.contains(gearID) ? gearID : operation["gearId"].text
                rows.append(decorate(operation, kind: "operation", subject: subject, at: at))
            }
        }
        for event in state["gearStates"].array where event["operationId"].isNull && event["installationId"].isNull {
            let subject = event["gearId"].text, at = event["at"].text
            if belongs(subject, point: event) { rows.append(decorate(event, kind: "status", subject: subject, at: at)) }
        }
        for event in state["gearEvents"].array {
            let subject = event["gearId"].text
            let at = event["occurredDate"].text + "T" + (event["occurredTime"].isNull ? "23:59:59" : event["occurredTime"].text + ":00")
            if belongs(subject, point: ["at": .string(at)]) { rows.append(decorate(event, kind: "event", subject: subject, at: at)) }
        }
        if let gear = gears[gearID], !gear["purchased"].isNull {
            rows.append(decorate(["id": .string(gearID)], kind: "purchase", subject: gearID, at: gear["purchased"].text))
        }
        return rows.sorted {
            let order = compare($0, $1)
            return order == 0 ? $0["timelineID"].text < $1["timelineID"].text : order > 0
        }
    }
}
