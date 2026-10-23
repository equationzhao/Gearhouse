import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

extension NativeStore {
    func saveReminder(_ reminder: GearReminder) throws {
        try reminder.validate()
        guard state["gears"].array.contains(where: { $0.id == reminder.gearID && $0["deletedAt"].isNull }) else { throw DomainError("装备不存在或已删除") }
        if reminder.mode == .usage && reminder.anchor != .now {
            let field = reminder.anchor == .event ? "gearEvents" : "events"
            guard state[field].array.contains(where: { $0.id == reminder.anchorID && $0["gearId"].text == reminder.gearID }) else { throw DomainError("请选择有效的起点记录") }
        }
        var rows = reminders
        if let index = rows.firstIndex(where: { $0.id == reminder.id }) { rows[index] = reminder } else { rows.append(reminder) }
        try replaceReminders(rows)
    }
    func removeReminder(_ id: String) throws { try replaceReminders(reminders.filter { $0.id != id }) }
    func completeReminder(_ r: GearReminder) throws {
        let total = try query("view")["statistics"][r.gearID]["distance"].double
        let occurrence = GearReminderEngine.evaluate(r, state: state, total: total)
        try saveReminder(GearReminderEngine.complete(r, occurrence: occurrence, total: total))
    }
    func snoozeReminder(_ r: GearReminder) throws {
        var next = r; next.snoozedCycle = reminderOccurrence(r).cycle
        next.snoozedUntil = GearReminderEngine.calendar.date(byAdding: .day, value: 1, to: Date())
        try saveReminder(next)
    }
    func notificationPlans() -> [NativeNotifications.Plan] {
        guard !reminders.isEmpty else { return [] }
        let now = Date()
        var plans: [NativeNotifications.Plan] = []
        for r in reminders {
            let occurrence = reminderOccurrence(r, now: now)
            guard occurrence.issue == nil, let fire = occurrence.fireDate else { continue }
            func append(_ date: Date, _ cycle: String) {
                let snoozed = r.snoozedCycle == cycle && r.snoozedUntil != nil
                plans.append(.init(id: "gearhouse.reminder." + r.id + "." + cycle + (snoozed ? ".snooze.\(Int(r.snoozedUntil!.timeIntervalSince1970))" : ""), reminderID: r.id, title: name(r.gearID), body: r.title, date: date, snoozed: snoozed))
            }
            append(fire, occurrence.cycle)
            if r.mode == .date && r.repeats {
                // Pre-schedule fixed calendar repeats so they work even while the app is closed.
                let original = occurrence.cycle
                let dateText = String(original.dropFirst(r.generation.count + 1))
                let base = GearReminderEngine.parse(dateText) ?? fire
                for n in 1...12 {
                    let next = GearReminderEngine.calendar.date(byAdding: .day, value: r.days * n, to: base)!
                    append(next, r.generation + ":" + GearReminderEngine.wall(next))
                }
            }
        }
        return plans
    }
}

func reminderSubtitle(_ r: GearReminder, _ occurrence: ReminderOccurrence) -> String {
    if let issue = occurrence.issue { return issue }
    if r.snoozedCycle == occurrence.cycle, let until = r.snoozedUntil, until > Date() { return "稍后提醒 · " + NativeDate.format(until, "M月d日 HH:mm") }
    if occurrence.due { return "待处理" }
    if r.mode == .date, let date = occurrence.fireDate { return NativeDate.format(date, "M月d日 HH:mm") }
    var values: [String] = []
    if r.kilometers > 0 { values.append(String(format: "还剩 %.0f km", ceil(occurrence.remaining / 1000))) }
    if let date = occurrence.fireDate { values.append(NativeDate.format(date, "M月d日")) }
    return values.joined(separator: " · ")
}
