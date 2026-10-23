import Foundation

public enum GearTimeline {
    /// Attribute a component's record to the equipment it belonged to when it happened.
    public static func buildRows(state: Value, gearID: String) -> [Value] {
        let gears = Dictionary(state["gears"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let histories = Dictionary(grouping: state["events"].array, by: { $0["gearId"].text })
            .mapValues { $0.sorted { $0["at"].text < $1["at"].text } }
        func parent(_ id: String, at: String, inclusive: Bool) -> String {
            let events = histories[id] ?? []
            var low = 0, high = events.count
            while low < high {
                let middle = (low + high) / 2, date = events[middle]["at"].text
                if date < at || (inclusive && date == at) { low = middle + 1 } else { high = middle }
            }
            return low == 0 ? "" : events[low - 1]["parentId"].text
        }
        func belongs(_ id: String, at: String, inclusive: Bool = true) -> Bool {
            var current = id, seen = Set<String>()
            while !current.isEmpty && seen.insert(current).inserted {
                if current == gearID { return true }
                current = parent(current, at: at, inclusive: inclusive)
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
            if belongs(subject, at: at) || belongs(subject, at: at, inclusive: false) {
                var row = decorate(event, kind: "installation", subject: subject, at: at)
                row["fromParentId"] = .optional(parent(subject, at: at, inclusive: false))
                rows.append(row)
            }
        }
        for operation in state["gearOperations"].array {
            let at = operation["at"].text
            let members = operation["gearIds"].array.map(\.text)
            let parentID = operation["parentId"].text
            if members.contains(where: { belongs($0, at: at) || belongs($0, at: at, inclusive: false) }) || (!parentID.isEmpty && belongs(parentID, at: at)) {
                let subject = members.contains(gearID) ? gearID : operation["gearId"].text
                rows.append(decorate(operation, kind: "operation", subject: subject, at: at))
            }
        }
        for event in state["gearStates"].array where event["operationId"].isNull && event["installationId"].isNull {
            let subject = event["gearId"].text, at = event["at"].text
            if belongs(subject, at: at) { rows.append(decorate(event, kind: "status", subject: subject, at: at)) }
        }
        for event in state["gearEvents"].array {
            let subject = event["gearId"].text
            let at = event["occurredDate"].text + "T" + (event["occurredTime"].isNull ? "23:59:59" : event["occurredTime"].text + ":00")
            if belongs(subject, at: at) { rows.append(decorate(event, kind: "event", subject: subject, at: at)) }
        }
        if let gear = gears[gearID], !gear["purchased"].isNull {
            rows.append(decorate(["id": .string(gearID)], kind: "purchase", subject: gearID, at: gear["purchased"].text))
        }
        return rows.sorted {
            if $0["at"] == $1["at"] { return $0["timelineID"].text < $1["timelineID"].text }
            return $0["at"].text > $1["at"].text
        }
    }
}
