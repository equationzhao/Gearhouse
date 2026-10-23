import SwiftUI
import UserNotifications
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct ReminderRoute: Identifiable { var id: String }

@MainActor
final class NativeNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NativeNotifications()
    @Published var opened: ReminderRoute?
    @Published var permissionDenied = false
    @Published var permissionRequired = false
    @Published var schedulingError: String?
    private let center = UNUserNotificationCenter.current()
    private var task: Task<Void, Never>?
    private var receipts: [String: Double] = UserDefaults.standard.dictionary(forKey: "reminderNotificationReceipts") as? [String: Double] ?? [:]
    override init() { super.init(); center.delegate = self }
    func authorize() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .notDetermined { permissionDenied = settings.authorizationStatus == .denied; permissionRequired = permissionDenied; return }
        do { let allowed = try await center.requestAuthorization(options: [.alert, .sound]); permissionDenied = !allowed; permissionRequired = !allowed }
        catch { schedulingError = "无法开启通知，请重试。" }
    }
    func refreshPermission() async {
        let settings = await center.notificationSettings()
        permissionRequired = settings.authorizationStatus == .denied || settings.authorizationStatus == .notDetermined
        permissionDenied = settings.authorizationStatus == .denied
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([.banner, .sound, .list]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["reminderID"] as? String
        // UIKit's foreground transition completion must run on the main thread.
        Task { @MainActor in
            if let id { self.opened = ReminderRoute(id: id) }
            completionHandler()
        }
    }
    struct Plan { var id: String; var reminderID: String; var title: String; var body: String; var date: Date; var snoozed: Bool }
    func reconcile(_ plans: @escaping @MainActor () -> [Plan]) {
        task?.cancel()
        task = Task {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await apply(plans())
        }
    }
    func flush(_ plans: [Plan]) async { task?.cancel(); await apply(plans) }
    private func apply(_ all: [Plan]) async {
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        permissionRequired = settings.authorizationStatus == .denied || settings.authorizationStatus == .notDetermined
        permissionDenied = settings.authorizationStatus == .denied
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        guard !Task.isCancelled else { return }
        let plans = Array(all.sorted { $0.date < $1.date }.prefix(60))
        let valid = Set(plans.map(\.id))
        let obsolete = pending.map(\.identifier).filter { $0.hasPrefix("gearhouse.reminder.") && !valid.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix("gearhouse.reminder.") && !valid.contains($0) })
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pendingIDs = Set(pending.map(\.identifier))
        let deliveredIDs = Set(delivered.map { $0.request.identifier })
        // Keep a receipt after delivery/dismissal to avoid notifying again on every sync.
        for id in obsolete where (receipts[id] ?? 0) > Date().timeIntervalSince1970 { receipts.removeValue(forKey: id) }
        var failure: String?
        for plan in plans {
            guard !Task.isCancelled else { break }
            if deliveredIDs.contains(plan.id) { receipts[plan.id] = min(receipts[plan.id] ?? Date().timeIntervalSince1970, Date().timeIntervalSince1970); continue }
            if let timestamp = receipts[plan.id], timestamp <= Date().timeIntervalSince1970, !pendingIDs.contains(plan.id) { continue }
            if let request = pending.first(where: { $0.identifier == plan.id }), let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(), abs(next.timeIntervalSince(plan.date)) < 2, request.content.title == plan.title, request.content.body == plan.body { continue }
            let content = UNMutableNotificationContent(); content.title = plan.title; content.body = plan.body; content.sound = .default
            content.userInfo = ["reminderID": plan.reminderID]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(2, plan.date.timeIntervalSinceNow), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                receipts[plan.id] = max(Date().addingTimeInterval(2).timeIntervalSince1970, plan.date.timeIntervalSince1970)
            } catch { failure = "无法安排通知，请重试。" }
        }
        schedulingError = failure
        UserDefaults.standard.set(receipts, forKey: "reminderNotificationReceipts")
    }
}
