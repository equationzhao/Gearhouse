import SwiftUI
import UniformTypeIdentifiers
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct NativeBackupSettings: View {
    @EnvironmentObject private var store: NativeStore
    var previewImportConfirmation = false
    var body: some View { NativeBackupSettingsContent(manager: store.cloudBackup, previewImportConfirmation: previewImportConfirmation) }
}

private struct NativeBackupSettingsContent: View {
    @EnvironmentObject private var store: NativeStore
    @ObservedObject var manager: NativeCloudBackup
    var previewImportConfirmation = false
    @State private var locationPicker = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document: NativeBackupDocument?
    @State private var pendingPackage: NativeBackupVersion?
    @State private var pendingImport: Data?
    @State private var failure: String?
    var body: some View {
        Form {
            Section {
                Toggle("iCloud Drive 自动备份", isOn: Binding(get: { manager.enabled }, set: { enabled in
                    if enabled && !manager.hasLocation { locationPicker = true }
                    else { manager.setEnabled(enabled) }
                })).disabled(manager.working).accessibilityIdentifier("backup-enabled")
                if manager.working {
                    HStack { ProgressView(); Text(manager.phase) }
                } else if manager.uploading {
                    Label("等待 iCloud 上传", systemImage: "icloud.and.arrow.up")
                } else if let date = manager.lastBackup {
                    LabeledContent("最近备份") { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                } else { Text("尚无备份").foregroundStyle(.secondary) }
                NavigationLink("恢复备份") { NativeBackupVersions(manager: manager) }
                    .accessibilityIdentifier("backup-versions").disabled(manager.working)
            }
            if let error = manager.error ?? failure { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("备份与恢复").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("立即备份", systemImage: "icloud.and.arrow.up") { Task { await manager.tick(force: true) } }
                    .disabled(!manager.enabled || manager.working).accessibilityIdentifier("backup-now")
                Button("选择备份文件夹", systemImage: "folder") { locationPicker = true }.disabled(manager.working)
                Divider()
                Button("导出备份") {
                    do { document = NativeBackupDocument(data: try store.exportBackup()); exporting = true }
                    catch { failure = error.userFacingMessage }
                }.disabled(manager.working)
                Button("导入备份") { importing = true }.disabled(store.busy || manager.working)
            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("更多备份操作")
        }
        .task {
            await manager.reload()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-route") && ProcessInfo.processInfo.arguments.contains("-backup-qa") { seedBackupPhoto() }
            if previewImportConfirmation { pendingImport = try? store.exportBackup() }
            #endif
        }
        .fileImporter(isPresented: $locationPicker, allowedContentTypes: [.folder]) { result in
            do { let url = try result.get(); Task { await manager.select(url) } }
            catch { if (error as NSError).code != NSUserCancelledError { failure = error.userFacingMessage } }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Gearhouse-" + NativeDate.today) { result in
            if case .failure(let error) = result { failure = error.userFacingMessage }
        }
        .sheet(item: $pendingPackage) { NativeBackupRestore(manager: manager, version: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(exportedAs: "com.equationzhao.gearhouse.backup", conformingTo: .package)]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() == GearBackupArchive.fileExtension {
                    pendingPackage = NativeBackupVersion(manifest: try GearBackupArchive.manifest(at: url), url: url, uploaded: false, local: true)
                } else {
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 500 * 1024 * 1024 else { throw DomainError("备份过大") }
                    pendingImport = try Data(contentsOf: url)
                }
            } catch { failure = error.userFacingMessage }
        }
        .confirmationDialog("使用备份替换本机数据？", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("导入并替换", role: .destructive) {
                guard let data = pendingImport else { return }
                do { try store.importBackup(data); failure = nil } catch { failure = error.userFacingMessage }
                pendingImport = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: { Text("当前装备、活动、记录、图片和附件将被替换。导入前会保留一份本机备份。") }
    }
    #if DEBUG
    private func seedBackupPhoto() {
        guard store.state["photos"].array.isEmpty, let gear = store.gears.first else { return }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        do {
            let id = try store.addImage(image.pngData()!, owner: "gear", id: gear.id)
            try store.commit("photo-edit", ["ownerType":"gear", "ownerId":gear["id"], "action":"cover", "id":.string(id)])
        } catch { failure = error.userFacingMessage }
    }
    #endif
}

struct NativeBackupVersions: View {
    @ObservedObject var manager: NativeCloudBackup
    @State private var selected: NativeBackupVersion?
    var body: some View {
        List {
            if manager.working { HStack { ProgressView(); Text(manager.phase) } }
            if !manager.versions.isEmpty {
                Section("iCloud Drive") { ForEach(manager.versions) { version in versionRow(version) } }
            }
            if !manager.localVersions.isEmpty {
                Section("恢复前备份 · 本机") { ForEach(manager.localVersions) { version in versionRow(version) } }
            }
            if !manager.working && manager.versions.isEmpty && manager.localVersions.isEmpty { Text("暂无备份").foregroundStyle(.secondary) }
            if let error = manager.error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("恢复备份").navigationBarTitleDisplayMode(.inline)
        .task { await manager.reload() }
        .refreshable { await manager.reload() }
        .sheet(item: $selected) { NativeBackupRestore(manager: manager, version: $0) }
    }
    private func versionRow(_ version: NativeBackupVersion) -> some View {
        Button { selected = version } label: {
            HStack {
                Text(version.manifest.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                Spacer()
                if manager.waitingForUpload(version) { Image(systemName: "icloud.and.arrow.up").foregroundStyle(.secondary).accessibilityLabel("等待上传") }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }.tint(.primary).accessibilityIdentifier("backup-version-" + version.id).disabled(manager.working)
    }
}

private struct NativeBackupRestore: View {
    @ObservedObject var manager: NativeCloudBackup
    @Environment(\.dismiss) private var dismiss
    let version: NativeBackupVersion
    @State private var confirming = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("备份时间") { Text(version.manifest.createdAt, format: .dateTime.year().month().day().hour().minute().second()) }
                    LabeledContent("装备", value: "\(version.manifest.gears) 件")
                    LabeledContent("活动", value: "\(version.manifest.activities) 次")
                    LabeledContent("记录", value: "\(version.manifest.records) 条")
                    LabeledContent("图片", value: "\(version.manifest.photos.count) 张")
                    if let attachments = version.manifest.attachments, !attachments.isEmpty { LabeledContent("附件", value: "\(attachments.count) 个") }
                }
                Section {
                    if manager.working { HStack { ProgressView(); Text(manager.phase) } }
                    else { Button("恢复这份备份", role: .destructive) { confirming = true }.accessibilityIdentifier("backup-restore") }
                }
                if let error = manager.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("备份详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(manager.working) } }
            .interactiveDismissDisabled(manager.working)
            .confirmationDialog("恢复这份备份？", isPresented: $confirming, titleVisibility: .visible) {
                Button("恢复并替换", role: .destructive) { Task { if await manager.restore(version) { dismiss() } } }.accessibilityIdentifier("backup-restore-confirm")
                Button("取消", role: .cancel) {}
            } message: { Text("当前装备、活动、记录、图片和附件将被替换。恢复前会保留一份本机备份。") }
        }
    }
}
