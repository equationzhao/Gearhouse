import Foundation
import CryptoKit

public struct GearBackupManifest: Codable, Equatable, Sendable, Identifiable {
    public struct Photo: Codable, Equatable, Sendable {
        public let id: String
        public let hash: String
        public let bytes: Int
    }
    public struct Attachment: Codable, Equatable, Sendable {
        public let id: String
        public let fileName: String
        public let hash: String
        public let bytes: Int
    }
    public let format: Int
    public let id: String
    public let createdAt: Date
    public let accountID: String?
    public let stateHash: String
    public let gears: Int
    public let activities: Int
    public let records: Int
    public let photos: [Photo]
    public var attachments: [Attachment]? = nil
}

/// File packages keep image bytes out of JSON and are published only after validation.
public enum GearBackupArchive {
    public static let fileExtension = "gearhousebackup"
    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func create(state: Value, media: URL, in directory: URL, at date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        try GearAttachment.validateRecords(in: state)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let partial = directory.appendingPathComponent("." + id + ".partial", isDirectory: true)
        let complete = directory.appendingPathComponent(id + "." + fileExtension, isDirectory: true)
        try fm.createDirectory(at: partial.appendingPathComponent("media"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: partial) }
        let stateFile = partial.appendingPathComponent("state.json")
        try state.jsonData().write(to: stateFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var photos: [GearBackupManifest.Photo] = [], seen = Set<String>()
        for photo in state["photos"].array {
            guard UUID(uuidString: photo.id) != nil, seen.insert(photo.id).inserted else { throw DomainError("备份图片标识无效") }
            let target = partial.appendingPathComponent("media/" + photo.id + ".jpg")
            try fm.copyItem(at: media.appendingPathComponent(photo.id + ".jpg"), to: target)
            let digest = try hash(target)
            guard digest == photo["hash"].text else { throw DomainError("备份图片校验失败") }
            let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            photos.append(.init(id: photo.id, hash: digest, bytes: size))
        }
        var attachments: [GearBackupManifest.Attachment] = []
        for row in state["attachments"].array {
            let name = try GearAttachment.fileName(row), source = media.appendingPathComponent(name)
            let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.fileSize == row["bytes"].integer else { throw DomainError("附件文件不完整，请重新添加后再备份。") }
            let target = partial.appendingPathComponent("media/" + name)
            try fm.copyItem(at: source, to: target)
            guard try hash(target) == row["hash"].text else { throw DomainError("附件校验失败，请重新添加后再备份。") }
            attachments.append(.init(id: row.id, fileName: name, hash: row["hash"].text, bytes: row["bytes"].integer))
        }
        var manifest = GearBackupManifest(format: 1, id: id, createdAt: date,
            accountID: state["account"]["id"].text.isEmpty ? nil : state["account"]["id"].text,
            stateHash: try hash(stateFile), gears: state["gears"].array.count,
            activities: state["activities"].array.count, records: state["events"].array.count + state["gearEvents"].array.count,
            photos: photos)
        if !attachments.isEmpty { manifest.attachments = attachments }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(manifest).write(to: partial.appendingPathComponent("manifest.json"), options: .atomic)
        try fm.moveItem(at: partial, to: complete)
        return complete
    }
    public static func manifest(at url: URL) throws -> GearBackupManifest {
        let file = url.appendingPathComponent("manifest.json")
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw DomainError("备份数据无效") }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 8 * 1024 * 1024 else { throw DomainError("备份数据无效") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let manifest = try decoder.decode(GearBackupManifest.self, from: Data(contentsOf: file))
        guard manifest.format == 1, UUID(uuidString: manifest.id) != nil else { throw DomainError("备份数据无效") }
        for attachment in manifest.attachments ?? [] {
            guard UUID(uuidString: attachment.id) != nil,
                  [attachment.id + ".pdf", attachment.id + ".jpg"].contains(attachment.fileName),
                  attachment.bytes > 0, attachment.bytes <= GearAttachment.maximumBytes else { throw DomainError("备份附件信息不完整，请重新选择完整备份。") }
        }
        return manifest
    }
    public static func validate(at url: URL) throws -> (manifest: GearBackupManifest, state: Value) {
        let manifest = try manifest(at: url), stateFile = url.appendingPathComponent("state.json")
        guard try stateFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try url.appendingPathComponent("media").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw DomainError("备份数据无效") }
        let size = try stateFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 500 * 1024 * 1024, try hash(stateFile) == manifest.stateHash else { throw DomainError("备份数据无效") }
        let state = try Value.decode(Data(contentsOf: stateFile))
        try GearAttachment.validateRecords(in: state)
        guard case .array = state["gears"], case .array = state["events"], case .array = state["activities"],
              manifest.accountID == (state["account"]["id"].text.isEmpty ? nil : state["account"]["id"].text),
              manifest.gears == state["gears"].array.count, manifest.activities == state["activities"].array.count,
              manifest.records == state["events"].array.count + state["gearEvents"].array.count,
              manifest.photos.count == state["photos"].array.count,
              (manifest.attachments ?? []).count == state["attachments"].array.count else { throw DomainError("备份数据无效") }
        var seen = Set<String>()
        for photo in manifest.photos {
            guard UUID(uuidString: photo.id) != nil, seen.insert(photo.id).inserted,
                  let record = state["photos"].array.first(where: { $0.id == photo.id }), record["hash"].text == photo.hash,
                  photo.bytes > 0, photo.bytes <= 10 * 1024 * 1024 else { throw DomainError("备份图片标识无效") }
            let file = url.appendingPathComponent("media/" + photo.id + ".jpg")
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.fileSize == photo.bytes, try hash(file) == photo.hash else { throw DomainError("备份图片校验失败") }
        }
        var seenAttachments = Set<String>()
        for attachment in manifest.attachments ?? [] {
            guard seenAttachments.insert(attachment.id).inserted,
                  let row = state["attachments"].array.first(where: { $0.id == attachment.id }),
                  try GearAttachment.fileName(row) == attachment.fileName,
                  row["hash"].text == attachment.hash, row["bytes"].integer == attachment.bytes else { throw DomainError("备份附件信息不完整，请重新选择完整备份。") }
            let file = url.appendingPathComponent("media/" + attachment.fileName)
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.fileSize == attachment.bytes,
                  try hash(file) == attachment.hash else { throw DomainError("备份附件校验失败，请重新选择完整备份。") }
        }
        return (manifest, state)
    }
    /// Keep recent versions plus daily and weekly recovery points. Call only after upload succeeds.
    public static func retainedIDs(_ manifests: [GearBackupManifest], now: Date = Date()) -> Set<String> {
        let sorted = manifests.sorted { $0.createdAt > $1.createdAt }
        var kept = Set(sorted.prefix(3).map(\.id)), days = Set<Date>(), weeks = Set<Date>()
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for item in sorted {
            let age = now.timeIntervalSince(item.createdAt)
            let day = calendar.startOfDay(for: item.createdAt)
            if age >= 0 && age < 7 * 86400 && days.count < 7 && days.insert(day).inserted { kept.insert(item.id) }
            if age >= 0 && age < 28 * 86400, weeks.count < 4, let week = calendar.dateInterval(of: .weekOfYear, for: item.createdAt)?.start,
               weeks.insert(week).inserted { kept.insert(item.id) }
        }
        return kept
    }
}
