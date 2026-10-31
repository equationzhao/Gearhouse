import Foundation

public struct GearReminder: Codable, Identifiable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case total, usage, date }
    public enum Anchor: String, Codable, Sendable { case now, event, installation }
    public var id = UUID().uuidString
    public var gearID: String
    public var title = ""
    public var mode: Mode = .usage
    public var kilometers: Double = 300
    public var repeatKilometers: Double?
    public var days: Int = 0
    public var date = Date()
    public var anchor: Anchor = .now
    public var anchorID = ""
    public var eventKind: String?
    public var eventCustomName: String?
    public var startedAt = Date()
    public var repeats = false
    public var enabled = true
    public var completedCycle: String?
    public var snoozedCycle: String?
    public var snoozedUntil: Date?
    public var generation = UUID().uuidString
    public init(gearID: String) { self.gearID = gearID }

    public func prepareEdit(replacing existing: GearReminder?, now: Date = Date()) -> GearReminder {
        var next = self
        next.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing == nil || existing?.mode != mode || (mode == .usage && anchor == .now && existing?.anchor != .now) {
            next.startedAt = now
        }
        if mode == .total && (existing?.kilometers != kilometers || existing?.repeatKilometers == nil) {
            next.repeatKilometers = kilometers
        }
        if let existing, next.matchesConfiguration(of: existing) {
            next.generation = existing.generation
            next.completedCycle = existing.completedCycle
            next.snoozedCycle = existing.snoozedCycle
            next.snoozedUntil = existing.snoozedUntil
        } else {
            next.generation = UUID().uuidString
            next.completedCycle = nil
            next.snoozedCycle = nil
            next.snoozedUntil = nil
        }
        return next
    }
    private func matchesConfiguration(of other: GearReminder) -> Bool {
        guard gearID == other.gearID, mode == other.mode, repeats == other.repeats, enabled == other.enabled else { return false }
        switch mode {
        case .total: return kilometers == other.kilometers
        case .date: return date == other.date && (!repeats || days == other.days)
        case .usage:
            guard kilometers == other.kilometers, days == other.days, anchor == other.anchor else { return false }
            if anchor != .now { return anchorID == other.anchorID }
            return startedAt == other.startedAt && eventKind == other.eventKind
                && (eventKind != "custom" || eventCustomName == other.eventCustomName)
        }
    }

    public func copyRule(to gearID: String, state: Value, now: Date = Date()) -> GearReminder {
        var copy = self
        copy.id = UUID().uuidString; copy.gearID = gearID; copy.generation = UUID().uuidString
        copy.startedAt = now; copy.anchor = .now; copy.anchorID = ""
        copy.completedCycle = nil; copy.snoozedCycle = nil; copy.snoozedUntil = nil
        if mode == .total { copy.kilometers = repeatKilometers ?? kilometers }
        if mode == .date && date <= now { copy.date = GearReminderEngine.calendar.date(byAdding: .day, value: max(1, days), to: now)! }
        if anchor == .event, let event = state["gearEvents"].array.first(where: { $0.id == anchorID && $0["gearId"].text == self.gearID }) {
            copy.eventKind = event["kind"].text; copy.eventCustomName = event["customName"].text
        }
        return copy
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 100 else { throw DomainError("请填写提醒事项（最多 100 字）") }
        guard kilometers.isFinite, kilometers >= 0, kilometers <= 1_000_000, days >= 0, days <= 36500 else { throw DomainError("请输入有效的距离或天数") }
        if mode == .total && kilometers <= 0 { throw DomainError("请填写累计公里数") }
        if mode == .usage && kilometers == 0 && days == 0 { throw DomainError("请设置距离或天数") }
        if mode == .date && repeats && days < 1 { throw DomainError("请填写重复间隔") }
        if mode == .usage && anchor != .now && anchorID.isEmpty { throw DomainError("请选择一条历史记录") }
    }
}

public struct ReminderProgressMetric: Equatable, Sendable {
    public let current: Double
    public let target: Double

    public var fraction: Double {
        guard current.isFinite, target.isFinite, target > 0 else { return 0 }
        return min(1, max(0, current / target))
    }
}

public struct ReminderProgress: Equatable, Sendable {
    /// Distance is measured in meters, matching reminder evaluation and activity data.
    public let distance: ReminderProgressMetric?
    public let days: ReminderProgressMetric?
    public let startedAt: Date?
    /// The original deadline remains available even after a reminder is due or snoozed.
    public let deadline: Date?
}

public struct ReminderOccurrence: Equatable, Sendable {
    public var cycle: String
    public var due: Bool
    public var fireDate: Date?
    public var distance: Double
    public var remaining: Double
    public var issue: String?
    public var eventKind: String?
    public var eventCustomName: String?
    public var progress: ReminderProgress?
    public var paused = false

    public enum Group: Int, CaseIterable, Sendable {
        case due, needsReview, upcoming, snoozed, inactive
    }

    public func readGroup(for reminder: GearReminder, now: Date = Date()) -> Group {
        if !reminder.enabled || paused || reminder.completedCycle == cycle { return .inactive }
        if issue != nil { return .needsReview }
        if reminder.snoozedCycle == cycle, let until = reminder.snoozedUntil, until > now { return .snoozed }
        return due ? .due : .upcoming
    }
}

/// Shared by reminders for one saved state, including when viewing an old snapshot.
public struct GearReminderActivityIndex: Sendable {
    private struct Entry: Sendable { let at: Date; let instant: Date?; let distance: Double }
    private var byGear: [String: [Entry]] = [:]
    public init(_ activities: [Value]) {
        var seen = Set<String>()
        for activity in activities {
            guard seen.insert(activity.id).inserted, !activity["deleted"].flag, !activity["summary"].flag,
                  !activity["unavailable"].flag, let at = GearReminderEngine.parse(activity["at"].text) else { continue }
            var memberships = Set<String>()
            for row in activity["snapshot"].array {
                guard memberships.insert(row.id).inserted, row["distanceIncluded"] != false else { continue }
                byGear[row.id, default: []].append(Entry(at: at, instant: GearReminderEngine.parseInstant(activity["startInstant"].text), distance: max(0, activity["distance"].double)))
            }
        }
    }
    func distance(for gear: String, from: Date, through: Date, precise: Bool = false) -> (value: Double, uncertain: Bool) {
        var total = 0.0, uncertain = false
        for entry in byGear[gear] ?? [] {
            if precise && entry.instant == nil && (abs(entry.at.timeIntervalSince(from)) <= 2 * 86400 || abs(entry.at.timeIntervalSince(through)) <= 2 * 86400) { uncertain = true; continue }
            let at = precise ? (entry.instant ?? entry.at) : entry.at
            if at >= from && at <= through { total += entry.distance }
        }
        return (total, uncertain)
    }
}

public enum GearReminderEngine {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private static let isoFractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let formatters = NSCache<NSString, DateFormatter>()
    private static func formatter(_ pattern: String) -> DateFormatter {
        if let existing = formatters.object(forKey: pattern as NSString) { return existing }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = pattern
        formatters.setObject(f, forKey: pattern as NSString)
        return f
    }
    public static func parse(_ text: String) -> Date? {
        formatter(text.count <= 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ss").date(from: text.count == 16 ? text + ":00" : text)
    }
    public static func parseInstant(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return isoFractional.date(from: text) ?? isoPlain.date(from: text)
    }
    private static func instant(_ date: Date) -> String { isoFractional.string(from: date) }
    public static func wall(_ date: Date) -> String { formatter("yyyy-MM-dd'T'HH:mm:ss").string(from: date) }
    public static func eventDate(_ event: Value) -> Date? {
        if event["occurredTime"].isNull { return parse(event["occurredDate"].text).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } }
        return parse(event["occurredDate"].text + "T" + event["occurredTime"].text)
    }
    public static func evaluate(_ r: GearReminder, state: Value, total: Double, now: Date = Date(), activities: GearReminderActivityIndex? = nil) -> ReminderOccurrence {
        var result = ReminderOccurrence(cycle: r.generation, due: false, fireDate: nil, distance: 0, remaining: 0)
        guard r.enabled else { result.paused = true; result.issue = !r.repeats && r.completedCycle != nil ? "已完成" : "已暂停"; return result }
        guard let gear = state["gears"].array.first(where: { $0.id == r.gearID }), gear["deletedAt"].isNull else { result.paused = true; result.issue = "装备已移入回收站，提醒已暂停"; return result }
        guard GearInventory.readStatus(state: state, gearID: r.gearID, at: wall(now), instant: instant(now)) != "retired" else { result.paused = true; result.issue = "装备已退役，提醒已暂停"; return result }
        if r.mode == .date {
            var date = r.date
            if r.repeats, r.days > 0, date < now {
                let elapsed = calendar.dateComponents([.day], from: date, to: now).day ?? 0
                date = calendar.date(byAdding: .day, value: max(0, elapsed / r.days) * r.days, to: date)!
                // If today's scheduled time has not arrived, keep that upcoming occurrence.
            }
            result.cycle += ":" + wall(date)
            if r.completedCycle == result.cycle && r.repeats {
                date = calendar.date(byAdding: .day, value: r.days, to: date)!
                result.cycle = r.generation + ":" + wall(date)
            }
            result.fireDate = date; result.due = date <= now
            result.progress = ReminderProgress(distance: nil, days: nil, startedAt: nil, deadline: date)
        } else {
            var start = r.startedAt
            var preciseStart = false
            var dayOrigin: Date?
            if r.mode == .usage && (r.anchor == .event || r.eventKind != nil) {
                let selected = r.anchor == .event
                    ? state["gearEvents"].array.first(where: { $0.id == r.anchorID && $0["gearId"].text == r.gearID })
                    : state["gearEvents"].array.filter { $0["gearId"].text == r.gearID && $0["kind"].text == r.eventKind && (r.eventKind != "custom" || $0["customName"].text == r.eventCustomName) && $0["occurredDate"].text >= String(wall(r.startedAt).prefix(10)) && $0["occurredDate"].text <= String(wall(now).prefix(10)) }.min { (eventDate($0) ?? .distantFuture) < (eventDate($1) ?? .distantFuture) }
                if r.anchor == .event && selected.flatMap(eventDate) == nil { result.issue = "起点记录已删除，请重新选择"; return result }
                result.eventKind = r.eventKind; result.eventCustomName = r.eventCustomName
                if let selected, let selectedDate = eventDate(selected) {
                var event = selected
                if r.repeats {
                    event = state["gearEvents"].array.filter { e in
                        e["gearId"].text == r.gearID && e["kind"] == selected["kind"] && (e["kind"].text != "custom" || e["customName"] == selected["customName"]) && (eventDate(e) ?? .distantPast) >= selectedDate && e["occurredDate"].text <= String(wall(now).prefix(10))
                    }.max { (eventDate($0) ?? .distantPast) < (eventDate($1) ?? .distantPast) } ?? selected
                }
                start = eventDate(event)!
                if event["occurredTime"].isNull, let day = parse(event["occurredDate"].text) {
                    dayOrigin = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
                }
                result.cycle += ":" + event.id + ":" + wall(start)
                result.eventKind = event["kind"].text; result.eventCustomName = event["customName"].text
                }
            } else if r.mode == .usage && r.anchor == .installation {
                guard let event = state["events"].array.first(where: { $0.id == r.anchorID && $0["gearId"].text == r.gearID }), let date = event["instant"].isNull ? parse(event["at"].text) : parseInstant(event["instant"].text) else { result.issue = "装配记录已删除，请重新选择"; return result }
                preciseStart = !event["instant"].isNull
                start = date; result.cycle += ":" + event.id + ":" + (preciseStart ? event["instant"].text : wall(date))
            }
            if r.mode == .total { result.distance = total }
            else if let activities {
                let usage = activities.distance(for: r.gearID, from: start, through: now, precise: preciseStart)
                result.distance = usage.value
                if usage.uncertain { result.issue = "活动缺少可靠开始时刻，请同步后核对提醒。" }
            }
            else {
                var seen = Set<String>()
                for a in state["activities"].array {
                    guard seen.insert(a.id).inserted, !a["deleted"].flag, !a["summary"].flag, !a["unavailable"].flag,
                          let membership = a["snapshot"].array.first(where: { $0.id == r.gearID }), membership["distanceIncluded"] != false,
                          let local = parse(a["at"].text) else { continue }
                    let instant = parseInstant(a["startInstant"].text)
                    if preciseStart && instant == nil && (abs(local.timeIntervalSince(start)) <= 2 * 86400 || abs(local.timeIntervalSince(now)) <= 2 * 86400) { result.issue = "活动缺少可靠开始时刻，请同步后核对提醒。"; continue }
                    let at = preciseStart ? (instant ?? local) : local
                    guard at >= start, at <= now else { continue }
                    result.distance += max(0, a["distance"].double)
                }
            }
            result.remaining = max(0, r.kilometers * 1000 - result.distance)
            result.due = r.kilometers > 0 && result.remaining == 0
            var elapsedDays: ReminderProgressMetric?
            var deadline: Date?
            if r.mode == .usage && r.days > 0 {
                let origin = dayOrigin ?? start
                let date = calendar.date(byAdding: .day, value: r.days, to: origin)!
                deadline = date
                elapsedDays = ReminderProgressMetric(current: Double(max(0, calendar.dateComponents([.day], from: origin, to: now).day ?? 0)), target: Double(r.days))
                result.fireDate = date
                result.due = result.due || date <= now
            }
            result.progress = ReminderProgress(
                distance: r.kilometers > 0 ? ReminderProgressMetric(current: result.distance, target: r.kilometers * 1000) : nil,
                days: elapsedDays,
                startedAt: r.mode == .usage ? dayOrigin ?? start : nil,
                deadline: deadline
            )
            if result.due { result.fireDate = now }
        }
        if r.completedCycle == result.cycle { result.issue = "已完成"; result.due = false; result.fireDate = nil; result.progress = nil }
        if r.snoozedCycle == result.cycle, let until = r.snoozedUntil, result.fireDate != nil { result.fireDate = max(result.fireDate!, until) }
        return result
    }

    public static func complete(_ reminder: GearReminder, occurrence: ReminderOccurrence, total: Double, now: Date = Date()) -> GearReminder {
        var r = reminder
        r.completedCycle = occurrence.cycle; r.snoozedUntil = nil; r.snoozedCycle = nil
        if !r.repeats { r.enabled = false }
        else if r.mode == .total { let interval = r.repeatKilometers ?? r.kilometers; r.repeatKilometers = interval; r.kilometers = max(total / 1000, r.kilometers) + interval; r.generation = UUID().uuidString }
        else if r.mode == .usage && r.anchor != .event { r.anchor = .now; r.anchorID = ""; r.startedAt = now; r.generation = UUID().uuidString }
        // Event-based repetition only advances when a corresponding event is saved.
        return r
    }
}
