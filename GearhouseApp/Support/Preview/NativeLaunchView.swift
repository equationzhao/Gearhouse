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
        Group { switch route {
        case "equipment-long-content": NativeRoot().task { await NativeSelfTest.seedLongContentPreview(store) }
        case "equipment-design": NativeRoot().task { await NativeSelfTest.seedEquipmentPreview(store) }
        case "equipment-design-detail": NavigationStack { NativeGearDetail(id: "tarmac") }.task { await NativeSelfTest.seedEquipmentPreview(store) }
        case "equipment-photo-fallback": NativeRoot().task { NativeSelfTest.seedPhotoFallbackPreview(store) }
        case "timeline": NavigationStack { NativeGearTimeline(gearID: "tarmac") }.task { await NativeSelfTest.seedLongContentPreview(store) }
        case "categories": NavigationStack { NativeCategories() }
        case "photo-missing": NativePhotoGallery(ids: ["preview-missing-image"])
        case "photo-zoom": NativePhotoZoomPreview()
        case "sync-cancellation": NativeSyncCancellationPreview()
        case "sync-gear-refresh": NativeSyncGearRefreshPreview()
        case "activity-gear-refresh-empty": NativeSyncGearRefreshPreview(showActivities: true)
        case "activity-gear-refresh-populated": NativeSyncGearRefreshPreview(showActivities: true, includeActivity: true)
        case "sync-history": NavigationStack { NativeSync() }.task {
            store.perform("sync-rows", ["rows": [], "writes": [:], "from": "2026-10-10", "to": "2026-10-12", "next": "2026-10-13"])
            store.perform("sync-settings", ["enabled": false, "lastSuccess": "2026-10-24T01:30:00.000Z"])
        }
        case "backups": NavigationStack { NativeBackupSettings() }
        case "backup-versions": NavigationStack { NativeBackupVersions(manager: store.cloudBackup) }
        case "backup-versions-empty": NativeEmptyBackupPreview()
        case "backup-read-failure": NativeBackupReadFailurePreview(includeRecovery: false)
        case "backup-read-failure-local": NativeBackupReadFailurePreview(includeRecovery: true)
        case "backup-scan-pending": NativeBackupScanPreview(scenario: "pending")
        case "backup-scan-unreadable": NativeBackupScanPreview(scenario: "unreadable")
        case "backup-scan-mixed": NativeBackupScanPreview(scenario: "mixed")
        case "startup-recovery": NativeLibraryRecoveryPreview()
        case "reminder": NativeEditor(route: .init(kind: "reminder", parent: "chain"))
        case "reminders-overview": NativeRoot().task { await NativeReminderSelfTest.seedOverviewPreview(store) }
        case "reminders-empty": NavigationStack { NativeReminderOverview() }
        case "reminder-detail": NavigationStack { NativeGearDetail(id: "chain") }
        case "reminder-progress-detail": NavigationStack { NativeReminderDetail(id: "preview-drip") }.task { await NativeReminderSelfTest.seedProgressPreview(store) }
        case "reminder-progress-readonly": NavigationStack { NativeReminderDetail(id: "preview-drip") }.task {
            await NativeReminderSelfTest.seedProgressPreview(store)
            store.snapshotDate = NativeDate.today
        }
        case "reminder-copied-progress": NavigationStack { NativeReminderDetail(id: "preview-copied-drip") }.task {
            await NativeReminderSelfTest.seedCopiedProgressPreview(store)
        }
        case "reminder-edit-snoozed": NavigationStack { NativeReminderDetail(id: "preview-edit-snoozed") }.task {
            await NativeReminderSelfTest.seedEditLifecyclePreview(store, completed: false)
        }
        case "reminder-edit-completed": NavigationStack { NativeReminderDetail(id: "preview-edit-completed") }.task {
            await NativeReminderSelfTest.seedEditLifecyclePreview(store, completed: true)
        }
        case "reminder-origin-times": NavigationStack { NativeReminderDetail(id: "preview-origin-times") }.task {
            await NativeReminderSelfTest.seedOriginTimesPreview(store)
        }
        case "reminder-progress": NavigationStack { NativeGearDetail(id: "chain") }.task { await NativeReminderSelfTest.seedProgressPreview(store) }
        case "reminder-progress-states": NavigationStack { NativeGearDetail(id: "chain") }.task { await NativeReminderSelfTest.seedProgressPreview(store, includeAdditionalStates: true) }
        case "import-confirmation": NavigationStack { NativeBackupSettings(previewImportConfirmation: true) }
        case "gear": NavigationStack { NativeGearDetail(id: "clii") }
        case "gear-attachments": NavigationStack { NativeGearDetail(id: "tarmac") }.task { await NativeSelfTest.seedAttachments(store) }
        case "event": NativeEditor(route: .init(kind: "event", parent: "chain"))
        case "component": NativeEditor(route: .init(kind: "component", parent: "tarmac"))
        case "installation": NativeEditor(route: .init(kind: "history", parent: "chain"))
        case "move-review": NativeMoveReview(changes: [["gearId": "front", "fromParentId": "clii", "parentId": "propel"]], complete: {})
        case "recompute": NativeEditor(route: .init(kind: "recompute", parent: "clii"))
        case "recompute-baseline": NativeEditor(route: .init(kind: "recompute", parent: "tarmac")).task { await NativeSelfTest.seedLongContentPreview(store) }
        case "activity": NavigationStack { NativeActivityDetail(id: "demo-ride") }
        case "activity-list-unlinked": NativeRoot().task { NativeSelfTest.seedActivityPreview(store, scenario: "unlinked") }
        case "activity-duplicate-choices": NavigationStack { NativeActivityDetail(id: "demo-ride") }.task { NativeSelfTest.seedDuplicateChoicesPreview(store) }
        case "activity-pending": NavigationStack { NativeActivityDetail(id: "demo-ride") }.task { NativeSelfTest.seedActivityPreview(store, scenario: "pending") }
        case "activity-conflict": NavigationStack { NativeActivityDetail(id: "demo-ride") }.task { NativeSelfTest.seedActivityPreview(store, scenario: "conflict") }
        case "activity-unlinked": NavigationStack { NativeActivityDetail(id: "demo-ride") }.task { NativeSelfTest.seedActivityPreview(store, scenario: "unlinked") }
        case "gear-edit": NativeEditor(route: .init(kind: "gear"))
        case "gear-edit-missing-remote": NativeEditor(route: .init(kind: "gear", item: store.gear("tarmac"))).task { store.perform("gear-refresh", ["rows":[]]) }
        case "gear-inherited-retirement": NavigationStack { NativeGearDetail(id: "chain") }.task { NativeSelfTest.seedInheritedRetirementPreview(store, retired: true) }
        case "gear-inherited-reactivated": NavigationStack { NativeGearDetail(id: "chain") }.task { NativeSelfTest.seedInheritedRetirementPreview(store, retired: false) }
        case "inventory-replacement-edit": NativeReplacementEditPreview()
        case "inventory-batch-retired": NativeEditor(route: .init(kind: "inventory-batch", item: ["gearIds": ["tarmac", "chain", "propel"]]))
            .task { NativeSelfTest.seedInheritedRetirementPreview(store, retired: true) }
        default: NativeRoot()
        } }.preferredColorScheme(args.contains("-preview-dark") ? .dark : args.contains("-preview-light") ? .light : nil)
            .tint(NativeAppearance.accent)
        #else
        NativeRoot()
        #endif
    }
}

#if DEBUG
@MainActor
private final class NativeLibraryRecoveryFixture {
    let store: NativeStore
    private let directory: URL
    private let repairedState: Data
    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseLibraryRecoveryPreview-" + UUID().uuidString)
        directory = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let donor = NativeStore(directory: root.appendingPathComponent("Donor"), secretStore: MemorySecretStore())
        try donor.commit("gear", ["name": "本机示例自行车", "type": "Bike"])
        repairedState = try donor.state.jsonData()
        guard let gear = donor.state["gears"].array.first else { throw DomainError("示例数据无法创建") }
        try donor.commit("gear", ["id": gear["id"], "name": "备份示例自行车", "type": "Bike"])
        _ = try GearBackupArchive.create(state: donor.state, media: donor.directory.appendingPathComponent("media"), in: root.appendingPathComponent("Recovery"))
        try Data("{synthetic unreadable library".utf8).write(to: root.appendingPathComponent("state-v2.json"), options: .atomic)
        store = NativeStore(directory: root, secretStore: MemorySecretStore())
    }
    func repairLocalFile() throws {
        try repairedState.write(to: directory.appendingPathComponent("state-v2.json"), options: .atomic)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

private struct NativeLibraryRecoveryPreview: View {
    @State private var fixture: NativeLibraryRecoveryFixture?
    @State private var failure: String?
    var body: some View {
        Group {
            if let fixture { NativeLibraryRecoveryPreviewContent(fixture: fixture, store: fixture.store) }
            else if let failure { Text(failure) }
            else { ProgressView() }
        }.task {
            guard fixture == nil else { return }
            do {
                let next = try NativeLibraryRecoveryFixture()
                await next.store.cloudBackup.reload()
                guard !Task.isCancelled else { return }
                fixture = next
            } catch { if !Task.isCancelled { failure = error.userFacingMessage } }
        }
    }
}

private struct NativeLibraryRecoveryPreviewContent: View {
    let fixture: NativeLibraryRecoveryFixture
    @ObservedObject var store: NativeStore
    @State private var repaired = false
    @State private var failure: String?
    var body: some View {
        NativeRoot().environmentObject(store)
            .overlay(alignment: .topTrailing) {
                if !store.hasLoadedState {
                    VStack {
                        Button {
                            do { try fixture.repairLocalFile(); repaired = true }
                            catch { failure = error.userFacingMessage }
                        } label: {
                            Image(systemName: "wrench.and.screwdriver").font(.system(size: 18)).frame(width: 44, height: 44)
                        }.disabled(repaired).accessibilityLabel("修复示例数据").accessibilityIdentifier("library-fixture-repair")
                        if let failure { Text(failure) }
                    }.padding(.trailing, 12)
                }
            }
    }
}

@MainActor
private final class NativeBackupScanFixture {
    let store: NativeStore
    private let directory: URL
    private let candidates: URL
    private let worker = NativeBackupWorker()
    private var pendingPackages = Set<String>()
    init(scenario: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseBackupScanPreview-" + UUID().uuidString)
        directory = root; candidates = root.appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(at: candidates, withIntermediateDirectories: true)
        let settings: Value = ["enabled": false, "bookmark": .string(Data("synthetic scan override".utf8).base64EncodedString())]
        try settings.jsonData().write(to: root.appendingPathComponent("cloud-backup-settings.json"))
        store = NativeStore(directory: root, secretStore: MemorySecretStore())
        try store.commit("gear", ["name": "备份读取测试装备", "type": "Bike"])
        if scenario == "mixed" {
            _ = try GearBackupArchive.create(state: store.state, media: root.appendingPathComponent("media"), in: candidates)
            _ = try await worker.safety(state: store.state, directory: root)
        }
        if scenario == "pending" || scenario == "mixed" {
            let name = "Waiting." + GearBackupArchive.fileExtension
            try FileManager.default.createDirectory(at: candidates.appendingPathComponent(name), withIntermediateDirectories: true)
            pendingPackages.insert(name)
        }
        if scenario == "unreadable" || scenario == "mixed" {
            let broken = candidates.appendingPathComponent("Unreadable." + GearBackupArchive.fileExtension)
            try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
            try Data("synthetic unreadable manifest".utf8).write(to: broken.appendingPathComponent("manifest.json"))
        }
        store.cloudBackup.readVersionsForTesting = { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.worker.scanVersionsForTesting(in: self.candidates, pendingPackages: self.pendingPackages).scan
        }
        await store.cloudBackup.reload()
    }
    func repairVersions() async throws {
        for name in ["Waiting", "Unreadable"] {
            let file = candidates.appendingPathComponent(name + "." + GearBackupArchive.fileExtension)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        pendingPackages = []
        if store.cloudBackup.versions.isEmpty {
            _ = try GearBackupArchive.create(state: store.state, media: directory.appendingPathComponent("media"), in: candidates)
        }
        await store.cloudBackup.reload()
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

private struct NativeBackupScanPreview: View {
    let scenario: String
    @State private var fixture: NativeBackupScanFixture?
    @State private var failure: String?
    var body: some View {
        Group {
            if let fixture {
                NavigationStack {
                    NativeBackupVersions(manager: fixture.store.cloudBackup)
                        .environmentObject(fixture.store)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Task {
                                        do { try await fixture.repairVersions() }
                                        catch { failure = error.userFacingMessage }
                                    }
                                } label: { Image(systemName: "arrow.clockwise") }
                                    .disabled(fixture.store.cloudBackup.working).accessibilityLabel("更新示例备份").accessibilityIdentifier("backup-fixture-repair")
                            }
                        }
                }
            } else if let failure { Text(failure) }
            else { ProgressView() }
        }.task {
            guard fixture == nil else { return }
            do {
                let next = try await NativeBackupScanFixture(scenario: scenario)
                guard !Task.isCancelled else { return }
                fixture = next
            } catch { if !Task.isCancelled { failure = error.userFacingMessage } }
        }
    }
}

private struct NativeSyncGearRefreshPreview: View {
    @EnvironmentObject private var store: NativeStore
    var showActivities = false
    var includeActivity = false
    @State private var fixture: NativeSyncCancellationFixture?
    @State private var error: String?
    var body: some View {
        Group {
            if let fixture {
                NavigationStack {
                    Group {
                        if showActivities { NativeActivities() }
                        else { NativeSync() }
                    }.toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成读取") { fixture.releaseReads() }
                                .accessibilityIdentifier("sync-preview-finish-refresh")
                        }
                    }
                }.environmentObject(fixture.store)
            } else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard fixture == nil else { return }
            do {
                let directory = store.directory.appendingPathComponent("SyncGearRefreshPreview")
                try? FileManager.default.removeItem(at: directory)
                let next = try NativeSyncCancellationFixture(directory: directory, automatic: false, holdingCatalog: true)
                if includeActivity {
                    try next.store.commit("sync-rows", ["rows":[["id":"gear-refresh-existing-ride", "name":"已保留的测试活动",
                        "start_date_local":.string(NativeDate.today + "T00:00:00"), "type":"Ride", "distance":1000, "moving_time":60]],
                        "writes":[:], "from":.string(NativeDate.today), "to":.string(NativeDate.today), "next":.string(NativeDate.shift(NativeDate.today, 1))])
                }
                fixture = next
                try await next.store.refreshRemoteGears()
            } catch is CancellationError { }
            catch { self.error = error.userFacingMessage }
        }.onDisappear { fixture?.close() }
    }
}

private struct NativeSyncCancellationPreview: View {
    @EnvironmentObject private var store: NativeStore
    @State private var fixture: NativeSyncCancellationFixture?
    @State private var error: String?
    var body: some View {
        Group {
            if let fixture { NativeRoot().environmentObject(fixture.store) }
            else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard fixture == nil else { return }
            do {
                let preserving = ProcessInfo.processInfo.arguments.contains("-preserve-preview")
                let directory = store.directory.appendingPathComponent("SyncCancellationPreview")
                if !preserving { try? FileManager.default.removeItem(at: directory) }
                let next = try NativeSyncCancellationFixture(directory: directory, automatic: false, preserving: preserving)
                fixture = next
                guard !preserving || next.store.state["activities"].array.isEmpty else { return }
                next.store.startSync()
                while next.store.busy && !Task.isCancelled { try await Task.sleep(for: .milliseconds(25)) }
                try next.readCancellationResult().jsonData().write(to: store.directory.appendingPathComponent("sync-cancellation-preview.json"), options: .atomic)
            } catch is CancellationError { }
            catch { self.error = error.userFacingMessage }
        }.onDisappear { fixture?.close() }
    }
}

private struct NativeBackupReadFailurePreview: View {
    let includeRecovery: Bool
    @State private var previewStore: NativeStore?
    @State private var error: String?
    var body: some View {
        Group {
            if let previewStore {
                NavigationStack { NativeBackupVersions(manager: previewStore.cloudBackup) }
                    .environmentObject(previewStore)
            } else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard previewStore == nil else { return }
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseBackupFailurePreview-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let settings: Value = ["enabled": false, "bookmark": .string(Data("invalid fixture bookmark".utf8).base64EncodedString())]
                try settings.jsonData().write(to: directory.appendingPathComponent("cloud-backup-settings.json"))
                let fixture = NativeStore(directory: directory, secretStore: MemorySecretStore())
                if includeRecovery {
                    try fixture.commit("gear", ["name": "本机恢复测试装备", "type": "Bike"])
                    _ = try await NativeBackupWorker().safety(state: fixture.state, directory: directory)
                }
                await fixture.cloudBackup.reload()
                previewStore = fixture
            } catch { self.error = error.userFacingMessage }
        }
    }
}

private struct NativeReplacementEditPreview: View {
    @EnvironmentObject private var store: NativeStore
    @State private var operation: Value = .null
    @State private var error: String?
    var body: some View {
        Group {
            if let error { Text(error) }
            else if operation.isNull { ProgressView() }
            else { NativeEditor(route: .init(kind: "inventory", item: operation, parent: "clii")) }
        }.task {
            guard operation.isNull else { return }
            do { operation = try NativeSelfTest.seedReplacementEditPreview(store) }
            catch { self.error = error.userFacingMessage }
        }
    }
}

@MainActor
private struct NativeEmptyBackupPreview: View {
    @StateObject private var manager: NativeCloudBackup
    private let directory: URL
    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseEmptyBackupPreview-" + UUID().uuidString)
        self.directory = directory
        _manager = StateObject(wrappedValue: NativeCloudBackup(directory: directory, isolated: true))
    }
    var body: some View {
        NavigationStack { NativeBackupVersions(manager: manager) }
            .onDisappear { try? FileManager.default.removeItem(at: directory) }
    }
}
#endif
