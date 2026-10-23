import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeLaunchView: View {
    @EnvironmentObject private var store: NativeStore
    var body: some View {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "-preview-route")
        let route = index.flatMap { args.indices.contains($0+1) ? args[$0+1] : nil }
        switch route {
        case "backups": NavigationStack { NativeBackupSettings() }
        case "backup-versions": NavigationStack { NativeBackupVersions(manager: store.cloudBackup) }
        case "reminder": NativeEditor(route: .init(kind: "reminder", parent: "chain"))
        case "reminder-detail": NavigationStack { NativeGearDetail(id: "chain") }
        case "import-confirmation": NavigationStack { NativeBackupSettings(previewImportConfirmation: true) }
        case "gear": NavigationStack { NativeGearDetail(id: "clii") }
        case "gear-attachments": NavigationStack { NativeGearDetail(id: "tarmac") }.task { await NativeSelfTest.seedAttachments(store) }
        case "event": NativeEditor(route: .init(kind: "event", parent: "chain"))
        case "recompute": NativeEditor(route: .init(kind: "recompute", parent: "clii"))
        case "activity": NavigationStack { NativeActivityDetail(id: "demo-ride") }
        case "gear-edit": NativeEditor(route: .init(kind: "gear"))
        default: NativeRoot()
        }
        #else
        NativeRoot()
        #endif
    }
}
