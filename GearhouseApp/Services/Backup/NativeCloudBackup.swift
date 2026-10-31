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

enum NativeBackupUploadFailure: Sendable {
    case quota, unavailable
    init?(_ failure: Error) {
        let error = failure as NSError
        guard error.domain == NSCocoaErrorDomain else { return nil }
        switch error.code {
        case NSUbiquitousFileNotUploadedDueToQuotaError: self = .quota
        case NSUbiquitousFileUbiquityServerNotAvailable: self = .unavailable
        default: return nil
        }
    }
    var message: String {
        switch self {
        case .quota: return "iCloud 空间不足，请清理空间后重试。"
        case .unavailable: return "暂时无法连接 iCloud，请稍后重试。"
        }
    }
}

struct NativeBackupVersionScan: Sendable {
    let versions: [NativeBackupVersion]
    let pendingCount: Int
    let unreadableCount: Int
    let discoveredCount: Int
    var uploadFailure: NativeBackupUploadFailure? = nil
    var complete: Bool { pendingCount == 0 && unreadableCount == 0 }
    var readMessage: String? {
        if let uploadFailure { return uploadFailure.message }
        switch (pendingCount > 0, unreadableCount > 0) {
        case (true, false): return "有备份尚未下载完成，请稍后重新读取。"
        case (false, true): return "有备份无法读取，请重新读取或选择其他备份。"
        case (true, true): return "有备份尚未下载完成，另有备份无法读取。请稍后重新读取或选择其他备份。"
        default: return nil
        }
    }
}

enum NativeBackupFileSelection: Sendable {
    case json(Data)
    case package(NativeBackupVersion)
}

enum NativeBackupFiles {
    static let maximumJSONBytes = 500 * 1024 * 1024
    private static let exportSizeMessage = "备份文件过大，无法导出为 JSON。请使用 iCloud Drive 自动备份。"

    static func prepareExport(state: Value, media: URL) async throws -> Data {
        try await prepareExport(state: state, media: media, maximumBytes: maximumJSONBytes, beforeRead: nil)
    }
    static func readSelection(from url: URL) async throws -> NativeBackupFileSelection {
        try await readSelection(from: url, maximumBytes: maximumJSONBytes, beforeRead: nil)
    }
    static func validateJSONSize(_ count: Int, exporting: Bool = false) throws {
        try validateJSONSize(count, maximumBytes: maximumJSONBytes, exporting: exporting)
    }
    private static func validateJSONSize(_ count: Int, maximumBytes: Int, exporting: Bool) throws {
        guard count >= 0, count < maximumBytes else { throw DomainError(exporting ? exportSizeMessage : "备份过大") }
    }
    private static func coordinatedRead<T>(_ url: URL, _ action: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?, result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { target in
            result = Result { try action(target) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw NativeBackupError.location }
        return try result.get()
    }
    private static func joinWorker<T: Sendable>(_ worker: Task<T, Error>) async throws -> T {
        let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return value
    }
    private static func prepareExport(state: Value, media: URL, maximumBytes: Int,
                                      beforeRead: (@Sendable (URL) async throws -> Void)?) async throws -> Data {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) { () async throws -> Data in
            try Task.checkCancellation()
            var photos: [String: Value] = [:], attachments: [String: Value] = [:]
            var encodedMediaBytes = 0
            func reserveEncodedBytes(_ bytes: Data) throws {
                try validateJSONSize(bytes.count, maximumBytes: maximumBytes, exporting: true)
                encodedMediaBytes += 4 * ((bytes.count + 2) / 3)
                try validateJSONSize(encodedMediaBytes, maximumBytes: maximumBytes, exporting: true)
            }
            for photo in state["photos"].array {
                try Task.checkCancellation()
                guard UUID(uuidString: photo.id) != nil else { throw DomainError("备份图片标识无效") }
                let file = media.appendingPathComponent(photo.id + ".jpg")
                try await beforeRead?(file)
                try Task.checkCancellation()
                let bytes = try coordinatedRead(file) { try Data(contentsOf: $0) }
                try Task.checkCancellation()
                try reserveEncodedBytes(bytes)
                photos[photo.id] = .string(bytes.base64EncodedString())
            }
            for record in state["attachments"].array {
                try Task.checkCancellation()
                let file = media.appendingPathComponent(try GearAttachment.fileName(record))
                try await beforeRead?(file)
                try Task.checkCancellation()
                let bytes = try coordinatedRead(file) { try Data(contentsOf: $0) }
                try Task.checkCancellation()
                try reserveEncodedBytes(bytes)
                attachments[record.id] = .string(bytes.base64EncodedString())
            }
            try Task.checkCancellation()
            let data = try Value.object(["state": state, "media": .object(photos), "attachments": .object(attachments)]).jsonData()
            try validateJSONSize(data.count, maximumBytes: maximumBytes, exporting: true)
            try Task.checkCancellation()
            return data
        }
        return try await joinWorker(worker)
    }
    private static func readSelection(from url: URL, maximumBytes: Int,
                                       beforeRead: (@Sendable (URL) async throws -> Void)?) async throws -> NativeBackupFileSelection {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) { () async throws -> NativeBackupFileSelection in
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let package = url.pathExtension.lowercased() == GearBackupArchive.fileExtension
            if !package {
                try coordinatedRead(url) { target in
                    var file = target; file.removeAllCachedResourceValues()
                    try validateJSONSize(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, maximumBytes: maximumBytes, exporting: false)
                }
            }
            try await beforeRead?(url)
            try Task.checkCancellation()
            return try coordinatedRead(url) { target in
                try Task.checkCancellation()
                if package {
                    let manifest = try GearBackupArchive.manifest(at: target)
                    try Task.checkCancellation()
                    return .package(NativeBackupVersion(manifest: manifest, url: url, uploaded: false, local: true))
                }
                var file = target; file.removeAllCachedResourceValues()
                try validateJSONSize(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, maximumBytes: maximumBytes, exporting: false)
                let data = try Data(contentsOf: file)
                try validateJSONSize(data.count, maximumBytes: maximumBytes, exporting: false)
                try Task.checkCancellation()
                return .json(data)
            }
        }
        return try await joinWorker(worker)
    }
    #if DEBUG
    static func prepareExport(state: Value, media: URL, beforeRead: (@Sendable (URL) async throws -> Void)?,
                              maximumBytes: Int = maximumJSONBytes) async throws -> Data {
        precondition(maximumBytes > 0 && maximumBytes <= maximumJSONBytes)
        return try await prepareExport(state: state, media: media, maximumBytes: maximumBytes, beforeRead: beforeRead)
    }
    static func readSelection(from url: URL, beforeRead: (@Sendable (URL) async throws -> Void)?,
                              maximumBytes: Int = maximumJSONBytes) async throws -> NativeBackupFileSelection {
        precondition(maximumBytes > 0 && maximumBytes <= maximumJSONBytes)
        return try await readSelection(from: url, maximumBytes: maximumBytes, beforeRead: beforeRead)
    }
    #endif
}

/// All coordinated file access, image copying and validation happens off the UI actor.
enum NativeBackupSafety {
    private struct Medium {
        let name: String
        let hash: String
        let bytes: Int?
        let attachment: Bool
    }
    private static func readAttributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch {
            let failure = error as NSError
            let missing = failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code)
                || failure.domain == NSPOSIXErrorDomain && failure.code == Int(POSIXErrorCode.ENOENT.rawValue)
            guard missing else { throw error }
            return nil
        }
    }
    private static func requireRegularFile(_ attributes: [FileAttributeKey: Any]) throws {
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw DomainError("无法保留本机原文件，请检查存储空间后重试恢复。")
        }
    }
    private static func readMediaFiles(_ directory: URL) throws -> [URL] {
        guard let attributes = try readAttributes(directory) else { return [] }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw DomainError("无法保留本机原文件，请检查存储空间后重试恢复。")
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            guard let attributes = try readAttributes(file) else { throw NativeBackupError.location }
            try requireRegularFile(attributes)
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    /// Incomplete or unreadable local media can be preserved as originals, never as a restorable package.
    static func preserveBeforeRestore(state: Value, directory: URL) throws -> URL {
        let fm = FileManager.default, media = directory.appendingPathComponent("media")
        try GearAttachment.validateRecords(in: state)
        var references: [Medium] = [], names = Set<String>()
        for photo in state["photos"].array {
            guard UUID(uuidString: photo.id) != nil, names.insert(photo.id + ".jpg").inserted else { throw DomainError("备份图片标识无效") }
            references.append(.init(name: photo.id + ".jpg", hash: photo["hash"].text, bytes: nil, attachment: false))
        }
        for attachment in state["attachments"].array {
            let name = try GearAttachment.fileName(attachment)
            guard names.insert(name).inserted else { throw DomainError("备份数据无效") }
            references.append(.init(name: name, hash: attachment["hash"].text, bytes: attachment["bytes"].integer, attachment: true))
        }
        if let attributes = try readAttributes(media) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw DomainError("无法保留本机原文件，请检查存储空间后重试恢复。")
            }
        }
        var needsOriginalCopy = false
        for reference in references {
            let file = media.appendingPathComponent(reference.name)
            if let attributes = try readAttributes(file) {
                try requireRegularFile(attributes)
                if !reference.attachment {
                    if let image = CGImageSourceCreateWithURL(file as CFURL, nil) {
                        if CGImageSourceGetCount(image) == 0 { needsOriginalCopy = true }
                    } else { needsOriginalCopy = true }
                }
            } else { needsOriginalCopy = true }
        }
        if !needsOriginalCopy {
            return try GearBackupArchive.create(state: state, media: media, in: directory.appendingPathComponent("Recovery"))
        }
        let source = directory.appendingPathComponent("state-v2.json")
        guard let attributes = try readAttributes(source) else { throw NativeBackupError.location }
        try requireRegularFile(attributes)
        let bytes = try Data(contentsOf: source)
        guard try Value.decode(bytes) == state else { throw NativeBackupError.location }
        let files = try readMediaFiles(media)
        let original = directory.appendingPathComponent("Recovery/Original-" + UUID().uuidString.lowercased(), isDirectory: true)
        do {
            let copies = original.appendingPathComponent("media", isDirectory: true)
            try fm.createDirectory(at: copies, withIntermediateDirectories: true)
            let savedState = original.appendingPathComponent("state-v2.json")
            try bytes.write(to: savedState, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            for file in files {
                let digest = try GearBackupArchive.hash(file)
                if let reference = references.first(where: { $0.name == file.lastPathComponent }) {
                    if let count = reference.bytes {
                        guard (try readAttributes(file))?[.size] as? NSNumber == NSNumber(value: count) else { throw DomainError("附件文件不完整，请重新添加后再备份。") }
                    }
                    guard digest == reference.hash else {
                        throw DomainError(reference.attachment ? "附件校验失败，请重新添加后再备份。" : "备份图片校验失败")
                    }
                }
                let destination = copies.appendingPathComponent(file.lastPathComponent)
                try fm.copyItem(at: file, to: destination)
                guard try GearBackupArchive.hash(destination) == digest, try GearBackupArchive.hash(file) == digest else { throw NativeBackupError.location }
            }
            guard try Data(contentsOf: savedState) == bytes, try Data(contentsOf: source) == bytes,
                  try readMediaFiles(media).map(\.lastPathComponent) == files.map(\.lastPathComponent) else { throw NativeBackupError.location }
            for file in files {
                guard try GearBackupArchive.hash(file) == GearBackupArchive.hash(copies.appendingPathComponent(file.lastPathComponent)) else { throw NativeBackupError.location }
            }
            return original
        } catch {
            try? fm.removeItem(at: original)
            throw error
        }
    }
}

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
    func versions(bookmark: Data, namespace: String) throws -> NativeBackupVersionScan {
        let location = try root(bookmark, namespace: namespace)
        defer { location.scope.stopAccessingSecurityScopedResource() }
        guard fm.fileExists(atPath: location.folder.path) else { return .init(versions: [], pendingCount: 0, unreadableCount: 0, discoveredCount: 0) }
        return try coordinated(location.folder) { folder in
            try scanVersions(in: folder, isPending: manifestIsPending, requestDownload: requestManifestDownload)
        }
    }
    private func manifestIsPending(_ package: URL) -> Bool {
        for original in [package, package.appendingPathComponent("manifest.json")] {
            var file = original; file.removeAllCachedResourceValues()
            let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey])
            if values?.ubiquitousItemDownloadingStatus == .notDownloaded || values?.ubiquitousItemIsDownloading == true { return true }
        }
        return false
    }
    private func requestManifestDownload(_ package: URL) {
        try? fm.startDownloadingUbiquitousItem(at: package)
        try? fm.startDownloadingUbiquitousItem(at: package.appendingPathComponent("manifest.json"))
    }
    private func scanVersions(in folder: URL, isPending: (URL) -> Bool, requestDownload: (URL) -> Void,
                              uploadStatus: ((URL, GearBackupManifest) throws -> Bool)? = nil) throws -> NativeBackupVersionScan {
        guard fm.fileExists(atPath: folder.path) else { return .init(versions: [], pendingCount: 0, unreadableCount: 0, discoveredCount: 0) }
        var result: [NativeBackupVersion] = []
        var pending = 0, unreadable = 0, discovered = 0
        var uploadFailure: NativeBackupUploadFailure?
        for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isUbiquitousItemKey], options: .skipsHiddenFiles)
            where file.pathExtension == GearBackupArchive.fileExtension {
            discovered += 1
            if isPending(file) {
                pending += 1; requestDownload(file)
                continue
            }
            do {
                let manifest = try GearBackupArchive.manifest(at: file)
                let wasUploaded: Bool
                do { wasUploaded = try uploadStatus?(file, manifest) ?? uploaded(file, manifest: manifest) }
                catch {
                    unreadable += 1; wasUploaded = false
                    if uploadFailure == nil { uploadFailure = NativeBackupUploadFailure(error) }
                    NSLog("Gearhouse backup upload status could not be read: %@", error.localizedDescription)
                }
                result.append(.init(manifest: manifest, url: file, uploaded: wasUploaded, local: false))
            } catch {
                unreadable += 1
                NSLog("Gearhouse backup manifest could not be read: %@", error.localizedDescription)
            }
        }
        return .init(versions: result.sorted { $0.manifest.createdAt > $1.manifest.createdAt }, pendingCount: pending, unreadableCount: unreadable, discoveredCount: discovered, uploadFailure: uploadFailure)
    }
    #if DEBUG
    func scanVersionsForTesting(in folder: URL, pendingPackages: Set<String> = [],
                                uploadStatus: (@Sendable (URL, GearBackupManifest) throws -> Bool)? = nil) throws -> (scan: NativeBackupVersionScan, requestedDownloads: [String]) {
        var requested: [String] = []
        let scan = try scanVersions(in: folder, isPending: { pendingPackages.contains($0.lastPathComponent) }, requestDownload: { requested.append($0.lastPathComponent) }, uploadStatus: uploadStatus)
        return (scan, requested)
    }
    #endif
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
        try NativeBackupSafety.preserveBeforeRestore(state: state, directory: directory)
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
    #if DEBUG
    var readVersionsForTesting: (() async throws -> NativeBackupVersionScan)?
    #endif
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
        guard enabled, store?.hasLoadedState == true else { return }
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await self?.tick()
        }
    }
    func tick(force: Bool = false) async {
        guard enabled, !working, let store, store.hasLoadedState, !store.busy, !store.backupRestoring, let bookmark = settings.bookmark else { return }
        working = true; phase = "正在备份…"
        defer { working = false; phase = "" }
        do {
            let state = store.state
            let digest = try await worker.contentHash(state)
            let empty = state["gears"].array.isEmpty && state["activities"].array.isEmpty && state["gearEvents"].array.isEmpty
            if empty && settings.hash == nil {
                let scan = try await loadVersions(bookmark)
                if !versions.isEmpty || !scan.complete { return }
            }
            if force || digest != settings.hash {
                let manifest = try await worker.publish(state: state, media: directory.appendingPathComponent("media"), work: directory.appendingPathComponent("BackupWork"), bookmark: bookmark, namespace: namespace)
                settings.hash = digest; settings.queuedID = manifest.id; try saveSettings()
            }
            _ = try await loadVersions(bookmark)
        } catch { fail(error) }
    }
    private func loadVersions(_ bookmark: Data) async throws -> NativeBackupVersionScan {
        localVersions = await worker.localVersions(directory)
        let scan: NativeBackupVersionScan
        #if DEBUG
        if let readVersionsForTesting { scan = try await readVersionsForTesting() }
        else { scan = try await worker.versions(bookmark: bookmark, namespace: namespace) }
        #else
        scan = try await worker.versions(bookmark: bookmark, namespace: namespace)
        #endif
        let all = scan.versions
        let account = store?.state["account"]["id"].text ?? ""
        versions = all.filter { account.isEmpty || ($0.manifest.accountID ?? "") == account }
        lastBackup = versions.first(where: \.uploaded)?.manifest.createdAt
        uploading = versions.contains(where: waitingForUpload)
        // Never expire recovery points until the latest package is safely in iCloud.
        if store?.hasLoadedState == true && scan.complete && all.first?.uploaded == true {
            let removed = try await worker.prune(bookmark: bookmark, namespace: namespace, versions: all)
            versions.removeAll { removed.contains($0.id) }
        }
        #if DEBUG
        if namespace == "Gearhouse QA Backups" {
            let evidence: Value = ["at":.string(NativeDate.now), "enabled":.bool(enabled), "versions":.array(versions.map {
                ["id":.string($0.id), "uploaded":.bool($0.uploaded), "stateHash":.string($0.manifest.stateHash),
                 "photos":.number(Double($0.manifest.photos.count)), "file":.string($0.url.lastPathComponent)]
            })]
            try? evidence.jsonData().write(to: directory.appendingPathComponent("cloud-backup-verification.json"), options: .atomic)
        }
        #endif
        error = scan.readMessage
        return scan
    }
    func reload() async {
        guard !working else { return }
        working = true; phase = "正在读取备份…"; defer { working = false; phase = "" }
        do {
            if let bookmark = settings.bookmark { _ = try await loadVersions(bookmark) }
            else { localVersions = await worker.localVersions(directory); error = nil }
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
            let hadLoadedState = store.hasLoadedState
            let current = try store.beginBackupRestore(); locked = true
            guard current["account"].isNull || current["account"]["id"].text == prepared.state["account"]["id"].text else { throw DomainError("备份属于其他 ICU 账户") }
            if hadLoadedState { _ = try await worker.safety(state: current, directory: directory) }
            else { try store.preserveLocalSource() }
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
        error = NativeBackupUploadFailure(failure)?.message ?? (failure as? NativeBackupError)?.errorDescription ?? failure.userFacingMessage
    }
}
