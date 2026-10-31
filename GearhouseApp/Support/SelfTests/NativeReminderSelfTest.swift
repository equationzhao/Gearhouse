#if DEBUG
import Foundation
import UserNotifications
#if canImport(GearhouseCore)
import GearhouseCore
#endif

@MainActor
enum NativeReminderSelfTest {
    static func seedOriginTimesPreview(_ store: NativeStore) async {
        await seedProgressPreview(store)
        guard store.directory.lastPathComponent == "GearhousePreview", !store.reminders.contains(where: { $0.id == "preview-origin-times" }) else { return }
        do {
            let day = NativeDate.shift(NativeDate.today, -1)
            var backup = try Value.decode(store.exportBackup())
            var state = backup["state"]
            let choices: [Value] = [
                ["id": "preview-event-morning", "gearId": "chain", "kind": "inspection", "occurredDate": .string(day), "occurredTime": "08:15", "notes": "早间检查"],
                ["id": "preview-event-evening", "gearId": "chain", "kind": "inspection", "occurredDate": .string(day), "occurredTime": "18:45", "notes": "晚间检查"],
                ["id": "preview-event-undated-time", "gearId": "chain", "kind": "inspection", "occurredDate": .string(day), "occurredTime": .null, "notes": "当天检查"]
            ]
            state["gearEvents"] = .array(state["gearEvents"].array + choices)
            var reminder = GearReminder(gearID: "chain")
            reminder.id = "preview-origin-times"; reminder.title = "检查链条"; reminder.anchor = .event
            reminder.anchorID = "preview-event-morning"; reminder.days = 30
            state["reminders"] = .array(state["reminders"].array + [try Value.decode(JSONEncoder().encode(reminder))])
            backup["state"] = state
            try store.importBackup(backup.jsonData())
        } catch { store.error = error.userFacingMessage }
    }
    static func seedEditLifecyclePreview(_ store: NativeStore, completed: Bool) async {
        await seedProgressPreview(store)
        guard store.directory.lastPathComponent == "GearhousePreview" else { return }
        let id = completed ? "preview-edit-completed" : "preview-edit-snoozed"
        guard !store.reminders.contains(where: { $0.id == id }) else { return }
        do {
            var reminder = GearReminder(gearID: "chain")
            reminder.id = id; reminder.title = "检查链条"; reminder.mode = .total; reminder.kilometers = 1
            try store.saveReminder(reminder)
            if completed { try store.completeReminder(reminder) }
            else { try store.snoozeReminder(reminder) }
        } catch { store.error = error.userFacingMessage }
    }
    static func seedCopiedProgressPreview(_ store: NativeStore) async {
        await seedProgressPreview(store)
        guard store.directory.lastPathComponent == "GearhousePreview",
              !store.reminders.contains(where: { $0.id == "preview-copied-drip" }),
              let original = store.reminders.first(where: { $0.id == "preview-drip" }),
              let start = GearReminderEngine.calendar.date(byAdding: .day, value: -40, to: Date()) else { return }
        var copy = original.copyRule(to: "chain", state: store.state, now: start)
        copy.id = "preview-copied-drip"; copy.title = "复制的滴蜡"
        do { try store.saveReminder(copy) } catch { store.error = error.userFacingMessage }
    }
    static func seedOverviewPreview(_ store: NativeStore) async {
        await seedProgressPreview(store, includeAdditionalStates: true)
        guard store.directory.lastPathComponent == "GearhousePreview",
              !store.reminders.contains(where: { $0.id == "preview-snoozed" }) else { return }
        do {
            var reminder = GearReminder(gearID: "tarmac")
            reminder.id = "preview-snoozed"; reminder.title = "检查胎压"; reminder.mode = .date
            reminder.date = Date().addingTimeInterval(-3600)
            reminder.snoozedCycle = store.reminderOccurrence(reminder).cycle
            reminder.snoozedUntil = Date().addingTimeInterval(86400)
            try store.saveReminder(reminder)
            reminder = GearReminder(gearID: "propel")
            reminder.id = "preview-completed"; reminder.title = "检查刹车"; reminder.mode = .date
            reminder.date = Date().addingTimeInterval(-3600)
            try store.saveReminder(reminder)
            try store.completeReminder(reminder)
        } catch { store.error = error.userFacingMessage }
    }
    static func seedProgressPreview(_ store: NativeStore, includeAdditionalStates: Bool = false) async {
        guard store.directory.lastPathComponent == "GearhousePreview",
              !store.reminders.contains(where: { $0.id == "preview-drip" }) else { return }
        do {
            let now = Date()
            let calendar = GearReminderEngine.calendar
            func date(_ daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: now)! }
            func event(_ id: String, kind: String, daysAgo: Int) -> Value {
                ["id": .string(id), "gearId": "chain", "kind": .string(kind),
                 "occurredDate": .string(NativeDate.format(date(daysAgo), "yyyy-MM-dd")),
                 "occurredTime": .string(NativeDate.format(date(daysAgo), "HH:mm")),
                 "notes": "", "createdAt": .string(GearReminderEngine.wall(date(daysAgo)))]
            }
            func activity(_ id: String, daysAgo: Int, kilometers: Double) -> Value {
                ["id": .string(id), "name": "公路骑行", "at": .string(GearReminderEngine.wall(date(daysAgo))),
                 "type": "Ride", "distance": .number(kilometers * 1000), "seconds": .number(kilometers * 120),
                 "main": "tarmac", "remoteId": "demo-tarmac", "summary": false, "unavailable": false,
                 "deleted": false, "manual": false, "pending": false, "unknown": false, "equipmentDistance": true,
                 "snapshot": [["id": "tarmac", "parentId": .null], ["id": "chain", "parentId": "tarmac"]]]
            }
            var backup = try Value.decode(store.exportBackup())
            var state = backup["state"]
            state["activities"] = .array([
                activity("preview-older-ride", daysAgo: 20, kilometers: 226),
                activity("preview-recent-ride", daysAgo: 10, kilometers: 100),
                activity("preview-last-ride", daysAgo: 2, kilometers: 86)
            ])
            state["gearEvents"] = .array([
                event("preview-hot-wax-event", kind: "hotWax", daysAgo: 40),
                event("preview-drip-event", kind: "dripWax", daysAgo: 18)
            ])
            var drip = GearReminder(gearID: "chain")
            drip.id = "preview-drip"; drip.title = "滴蜡"; drip.kilometers = 300; drip.days = 30
            drip.anchor = .event; drip.anchorID = "preview-drip-event"; drip.repeats = true
            drip.startedAt = date(18)
            var hotWax = GearReminder(gearID: "chain")
            hotWax.id = "preview-hot-wax"; hotWax.title = "煮蜡"; hotWax.kilometers = 400
            hotWax.anchor = .event; hotWax.anchorID = "preview-hot-wax-event"; hotWax.repeats = true
            hotWax.startedAt = date(40)
            var scheduled = GearReminder(gearID: "chain")
            scheduled.id = "preview-date"; scheduled.title = "检查链条伸长量"; scheduled.mode = .date
            scheduled.date = date(-7)
            var reminders = [drip, hotWax, scheduled]
            if includeAdditionalStates {
                var total = GearReminder(gearID: "chain")
                total.id = "preview-total"; total.title = "更换链条"; total.mode = .total; total.kilometers = 999999.9
                var paused = drip
                paused.id = "preview-paused"; paused.title = "清洁链条"; paused.enabled = false
                var missing = drip
                missing.id = "preview-missing"; missing.title = "检查快拆扣"; missing.anchorID = "removed-preview-record"
                var long = drip
                long.id = "preview-long"; long.title = "清洁链条并检查飞轮、盘片与快拆扣的磨损情况"
                reminders += [total, paused, missing, long]
            }
            state["reminders"] = try Value.decode(JSONEncoder().encode(reminders))
            backup["state"] = state
            try store.importBackup(backup.jsonData())
        } catch { store.error = error.userFacingMessage }
    }
    static func run() async {
        var report: [String: String] = [:]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseReminderTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func check(_ condition: Bool, _ name: String) throws { report[name] = condition ? "passed" : "failed"; if !condition { throw DomainError(name) } }
        let center = UNUserNotificationCenter.current()
        do {
            let store = NativeStore(directory: directory, secretStore: MemorySecretStore())
            let gear = try store.commit("gear", ["name":"Reminder fixture", "type":"Chain"])
            let gearID = gear.id
            try check(!gearID.isEmpty, "fixtureGear")
            var r = GearReminder(gearID: gearID); r.title = "检查链条"; r.mode = .date; r.date = Date().addingTimeInterval(120)
            try store.saveReminder(r)
            let reloaded = NativeStore(directory: directory, secretStore: MemorySecretStore())
            try check(reloaded.reminders == [r], "persistsAfterReload")
            let restored = NativeStore(directory: directory.appendingPathComponent("Restored"), secretStore: MemorySecretStore())
            try restored.importBackup(store.exportBackup())
            try check(restored.reminders == [r], "backupRoundTrip")
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
            try check(granted, "notificationPermission")
            await NativeNotifications.shared.flush(store.notificationPlans())
            var pending = await center.pendingNotificationRequests()
            try check(pending.filter { $0.content.userInfo["reminderID"] as? String == r.id }.count == 1, "calendarScheduled")
            await NativeNotifications.shared.flush(store.notificationPlans())
            pending = await center.pendingNotificationRequests()
            try check(pending.filter { $0.content.userInfo["reminderID"] as? String == r.id }.count == 1, "syncDoesNotDuplicate")
            r.date = Date().addingTimeInterval(-10); r.generation = UUID().uuidString; try store.saveReminder(r)
            await NativeNotifications.shared.flush(store.notificationPlans())
            try await Task.sleep(for: .seconds(4))
            let delivered = await center.deliveredNotifications()
            try check(delivered.contains { $0.request.content.userInfo["reminderID"] as? String == r.id }, "actuallyDelivered")
            await NativeNotifications.shared.flush(store.notificationPlans())
            pending = await center.pendingNotificationRequests()
            try check(!pending.contains { $0.content.userInfo["reminderID"] as? String == r.id }, "deliveredDoesNotRepeat")
            try store.snoozeReminder(r)
            await NativeNotifications.shared.flush(store.notificationPlans())
            pending = await center.pendingNotificationRequests()
            try check(pending.contains { $0.content.userInfo["reminderID"] as? String == r.id && $0.identifier.contains("snooze") }, "snoozeSchedulesTomorrow")
            try store.removeReminder(r.id)
            await NativeNotifications.shared.flush(store.notificationPlans())
            pending = await center.pendingNotificationRequests()
            try check(!pending.contains { $0.content.userInfo["reminderID"] as? String == r.id }, "deleteCancelsNotification")
            var repeating = GearReminder(gearID: gearID); repeating.title = "扭矩检查"; repeating.mode = .date; repeating.date = Date().addingTimeInterval(3600); repeating.days = 30; repeating.repeats = true
            try store.saveReminder(repeating)
            await NativeNotifications.shared.flush(store.notificationPlans())
            pending = await center.pendingNotificationRequests()
            try check(pending.filter { $0.content.userInfo["reminderID"] as? String == repeating.id }.count == 13, "calendarRepeatsPrescheduled")
            try store.commit("delete", ["id": .string(gearID)])
            await NativeNotifications.shared.flush(store.notificationPlans())
            pending = await center.pendingNotificationRequests()
            try check(!pending.contains { $0.content.userInfo["reminderID"] as? String == repeating.id }, "deletedGearCancelsNotification")
        } catch { report["error"] = error.localizedDescription }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("reminder-self-test.json")
        try? JSONEncoder().encode(report).write(to: url, options: .atomic)
    }
}
#endif
