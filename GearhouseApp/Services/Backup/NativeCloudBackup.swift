import SwiftUI
import ImageIO
import CryptoKit
#if canImport(GearhouseCore)
import GearhouseCore
#endif

enum NativeBackupError: LocalizedError {
    case location, notCloud, downloading, busy
    var errorDescription: String? {
        switch self {
        case .location: return "无法访问备份文件夹，请重新选择。"
        case .notCloud: return "请选择 iCloud Drive 中的文件夹。"
        case .downloading: return "备份尚未下载完成，请连接网络后重试。"
        case .busy: return "正在备份或恢复，请完成后重试。"
        }
    }
}

struct NativeBackupVersion: Identifiable, Sendable {
    let manifest: GearBackupManifest
    let url: URL
    let uploaded: Bool
    let local: Bool
    var id: String { manifest.id }
}

/// All coordinated file access, image copying and validation happens off the UI actor.
actor NativeBackupWorker {
    private let fm = FileManager.default
    private func coordinated<T>(_ url: URL, write: Bool = false, options: NSFileCoordinator.WritingOptions = [], _ action: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?, result: Result<T, Error>?
        let coordinator = NSFileCoordinator()
        if write {
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in result = Result { try action(target) } }
        } else {
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { target in result = Result { try action(target) } }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw NativeBackupError.location }
        return try result.get()
    }
    func bookmark(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true else { throw NativeBackupError.notCloud }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    private func root(_ bookmark: Data, namespace: String) throws -> (scope: URL, folder: URL) {
        var stale = false
        let scope = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, scope.startAccessingSecurityScopedResource() else { throw NativeBackupError.location }
        let folder = scope.lastPathComponent == namespace ? scope : scope.appendingPathComponent(namespace, isDirectory: true)
        return (scope, folder)
    }
    func contentHash(_ state: Value) throws -> String {
        var fields = state.object
        for key in ["revision", "syncLog", "lastSync", "autoSync"] { fields.removeValue(forKey: key) }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(Value.object(fields))).map { String(format: "%02x", $0) }.joined()
    }
    func publish(state: Value, media: URL, work: URL, bookmark: Data, namespace: String) throws -> GearBackupManifest {
        let location = try root(bookmark, namespace: namespace)
        defer { location.scope.stopAccessingSecurityScopedResource() }
        try prepareWorkspace(work)
        let package = try GearBackupArchive.create(state: state, media: media, in: work)
        defer { try? fm.removeItem(at: package) }
        let manifest = try GearBackupArchive.manifest(at: package)
        try coordinated(location.scope, write: true) { _ in try fm.createDirectory(at: location.folder, withIntermediateDirectories: true) }
        let destination = location.folder.appendingPathComponent(package.lastPathComponent, isDirectory: true)
        try coordinated(destination, write: true) { target in
            let partial = location.folder.appendingPathComponent("." + manifest.id + ".partial", isDirectory: true)
            defer { try? fm.removeItem(at: partial) }
            try fm.copyItem(at: package, to: partial)
            try fm.moveItem(at: partial, to: target)
        }
        return manifest
    }
    private func uploaded(_ url: URL, manifest: GearBackupManifest) throws -> Bool {
        let files = [url.appendingPathComponent("manifest.json"), url.appendingPathComponent("state.json")]
            + manifest.photos.map { url.appendingPathComponent("media/" + $0.id + ".jpg") }
            + (manifest.attachments ?? []).map { url.appendingPathComponent("media/" + $0.fileName) }
        for file in files {
            let values: URLResourceValues
            do { values = try file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey]) }
            catch CocoaError.fileReadNoSuchFile {
                try? fm.startDownloadingUbiquitousItem(at: file)
                return false
            }
            if let error = values.ubiquitousItemUploadingError { throw error }
            guard values.isUbiquitousItem == true && values.ubiquitousItemIsUploaded == true else { return false }
        }
        return true
    }
    func versions(bookmark: Data, namespace: String) throws -> [NativeBackupVersion] {
        let location = try root(bookmark, namespace: namespace)
        defer { location.scope.stopAccessingSecurityScopedResource() }
        guard fm.fileExists(atPath: location.folder.path) else { return [] }
        return try coordinated(location.folder) { folder in
            var result: [NativeBackupVersion] = []
            for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isUbiquitousItemKey], options: .skipsHiddenFiles)
                where file.pathExtension == GearBackupArchive.fileExtension {
                let manifestURL = file.appendingPathComponent("manifest.json")
                if !fm.fileExists(atPath: manifestURL.path) {
                    try? fm.startDownloadingUbiquitousItem(at: file)
                    continue
                }
                guard let manifest = try? GearBackupArchive.manifest(at: file) else {
                    try? fm.startDownloadingUbiquitousItem(at: file)
                    continue
                }
                result.append(.init(manifest: manifest, url: file, uploaded: try uploaded(file, manifest: manifest), local: false))
            }
            return result.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        }
    }
    func prune(bookmark: Data, namespace: String, versions: [NativeBackupVersion]) throws -> Set<String> {
        guard versions.first?.uploaded == true else { return [] }
        let groups = Dictionary(grouping: versions, by: { $0.manifest.accountID ?? "" })
        let keep = groups.values.reduce(into: Set<String>()) { $0.formUnion(GearBackupArchive.retainedIDs($1.map(\.manifest))) }
        let location = try root(bookmark, namespace: namespace)
        defer { location.scope.stopAccessingSecurityScopedResource() }
        guard versions.contains(where: { $0.uploaded && !keep.contains($0.id) }) else { return [] }
        if let latest = versions.first { _ = try GearBackupArchive.validate(at: latest.url) }
        var removed = Set<String>()
        for version in versions where version.uploaded && !keep.contains(version.id) {
            let target = location.folder.appendingPathComponent(version.url.lastPathComponent)
            try coordinated(target, write: true, options: .forDeleting) { try fm.removeItem(at: $0) }
            removed.insert(version.id)
        }
        return removed
    }
    private func prepareWorkspace(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = url; try folder.setResourceValues(values)
    }
    func prepare(_ version: NativeBackupVersion, bookmark: Data?, namespace: String, work: URL) async throws -> (url: URL, state: Value) {
        let scope: URL?
        if version.local { scope = nil }
        else {
            guard let bookmark else { throw NativeBackupError.location }
            scope = try root(bookmark, namespace: namespace).scope
        }
        defer { scope?.stopAccessingSecurityScopedResource() }
        let source = version.url
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let manifest = version.manifest
        let cloudFile = (try? source.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        if !version.local || cloudFile {
            let files = [source, source.appendingPathComponent("state.json"), source.appendingPathComponent("manifest.json")]
                + manifest.photos.map { source.appendingPathComponent("media/" + $0.id + ".jpg") }
                + (manifest.attachments ?? []).map { source.appendingPathComponent("media/" + $0.fileName) }
            for attempt in 0..<60 {
                var ready = true
                for file in files {
                    let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if !fm.fileExists(atPath: file.path) || values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                        try? fm.startDownloadingUbiquitousItem(at: file); ready = false
                    }
                }
                if ready { break }
                guard attempt < 59 else { throw NativeBackupError.downloading }
                try await Task.sleep(for: .seconds(1))
            }
        }
        try prepareWorkspace(work)
        let copy = work.appendingPathComponent(UUID().uuidString + "." + GearBackupArchive.fileExtension)
        do {
            try coordinated(source) { try fm.copyItem(at: $0, to: copy) }
            let validated = try GearBackupArchive.validate(at: copy)
            guard validated.manifest == manifest else { throw DomainError("备份数据无效") }
            let engine = try NativeDomain()
            let normalized = try engine.execute(state: validated.state, action: "initialize")["state"]
            if !normalized["reminders"].isNull {
                let reminders = try JSONDecoder().decode([GearReminder].self, from: normalized["reminders"].jsonData())
                guard Set(reminders.map(\.id)).count == reminders.count else { throw DomainError("备份包含重复提醒") }
                for reminder in reminders { try reminder.validate() }
            }
            for photo in manifest.photos {
                guard let image = CGImageSourceCreateWithURL(copy.appendingPathComponent("media/" + photo.id + ".jpg") as CFURL, nil),
                      CGImageSourceGetCount(image) > 0 else { throw DomainError("备份图片校验失败") }
            }
            return (copy, normalized)
        } catch { try? fm.removeItem(at: copy); throw error }
    }
    func safety(state: Value, directory: URL) throws -> URL {
        try GearBackupArchive.create(state: state, media: directory.appendingPathComponent("media"), in: directory.appendingPathComponent("Recovery"))
    }
    func localVersions(_ directory: URL) -> [NativeBackupVersion] {
        let files = (try? fm.contentsOfDirectory(at: directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.compactMap { url in
            guard let manifest = try? GearBackupArchive.manifest(at: url) else { return nil }
            return NativeBackupVersion(manifest: manifest, url: url, uploaded: true, local: true)
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }
    func installMedia(from package: URL, state: Value, into directory: URL) throws -> [URL] {
        let folder = directory.appendingPathComponent("media")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var added: [URL] = []
        do {
            for photo in state["photos"].array {
                let target = folder.appendingPathComponent(photo.id + ".jpg")
                if fm.fileExists(atPath: target.path) {
                    guard try GearBackupArchive.hash(target) == photo["hash"].text else { throw DomainError("备份图片与本机同名图片冲突") }
                } else { try fm.copyItem(at: package.appendingPathComponent("media/" + photo.id + ".jpg"), to: target); added.append(target) }
            }
            for attachment in state["attachments"].array {
                let name = try GearAttachment.fileName(attachment), target = folder.appendingPathComponent(name)
                if fm.fileExists(atPath: target.path) {
                    guard try GearBackupArchive.hash(target) == attachment["hash"].text else { throw DomainError("备份附件与本机文件冲突，请重新选择备份。") }
                } else { try fm.copyItem(at: package.appendingPathComponent("media/" + name), to: target); added.append(target) }
            }
            return added
        } catch { for file in added { try? fm.removeItem(at: file) }; throw error }
    }
    func remove(_ urls: [URL]) { for url in urls { try? fm.removeItem(at: url) } }
}

@MainActor
final class NativeCloudBackup: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var versions: [NativeBackupVersion] = []
    @Published private(set) var localVersions: [NativeBackupVersion] = []
    @Published private(set) var lastBackup: Date?
    @Published private(set) var working = false
    @Published private(set) var uploading = false
    @Published private(set) var phase = ""
    @Published var error: String?
    private struct Settings: Codable { var enabled = false; var bookmark: Data?; var hash: String?; var queuedID: String? }
    private var settings: Settings
    private let settingsURL: URL
    private let directory: URL
    private let namespace: String
    private let worker = NativeBackupWorker()
    private weak var store: NativeStore?
    private var task: Task<Void, Never>?
    var hasLocation: Bool { settings.bookmark != nil }
    func waitingForUpload(_ version: NativeBackupVersion) -> Bool { !version.uploaded && version.id == settings.queuedID }
    init(directory: URL, isolated: Bool) {
        self.directory = directory
        namespace = isolated ? "Gearhouse QA Backups" : "Gearhouse Backups"
        settingsURL = directory.appendingPathComponent("cloud-backup-settings.json")
        do {
            settings = FileManager.default.fileExists(atPath: settingsURL.path)
                ? try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL)) : Settings()
        } catch {
            settings = Settings()
            self.error = "无法读取备份设置，请重新选择备份文件夹。"
        }
        enabled = settings.enabled
    }
    func attach(_ store: NativeStore) { self.store = store }
    private func saveSettings() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: settingsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func select(_ url: URL) async {
        guard !working else { return }
        working = true; phase = "正在访问 iCloud Drive…"
        let previous = settings
        defer { working = false; phase = "" }
        do {
            let bookmark = try await worker.bookmark(url)
            settings.bookmark = bookmark; settings.enabled = true; settings.hash = nil; settings.queuedID = nil
            try saveSettings(); enabled = true; error = nil
            versions = []; lastBackup = nil; uploading = false
        } catch { settings = previous; fail(error) }
        if enabled { changed(); store?.scheduleBackground() }
    }
    func setEnabled(_ value: Bool) {
        guard !working else { return }
        let previous = settings
        do {
            settings.enabled = value; try saveSettings(); enabled = value; error = nil
            task?.cancel(); task = nil
            if value { changed() }
            store?.scheduleBackground()
        } catch { settings = previous; fail(error) }
    }
    func changed() {
        guard enabled else { return }
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await self?.tick()
        }
    }
    func tick(force: Bool = false) async {
        guard enabled, !working, let store, !store.busy, !store.backupRestoring, let bookmark = settings.bookmark else { return }
        working = true; phase = "正在备份…"
        defer { working = false; phase = "" }
        do {
            let state = store.state
            let digest = try await worker.contentHash(state)
            let empty = state["gears"].array.isEmpty && state["activities"].array.isEmpty && state["gearEvents"].array.isEmpty
            if empty && settings.hash == nil {
                try await loadVersions(bookmark)
                if !versions.isEmpty { return }
            }
            if force || digest != settings.hash {
                let manifest = try await worker.publish(state: state, media: directory.appendingPathComponent("media"), work: directory.appendingPathComponent("BackupWork"), bookmark: bookmark, namespace: namespace)
                settings.hash = digest; settings.queuedID = manifest.id; try saveSettings()
            }
            try await loadVersions(bookmark)
            error = nil
        } catch { fail(error) }
    }
    private func loadVersions(_ bookmark: Data) async throws {
        let all = try await worker.versions(bookmark: bookmark, namespace: namespace)
        let account = store?.state["account"]["id"].text ?? ""
        versions = all.filter { account.isEmpty || ($0.manifest.accountID ?? "") == account }
        lastBackup = versions.first(where: \.uploaded)?.manifest.createdAt
        uploading = versions.contains(where: waitingForUpload)
        // Never expire recovery points until the latest package is safely in iCloud.
        if all.first?.uploaded == true {
            let removed = try await worker.prune(bookmark: bookmark, namespace: namespace, versions: all)
            versions.removeAll { removed.contains($0.id) }
        }
        localVersions = await worker.localVersions(directory)
        #if DEBUG
        if namespace == "Gearhouse QA Backups" {
            let evidence: Value = ["at":.string(NativeDate.now), "enabled":.bool(enabled), "versions":.array(versions.map {
                ["id":.string($0.id), "uploaded":.bool($0.uploaded), "stateHash":.string($0.manifest.stateHash),
                 "photos":.number(Double($0.manifest.photos.count)), "file":.string($0.url.lastPathComponent)]
            })]
            try? evidence.jsonData().write(to: directory.appendingPathComponent("cloud-backup-verification.json"), options: .atomic)
        }
        #endif
    }
    func reload() async {
        guard !working else { return }
        working = true; phase = "正在读取备份…"; defer { working = false; phase = "" }
        do {
            if let bookmark = settings.bookmark { try await loadVersions(bookmark) }
            else { localVersions = await worker.localVersions(directory) }
            error = nil
        } catch { fail(error) }
    }
    func restore(_ version: NativeBackupVersion) async -> Bool {
        guard !working, let store else { return false }
        working = true; phase = "正在恢复…"
        var locked = false
        var package: URL?, added: [URL] = []
        defer { if locked { store.endBackupRestore() }; working = false; phase = "" }
        do {
            let prepared = try await worker.prepare(version, bookmark: settings.bookmark, namespace: namespace, work: directory.appendingPathComponent("BackupWork"))
            package = prepared.url
            let current = try store.beginBackupRestore(); locked = true
            guard current["account"].isNull || current["account"]["id"].text == prepared.state["account"]["id"].text else { throw DomainError("备份属于其他 ICU 账户") }
            _ = try await worker.safety(state: current, directory: directory)
            added = try await worker.installMedia(from: prepared.url, state: prepared.state, into: directory)
            try store.applyRestoredBackup(prepared.state)
            await worker.remove([prepared.url]); package = nil; added = []
            localVersions = await worker.localVersions(directory)
            settings.hash = nil; try? saveSettings()
            error = nil
            return true
        } catch {
            await worker.remove(added + (package.map { [$0] } ?? []))
            fail(error); return false
        }
    }
    private func fail(_ failure: Error) {
        NSLog("Gearhouse backup failed: %@", failure.localizedDescription)
        let ns = failure as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUbiquitousFileNotUploadedDueToQuotaError {
            error = "iCloud 空间不足，请清理空间后重试。"
        } else if ns.domain == NSCocoaErrorDomain && ns.code == NSUbiquitousFileUbiquityServerNotAvailable {
            error = "暂时无法连接 iCloud，请稍后重试。"
        } else { error = (failure as? NativeBackupError)?.errorDescription ?? failure.userFacingMessage }
    }
}
