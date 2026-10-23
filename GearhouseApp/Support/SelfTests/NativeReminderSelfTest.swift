#if DEBUG
import Foundation
import UserNotifications
#if canImport(GearhouseCore)
import GearhouseCore
#endif

@MainActor
enum NativeReminderSelfTest {
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
