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
    private enum FileOperation: Equatable {
        case preparingExport, readingImport
        var title: String { self == .preparingExport ? "正在准备导出" : "正在读取备份" }
    }
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
    @State private var fileOperation: FileOperation?
    @State private var fileOperationID: UUID?
    @State private var fileTask: Task<Void, Never>?
    @State private var stoppingFileOperation = false
    #if DEBUG
    @State private var previewHeldExport = false
    #endif
    private var fileControlsDisabled: Bool { manager.working || fileOperation != nil }
    private var importBlocked: Bool { manager.working || store.busy || store.refreshingGears || store.backupRestoring }
    var body: some View {
        Form {
            Section("自动备份") {
                Toggle("iCloud Drive 自动备份", isOn: Binding(get: { manager.enabled }, set: { enabled in
                    if enabled && !manager.hasLocation { failure = nil; locationPicker = true }
                    else { manager.setEnabled(enabled) }
                })).disabled(manager.working || !store.hasLoadedState).accessibilityIdentifier("backup-enabled")
                if manager.working {
                    HStack { ProgressView(); Text(manager.phase) }
                } else if manager.uploading {
                    Label("等待 iCloud 上传", systemImage: "icloud.and.arrow.up")
                } else if let date = manager.lastBackup {
                    LabeledContent("最近备份") { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                } else { Text("尚无备份").foregroundStyle(NativeAppearance.secondaryText) }
                Button { Task { await manager.tick(force: true) } } label: {
                    Label("立即备份", systemImage: "icloud.and.arrow.up")
                        .foregroundStyle(store.hasLoadedState && manager.enabled && !manager.working && !store.busy ? NativeAppearance.accent : NativeAppearance.secondaryText)
                }.disabled(!store.hasLoadedState || !manager.enabled || manager.working || store.busy).accessibilityIdentifier("backup-now")
                Button { failure = nil; locationPicker = true } label: { Label("选择备份文件夹", systemImage: "folder") }
                    .disabled(manager.working).accessibilityIdentifier("backup-location")
            }
            Section {
                NavigationLink { NativeBackupVersions(manager: manager) } label: { Label("恢复备份", systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("backup-versions").disabled(manager.working)
            }
            Section("备份文件") {
                Button(action: prepareFileExport) {
                    Label("导出备份", systemImage: "square.and.arrow.up")
                        .foregroundStyle(!store.hasLoadedState || fileControlsDisabled ? NativeAppearance.secondaryText : NativeAppearance.accent)
                }.disabled(!store.hasLoadedState || fileControlsDisabled).accessibilityIdentifier("backup-export")
                Button { failure = nil; importing = true } label: { Label("导入备份", systemImage: "square.and.arrow.down") }
                    .disabled(store.busy || store.refreshingGears || fileControlsDisabled).accessibilityIdentifier("backup-import")
                if let fileOperation {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(stoppingFileOperation ? "正在停止…" : fileOperation.title)
                            .foregroundStyle(NativeAppearance.secondaryText)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("backup-file-progress")
                    Button("取消", action: cancelFileOperation)
                        .disabled(stoppingFileOperation).accessibilityIdentifier("backup-file-cancel")
                }
            }
            if let failure {
                Section { Text(failure).foregroundStyle(NativeAppearance.dangerText).accessibilityIdentifier("backup-file-error") }
            }
            if let error = manager.error {
                Section { Text(error).foregroundStyle(NativeAppearance.dangerText).accessibilityIdentifier("backup-cloud-error") }
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("备份与恢复").navigationBarTitleDisplayMode(.inline)
        .alert("使用备份替换本机数据？", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("导入并替换", role: .destructive) {
                guard let data = pendingImport else { return }
                guard !importBlocked else {
                    failure = "请等待当前操作完成后，再重新选择备份文件。"; pendingImport = nil
                    return
                }
                do { try store.importBackup(data); failure = nil } catch { failure = error.userFacingMessage }
                pendingImport = nil
            }.disabled(importBlocked)
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: {
            Text((store.hasLoadedState
                  ? "当前本机数据将被替换，包括装备及类别、活动、记录、提醒、图片和附件。导入前会保留本机现有数据。"
                  : "本机数据将被替换。导入前会保留当前无法读取的数据文件。")
                 + (importBlocked ? "\n\n请等待当前操作完成后再导入。" : ""))
        }
        .onDisappear {
            fileOperationID = nil
            fileTask?.cancel(); fileTask = nil
            fileOperation = nil; stoppingFileOperation = false
        }
        .task {
            await manager.reload()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-route") && ProcessInfo.processInfo.arguments.contains("-backup-qa") { seedBackupPhoto() }
            if previewImportConfirmation { pendingImport = try? store.exportBackup() }
            #endif
        }
        .fileImporter(isPresented: $locationPicker, allowedContentTypes: [.folder]) { result in
            do { let url = try result.get(); failure = nil; Task { await manager.select(url) } }
            catch { if (error as NSError).code != NSUserCancelledError { failure = error.userFacingMessage } }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Gearhouse-" + NativeDate.today) { result in
            document = nil
            switch result {
            case .success: failure = nil
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { failure = error.userFacingMessage }
            }
        }
        .sheet(item: $pendingPackage) { NativeBackupRestore(manager: manager, version: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(exportedAs: "com.equationzhao.gearhouse.backup", conformingTo: .package)]) { result in
            do {
                readImportSelection(try result.get())
            } catch { if (error as NSError).code != NSUserCancelledError { failure = error.userFacingMessage } }
        }
    }
    private func prepareFileExport() {
        guard store.hasLoadedState, !fileControlsDisabled else { return }
        let id = UUID(), state = store.state, generation = store.imageImportGeneration
        let media = store.directory.appendingPathComponent("media")
        fileOperationID = id; fileOperation = .preparingExport; stoppingFileOperation = false
        failure = nil; document = nil
        #if DEBUG
        let hold = store.directory.lastPathComponent == "GearhousePreview"
            && ProcessInfo.processInfo.arguments.contains("-preview-route")
            && ProcessInfo.processInfo.arguments.contains("-hold-backup-export") && !previewHeldExport
        if hold { previewHeldExport = true }
        #endif
        fileTask = Task {
            defer { finishFileOperation(id) }
            do {
                let data: Data
                #if DEBUG
                if hold {
                    data = try await NativeBackupFiles.prepareExport(state: state, media: media, beforeRead: { _ in
                        try await Task.sleep(for: .seconds(60))
                    })
                } else { data = try await NativeBackupFiles.prepareExport(state: state, media: media) }
                #else
                data = try await NativeBackupFiles.prepareExport(state: state, media: media)
                #endif
                try Task.checkCancellation()
                guard fileOperationID == id else { return }
                guard generation == store.imageImportGeneration else { throw DomainError("本机数据已恢复，请重新导出备份。") }
                document = NativeBackupDocument(data: data); exporting = true
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && fileOperationID == id { failure = error.userFacingMessage }
            }
        }
    }
    private func readImportSelection(_ url: URL) {
        guard fileOperation == nil else { return }
        let id = UUID()
        fileOperationID = id; fileOperation = .readingImport; stoppingFileOperation = false
        failure = nil; pendingImport = nil; pendingPackage = nil
        fileTask = Task {
            defer { finishFileOperation(id) }
            do {
                let selection = try await NativeBackupFiles.readSelection(from: url)
                try Task.checkCancellation()
                guard fileOperationID == id else { return }
                switch selection {
                case .json(let data): pendingImport = data
                case .package(let version): pendingPackage = version
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && fileOperationID == id { failure = error.userFacingMessage }
            }
        }
    }
    private func cancelFileOperation() {
        guard fileOperation != nil else { return }
        stoppingFileOperation = true
        fileTask?.cancel()
    }
    private func finishFileOperation(_ id: UUID) {
        guard fileOperationID == id else { return }
        fileOperationID = nil; fileTask = nil; fileOperation = nil; stoppingFileOperation = false
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
            if !manager.working && manager.versions.isEmpty && manager.localVersions.isEmpty {
                if let error = manager.error {
                    ContentUnavailableView {
                        Label("无法读取备份", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(error).foregroundStyle(NativeAppearance.secondaryText)
                    } actions: {
                        renderRetryButton()
                    }.listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView("暂无备份", systemImage: "clock.arrow.circlepath")
                        .listRowBackground(Color.clear)
                }
            } else if !manager.working, let error = manager.error {
                Section {
                    Text(error).foregroundStyle(NativeAppearance.dangerText)
                    renderRetryButton()
                }
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("恢复备份").navigationBarTitleDisplayMode(.inline)
        .task { await manager.reload() }
        .refreshable { await manager.reload() }
        .sheet(item: $selected) { NativeBackupRestore(manager: manager, version: $0) }
    }
    private func renderRetryButton() -> some View {
        Button("重新读取备份") { Task { await manager.reload() } }
            .accessibilityIdentifier("backup-reload")
    }
    private func versionRow(_ version: NativeBackupVersion) -> some View {
        Button { selected = version } label: {
            HStack {
                Text(version.manifest.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                Spacer()
                if manager.waitingForUpload(version) { Image(systemName: "icloud.and.arrow.up").foregroundStyle(NativeAppearance.secondaryText).accessibilityLabel("等待上传") }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(NativeAppearance.secondaryText)
            }
        }.tint(.primary).accessibilityIdentifier("backup-version-" + version.id).disabled(manager.working)
    }
}

private struct NativeBackupRestore: View {
    @ObservedObject var manager: NativeCloudBackup
    @EnvironmentObject private var store: NativeStore
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
                if let error = manager.error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) } }
            }
            .labeledContentStyle(NativeReadableValueStyle())
            .navigationTitle("备份详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(manager.working) } }
            .interactiveDismissDisabled(manager.working)
            .alert("恢复这份备份？", isPresented: $confirming) {
                Button("恢复并替换", role: .destructive) { Task { if await manager.restore(version) { dismiss() } } }.accessibilityIdentifier("backup-restore-confirm")
                Button("取消", role: .cancel) {}
            } message: {
                Text(store.hasLoadedState
                     ? "当前本机数据将被替换，包括装备及类别、活动、记录、提醒、图片和附件。恢复前会保留本机现有数据。"
                     : "本机数据将被替换。恢复前会保留当前无法读取的数据文件。")
            }
        }
    }
}
