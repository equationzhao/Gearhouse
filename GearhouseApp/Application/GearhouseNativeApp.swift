import SwiftUI
import BackgroundTasks
#if canImport(GearhouseCore)
import GearhouseCore
#endif

@main
struct GearhouseNativeApp: App {
    @StateObject private var store = NativeStore()
    @ObservedObject private var notifications = NativeNotifications.shared
    @Environment(\.scenePhase) private var phase
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-preview-route") { UIApplication.shared.isIdleTimerDisabled = true }
        if ProcessInfo.processInfo.arguments.contains("-keychain-self-test") { KeychainSelfTest.run() }
        if ProcessInfo.processInfo.arguments.contains("-reminder-self-test") { Task { @MainActor in await NativeReminderSelfTest.run() } }
        if ProcessInfo.processInfo.arguments.contains("-backup-self-test") { Task { @MainActor in await NativeBackupSelfTest.run() } }
        if ProcessInfo.processInfo.arguments.contains("-native-self-test") { Task { @MainActor in await NativeSelfTest.run() } }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            NativeLaunchView().environmentObject(store).environment(\.timeZone, NativeDate.zone)
                .sheet(item: Binding(get: { store.hasLoadedState ? notifications.opened : nil }, set: { notifications.opened = $0 })) { route in
                    NavigationStack { NativeReminderDetail(id: route.id).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { notifications.opened = nil } } } }.environmentObject(store)
                }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await store.automaticTick() } }
                    if value == .background { store.scheduleBackground() }
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-cloud-backup-self-test") {
                        await NativeBackupSelfTest.runCloud(store)
                        return
                    }
                    #endif
                    while !Task.isCancelled {
                        if phase == .active { await store.automaticTick() }
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
        .backgroundTask(.appRefresh(NativeStore.backgroundID)) { await store.automaticTick(); await store.flushNotifications() }
    }
}
