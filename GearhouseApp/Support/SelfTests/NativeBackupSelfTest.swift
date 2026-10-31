#if DEBUG
import UIKit
#if canImport(GearhouseCore)
import GearhouseCore
#endif

private final class NativeStartupAccountProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var account = ""
    private static var requests = 0
    static func configure(account: String) { lock.lock(); defer { lock.unlock() }; self.account = account; requests = 0 }
    static func readRequests() -> Int { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; let account = Self.account; Self.lock.unlock()
        guard request.url?.path == "/api/v1/athlete/0", let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return
        }
        let value: Value = ["id":.string(account), "name":"Synthetic verified account"]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? value.jsonData()) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class NativeBackupSyncProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "X-Gearhouse-Fixture")
        if scenario == "unavailable" {
            sendResponse(status: 503, value: [:])
        } else if scenario == "partial", request.url?.path.hasSuffix("/gear") == true {
            sendResponse(status: 200, value: [])
        } else if scenario == "partial", URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "oldest" })?.value == "2026-01-01" {
            sendResponse(status: 200, value: [["id":"cancelled-sync-ride", "name":"Fixture Ride", "start_date_local":"2026-01-02T12:00:00", "type":"Ride", "distance":1000, "moving_time":60]])
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        }
    }
    private func sendResponse(status: Int, value: Value) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? value.jsonData()) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class NativeDelayedSyncProtocol: URLProtocol {
    private struct Fixture {
        let firstDay: String
        let holdCatalog: Bool
        var holdReads = true
        var held: [UUID: NativeDelayedSyncProtocol] = [:]
        var stopped = 0
    }
    private static let lock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    private let deliveryLock = NSRecursiveLock()
    private let requestID = UUID()
    private var stopped = false
    private var held = false
    private var token: String { request.value(forHTTPHeaderField: "X-Gearhouse-Cancel-Fixture") ?? "" }
    static func registerFixture(_ token: String, firstDay: String, holdCatalog: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        fixtures[token] = Fixture(firstDay: firstDay, holdCatalog: holdCatalog)
    }
    static func removeFixture(_ token: String) {
        lock.lock(); defer { lock.unlock() }
        fixtures[token] = nil
    }
    static func readReceipt(_ token: String) -> Value {
        lock.lock(); defer { lock.unlock() }
        return ["held":.number(Double(fixtures[token]?.held.count ?? 0)), "stopped":.number(Double(fixtures[token]?.stopped ?? 0))]
    }
    static func releaseReads(_ token: String) {
        lock.lock()
        let waiting = fixtures[token].map { Array($0.held.values) } ?? []
        fixtures[token]?.held = [:]
        fixtures[token]?.holdReads = false
        lock.unlock()
        for request in waiting {
            if request.request.url?.path.hasSuffix("/gear") == true { request.sendResponse([]) }
            else { request.sendActivities() }
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        guard !stopped else { return }
        Self.lock.lock()
        guard let fixture = Self.fixtures[token] else {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let path = request.url?.path ?? ""
        let holdCatalog = path.hasSuffix("/gear") && fixture.holdCatalog
        let holdActivities = path.hasSuffix("/activities") && readOldestDay() != fixture.firstDay
        if fixture.holdReads && (holdCatalog || holdActivities) {
            held = true
            Self.fixtures[token]?.held[requestID] = self
            Self.lock.unlock()
            return
        }
        Self.lock.unlock()
        if path.hasSuffix("/gear") { sendResponse([]) }
        else if path.hasSuffix("/activities") { sendActivities() }
        else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    }
    override func stopLoading() {
        deliveryLock.lock()
        stopped = true
        let wasHeld = held; held = false
        deliveryLock.unlock()
        Self.lock.lock(); defer { Self.lock.unlock() }
        Self.fixtures[token]?.held[requestID] = nil
        if wasHeld { Self.fixtures[token]?.stopped += 1 }
    }
    private func readOldestDay() -> String {
        guard let url = request.url else { return "" }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "oldest" }?.value ?? ""
    }
    private func sendActivities() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        guard !stopped else { return }
        held = false
        let day = readOldestDay()
        Self.lock.lock()
        let first = Self.fixtures[token]?.firstDay == day
        Self.lock.unlock()
        sendResponse([["id":.string(first ? "sync-cancel-saved-batch" : "sync-cancel-finished-batch"),
                       "name":.string(first ? "已读取的测试活动" : "后续测试活动"), "start_date_local":.string(day + "T00:00:00"),
                       "type":"Ride", "distance":1000, "moving_time":60]])
    }
    private func sendResponse(_ value: Value) {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        guard !stopped, let url = request.url else { return }
        held = false
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? value.jsonData()) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class NativeSyncCancellationFixture {
    let store: NativeStore
    let initialStatus: Value
    let secondDay: String
    private let token: String
    private let session: URLSession
    init(directory: URL, automatic: Bool, preserving: Bool = false, holdingCatalog: Bool = false) throws {
        let token = UUID().uuidString
        self.token = token
        let firstDay = NativeDate.shift(NativeDate.today, -31)
        secondDay = NativeDate.today
        NativeDelayedSyncProtocol.registerFixture(token, firstDay: firstDay, holdCatalog: holdingCatalog)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeDelayedSyncProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Gearhouse-Cancel-Fixture": token]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        self.session = session
        let fixture = NativeStore(directory: directory, secretStore: MemorySecretStore("fixture-delayed-sync-key"), session: session)
        do {
            if !preserving || fixture.state["account"].isNull {
                try fixture.commit("account", ["id":"sync-cancel-fixture-athlete", "name":"同步测试"])
                try fixture.commit("sync-settings", ["enabled":.bool(automatic), "failures":2, "error":.null,
                                                    "lastSuccess":"2024-01-01T00:00:00Z", "nextAt":.null, "resume":["next":.string(firstDay)]])
            }
        } catch {
            session.invalidateAndCancel(); NativeDelayedSyncProtocol.removeFixture(token); throw error
        }
        store = fixture
        initialStatus = fixture.state["autoSync"]
    }
    func readReceipt() -> Value { NativeDelayedSyncProtocol.readReceipt(token) }
    func releaseReads() { NativeDelayedSyncProtocol.releaseReads(token) }
    func close() {
        store.cancelSync()
        session.invalidateAndCancel()
        NativeDelayedSyncProtocol.removeFixture(token)
    }
    func readCancellationResult() -> Value {
        let status = store.state["autoSync"], receipt = readReceipt()
        return ["busy":.bool(store.busy), "stopping":.bool(store.stoppingSync), "progress":.string(store.progress),
                "failuresUnchanged":.bool(status["failures"] == initialStatus["failures"]),
                "successUnchanged":.bool(status["lastSuccess"] == initialStatus["lastSuccess"]),
                "backoffUnchanged":.bool(status["nextAt"] == initialStatus["nextAt"]),
                "errorUnchanged":.bool(status["error"] == initialStatus["error"] && store.error == nil),
                "savedBatchPresent":.bool(store.state["activities"].array.contains { $0.id == "sync-cancel-saved-batch" }),
                "pendingBatchAbsent":.bool(!store.state["activities"].array.contains { $0.id == "sync-cancel-finished-batch" }),
                "resumeAtPendingBatch":.bool(status["resume"]["next"].text == secondDay),
                "held":receipt["held"], "stopped":receipt["stopped"]]
    }
}

private actor NativeBackupFileReadGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private(set) var onMainThread = false
    static func readMainThread() -> Bool { Thread.isMainThread }
    func pause(onMainThread: Bool) async {
        guard !released else { return }
        self.onMainThread = onMainThread; entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume(); continuation = nil
    }
}

@MainActor
enum NativeBackupSelfTest {
    private static func checkMissingMediaRecovery(_ seed: NativeStore, check: (Bool, String) throws -> Void) async throws {
        let fm = FileManager.default, root = seed.directory.appendingPathComponent("MissingMediaRecovery")
        let json = try seed.exportBackup(), full = try Value.decode(json)
        guard let photo = seed.state["photos"].array.first, let attachment = seed.state["attachments"].array.first,
              let gear = seed.state["gears"].array.first else { throw DomainError("Missing media recovery fixture incomplete") }
        let photoName = photo.id + ".jpg", attachmentName = try GearAttachment.fileName(attachment)
        let package = try GearBackupArchive.create(state: seed.state, media: seed.directory.appendingPathComponent("media"), in: root.appendingPathComponent("Packages"))
        let manifest = try GearBackupArchive.manifest(at: package)
        let invalidPackage = root.appendingPathComponent("Invalid." + GearBackupArchive.fileExtension)
        try fm.copyItem(at: package, to: invalidPackage)
        try Data("invalid incoming state".utf8).write(to: invalidPackage.appendingPathComponent("state.json"))
        var invalidJSON = full; invalidJSON["media"][photo.id] = "invalid image"
        func restore(_ store: NativeStore, mode: String, invalid: Bool = false) async -> Bool {
            if mode == "json" {
                do { try store.importBackup(invalid ? invalidJSON.jsonData() : json); return true }
                catch { return false }
            }
            return await store.cloudBackup.restore(.init(manifest: manifest, url: invalid ? invalidPackage : package, uploaded: true, local: true))
        }
        func readMedia(_ directory: URL) throws -> [String: Data] {
            let media = directory.appendingPathComponent("media")
            guard fm.fileExists(atPath: media.path) else { return [:] }
            return try Dictionary(uniqueKeysWithValues: fm.contentsOfDirectory(at: media, includingPropertiesForKeys: nil).map {
                ($0.lastPathComponent, try Data(contentsOf: $0))
            })
        }
        func readOriginals(_ directory: URL) throws -> [URL] {
            let recovery = directory.appendingPathComponent("Recovery")
            guard fm.fileExists(atPath: recovery.path) else { return [] }
            return try fm.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Original-") }
        }
        func sameLibrary(_ lhs: Value, _ rhs: Value) -> Bool {
            var left = lhs.object, right = rhs.object
            left.removeValue(forKey: "revision"); right.removeValue(forKey: "revision")
            return left == right
        }
        let unreadableRoot = root.appendingPathComponent("UnreadableLocalPhoto")
        try fm.createDirectory(at: unreadableRoot, withIntermediateDirectories: true)
        try fm.copyItem(at: seed.directory.appendingPathComponent("media"), to: unreadableRoot.appendingPathComponent("media"))
        let unreadablePhoto = unreadableRoot.appendingPathComponent("media/" + photoName)
        let badImage = Data([0xff, 0xd8, 0xff, 0xd9])
        try badImage.write(to: unreadablePhoto)
        var unreadableState = seed.state, badRecord = photo
        badRecord["hash"] = .string(try GearBackupArchive.hash(unreadablePhoto))
        unreadableState["photos"] = [badRecord]
        let unreadableBytes = try unreadableState.jsonData()
        try unreadableBytes.write(to: unreadableRoot.appendingPathComponent("state-v2.json"))
        let preserved = try NativeBackupSafety.preserveBeforeRestore(state: unreadableState, directory: unreadableRoot)
        try check(preserved.lastPathComponent.hasPrefix("Original-") &&
                  (try Data(contentsOf: preserved.appendingPathComponent("state-v2.json"))) == unreadableBytes &&
                  (try Data(contentsOf: preserved.appendingPathComponent("media/" + photoName))) == badImage &&
                  !fm.fileExists(atPath: preserved.appendingPathComponent("manifest.json").path),
                  "unreadableLocalPhotoPreservesExactOriginalWithoutPublishingPackage")
        try Data("different".utf8).write(to: unreadablePhoto)
        var mismatchedRejected = false
        do { _ = try NativeBackupSafety.preserveBeforeRestore(state: unreadableState, directory: unreadableRoot) }
        catch { mismatchedRejected = true }
        try check(mismatchedRejected && (try readOriginals(unreadableRoot)).count == 1,
                  "unreadableLocalPhotoStillRejectsHashMismatch")
        try badImage.write(to: unreadablePhoto)
        let unreadableStore = NativeStore(directory: unreadableRoot, secretStore: MemorySecretStore())
        let beforeRestoreBytes = try Data(contentsOf: unreadableRoot.appendingPathComponent("state-v2.json"))
        var replacement = full, replacementState = seed.state
        replacementState["photos"] = []
        replacement["state"] = replacementState; replacement["media"] = [:]
        try unreadableStore.importBackup(replacement.jsonData())
        let copies = try readOriginals(unreadableRoot)
        try check(unreadableStore.hasLoadedState && unreadableStore.state["photos"].array.isEmpty && copies.count == 2 &&
                  copies.contains { (try? Data(contentsOf: $0.appendingPathComponent("state-v2.json"))) == beforeRestoreBytes &&
                    (try? Data(contentsOf: $0.appendingPathComponent("media/" + photoName))) == badImage },
                  "unreadableLocalPhotoRecoveryPreservesOriginalBeforeRestore")
        for mode in ["json", "package"] {
            for missing in ["photo", "attachment", "folder"] {
                let suffix = "-" + mode + "-" + missing, directory = root.appendingPathComponent(mode + "-" + missing)
                let secrets = MemorySecretStore("fixture-known-account-key")
                var store = NativeStore(directory: directory, secretStore: secrets)
                try store.importBackup(json)
                _ = try store.commit("gear", ["id":gear["id"], "name":"Local before recovery", "type":gear["type"]])
                try fm.removeItem(at: directory.appendingPathComponent("Recovery"))
                try Data("unreferenced local media bytes".utf8).write(to: directory.appendingPathComponent("media/Orphan.bin"))
                if missing == "folder" { try fm.removeItem(at: directory.appendingPathComponent("media")) }
                else { try fm.removeItem(at: directory.appendingPathComponent("media/" + (missing == "photo" ? photoName : attachmentName))) }
                store = NativeStore(directory: directory, secretStore: secrets)
                let before = store.state, beforeBytes = try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))
                let mediaBefore = try readMedia(directory), mediaExisted = fm.fileExists(atPath: directory.appendingPathComponent("media").path)
                var strictMissing = false
                do { _ = try GearBackupArchive.create(state: before, media: directory.appendingPathComponent("media"), in: root.appendingPathComponent("Strict" + suffix)) }
                catch {
                    let error = error as NSError
                    strictMissing = error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
                }
                try check(store.hasLoadedState && strictMissing && before["photos"].array.count == 1 && before["attachments"].array.count == 1,
                          "missingMediaLoadedLibraryReproducesStrictSafetyFailure" + suffix)
                let invalid = await restore(store, mode: mode, invalid: true)
                try check(!invalid && store.state == before && (try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))) == beforeBytes &&
                          (try readMedia(directory)) == mediaBefore && (try readOriginals(directory)).isEmpty,
                          "missingMediaInvalidIncomingRejectedBeforePreservation" + suffix)
                let recovery = directory.appendingPathComponent("Recovery"), blocker = Data("blocked preservation destination".utf8)
                try blocker.write(to: recovery)
                let blocked = await restore(store, mode: mode)
                try check(!blocked && store.hasLoadedState && store.state == before && !store.backupRestoring &&
                          (try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))) == beforeBytes && (try readMedia(directory)) == mediaBefore &&
                          fm.fileExists(atPath: directory.appendingPathComponent("media").path) == mediaExisted && (try Data(contentsOf: recovery)) == blocker,
                          "missingMediaPreservationFailurePreventsIncomingWrites" + suffix)
                try fm.removeItem(at: recovery)
                let restored = await restore(store, mode: mode)
                let originals = try readOriginals(directory)
                guard let original = originals.first else { throw DomainError("Missing original media preservation") }
                try check(restored && originals.count == 1 && (try Data(contentsOf: original.appendingPathComponent("state-v2.json"))) == beforeBytes &&
                          (try readMedia(original)) == mediaBefore,
                          "missingMediaRecoveryPreservesExactOriginalStateAndRemainingMedia" + suffix)
                let listed = await NativeBackupWorker().localVersions(directory)
                try check(listed.isEmpty && !fm.fileExists(atPath: original.appendingPathComponent("manifest.json").path),
                          "missingMediaOriginalIsNotPublishedAsRestorablePackage" + suffix)
                try check(store.hasLoadedState && sameLibrary(store.state, seed.state) &&
                          (try Data(contentsOf: store.photoURL(photo.id))) == (try Data(contentsOf: seed.photoURL(photo.id))) &&
                          (try Data(contentsOf: store.attachmentURL(attachment))) == (try Data(contentsOf: seed.attachmentURL(attachment))),
                          "missingMediaCompleteBackupRepairsMissingFilesAfterRetry" + suffix)
                try check(store.connected && !store.state["nativeRequiresConnection"].flag && secrets.read() == "fixture-known-account-key",
                          "missingMediaKnownAccountKeepsConnection" + suffix)
                let reloaded = NativeStore(directory: directory, secretStore: secrets)
                try check(reloaded.hasLoadedState && sameLibrary(reloaded.state, seed.state) &&
                          (try Data(contentsOf: reloaded.photoURL(photo.id))) == (try Data(contentsOf: seed.photoURL(photo.id))) &&
                          (try Data(contentsOf: reloaded.attachmentURL(attachment))) == (try Data(contentsOf: seed.attachmentURL(attachment))),
                          "missingMediaRepairedLibrarySurvivesReload" + suffix)
            }
            for problem in ["hash", "size", "orphan-directory", "orphan-symlink"] {
                let suffix = "-" + mode + "-" + problem, directory = root.appendingPathComponent(mode + "-" + problem)
                let store = NativeStore(directory: directory, secretStore: MemorySecretStore())
                try store.importBackup(json)
                try fm.removeItem(at: directory.appendingPathComponent("Recovery"))
                try fm.removeItem(at: store.photoURL(photo.id))
                let attachmentURL = try store.attachmentURL(attachment), originalAttachment = try Data(contentsOf: attachmentURL)
                if problem == "hash" { try Data(repeating: 0, count: originalAttachment.count).write(to: attachmentURL) }
                if problem == "size" { try Data("truncated".utf8).write(to: attachmentURL) }
                let irregular = directory.appendingPathComponent("media/Irregular")
                if problem == "orphan-directory" { try fm.createDirectory(at: irregular, withIntermediateDirectories: false) }
                if problem == "orphan-symlink" { try fm.createSymbolicLink(at: irregular, withDestinationURL: attachmentURL) }
                let before = store.state, beforeBytes = try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))
                let attachmentBytes = try Data(contentsOf: attachmentURL)
                let restored = await restore(store, mode: mode)
                let originals = try readOriginals(directory)
                let irregularKept = !problem.hasPrefix("orphan-") || fm.fileExists(atPath: irregular.path)
                try check(!restored && store.hasLoadedState && store.state == before && !store.backupRestoring &&
                          (try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))) == beforeBytes &&
                          !fm.fileExists(atPath: store.photoURL(photo.id).path) && (try Data(contentsOf: attachmentURL)) == attachmentBytes &&
                          originals.isEmpty && irregularKept,
                          "missingMediaDoesNotHideExistingFileFailure" + suffix)
            }
        }
    }
    private static func checkModernMigrationSafety(_ seed: NativeStore, check: (Bool, String) throws -> Void) async throws {
        let fm = FileManager.default, root = seed.directory.appendingPathComponent("ModernMigrationSafety")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.copyItem(at: seed.directory.appendingPathComponent("media"), to: root.appendingPathComponent("media"))
        var fields = seed.state.object; fields.removeValue(forKey: "gearCategories")
        let raw = Value.object(fields)
        try raw.jsonData().write(to: root.appendingPathComponent("state-v2.json"))
        let migrated = NativeStore(directory: root, secretStore: MemorySecretStore())
        let versions = await NativeBackupWorker().localVersions(root)
        try check(migrated.hasLoadedState && !migrated.state["gearCategories"].isNull && versions.count == 1 && migrated.preservedSourceURL == nil,
                  "modernMigrationKeepsValidSafetyPackage")
        guard let version = versions.first else { throw DomainError("Modern migration safety package missing") }
        let validated = try GearBackupArchive.validate(at: version.url)
        var mediaMatches = true
        for photo in raw["photos"].array {
            let saved = try Data(contentsOf: version.url.appendingPathComponent("media/" + photo.id + ".jpg"))
            let original = try Data(contentsOf: seed.photoURL(photo.id))
            mediaMatches = mediaMatches && saved == original
        }
        for attachment in raw["attachments"].array {
            let saved = try Data(contentsOf: version.url.appendingPathComponent("media/" + GearAttachment.fileName(attachment)))
            let original = try Data(contentsOf: seed.attachmentURL(attachment))
            mediaMatches = mediaMatches && saved == original
        }
        try check(validated.state == raw && mediaMatches, "modernMigrationSafetyPreservesOriginalStateAndMedia")
    }
    private static func checkIncompletePrototypeInputs(_ seed: NativeStore, check: (Bool, String) throws -> Void) throws {
        let fm = FileManager.default, root = seed.directory.appendingPathComponent("PrototypeFormatRecovery")
        let store = NativeStore(directory: root.appendingPathComponent("Healthy"), secretStore: MemorySecretStore())
        let exported = try Value.decode(seed.exportBackup())
        try store.importBackup(exported.jsonData())
        let before = store.state, bytes = try Data(contentsOf: store.directory.appendingPathComponent("state-v2.json"))
        let generation = store.imageImportGeneration, viewGeneration = store.viewGeneration
        func readMedia() throws -> [String: Data] {
            let files = try fm.contentsOfDirectory(at: store.directory.appendingPathComponent("media"), includingPropertiesForKeys: nil)
            return try Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        }
        let media = try readMedia()
        func apply(_ raw: Value, to target: NativeStore, mode: String) throws {
            if mode == "json" {
                var backup = exported; backup["state"] = raw
                try target.importBackup(backup.jsonData())
            } else {
                _ = try target.beginBackupRestore()
                defer { target.endBackupRestore() }
                try target.applyRestoredBackup(raw)
            }
        }
        for (name, raw) in try NativeStartupFormatFixtures.buildRejectedStates(modern: seed.state) {
            for mode in ["json", "apply"] {
                var rejected = false
                do { try apply(raw, to: store, mode: mode) }
                catch { rejected = (error as? DomainError)?.message == "备份数据无效" }
                try check(rejected && store.hasLoadedState && store.loadingFailure == nil && !store.backupRestoring &&
                          store.state == before && store.imageImportGeneration == generation && store.viewGeneration == viewGeneration &&
                          (try Data(contentsOf: store.directory.appendingPathComponent("state-v2.json"))) == bytes && (try readMedia()) == media,
                          "incompleteFormatRecoveryKeepsStateAndMedia-" + mode + "-" + name)
            }
        }
        for empty in [false, true] {
            let raw = try NativeStartupFormatFixtures.buildPrototype(empty: empty)
            for mode in ["json", "apply"] {
                let target = NativeStore(directory: root.appendingPathComponent("Valid-" + mode + (empty ? "-empty" : "-full")), secretStore: MemorySecretStore())
                try apply(raw, to: target, mode: mode)
                let matches = empty ? target.hasLoadedState && target.gears.isEmpty && target.activities.isEmpty : NativeStartupFormatFixtures.hasMigratedPrototypeDetails(target)
                try check(matches, "prototypeRecoveryPreservesEncodedLibrary-" + mode + (empty ? "-empty" : "-full"))
            }
        }
    }
    private static func checkFailedStartupRecovery(_ seed: NativeStore, check: (Bool, String) throws -> Void) async throws {
        let fm = FileManager.default, root = seed.directory.appendingPathComponent("FailedStartupRecovery")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let json = try seed.exportBackup()
        let package = try GearBackupArchive.create(state: seed.state, media: seed.directory.appendingPathComponent("media"), in: root.appendingPathComponent("Packages"))
        let manifest = try GearBackupArchive.manifest(at: package)
        let invalidPackage = root.appendingPathComponent("Corrupt." + GearBackupArchive.fileExtension)
        try fm.copyItem(at: package, to: invalidPackage)
        try Data("broken backup state".utf8).write(to: invalidPackage.appendingPathComponent("state.json"))
        for mode in ["json", "package"] {
            let directory = root.appendingPathComponent(mode)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent(mode == "json" ? "state-v2.json" : "state.json")
            let damaged = mode == "json" ? Data([0xef, 0xbb, 0xbf]) + Data("{\"damaged\":\n".utf8) : Data(" \n{\"gears\":[],\"activities\":false}\n".utf8)
            try damaged.write(to: source)
            let secrets = MemorySecretStore("fixture-old-account-A-key")
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NativeStartupAccountProtocol.self]
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let store = NativeStore(directory: directory, secretStore: secrets, session: session)
            try check(!store.hasLoadedState && store.loadingFailure != nil, "startupRecoveryBeginsLocked-" + mode)
            let rejected: Bool
            if mode == "json" {
                do { try store.importBackup(Data("{}".utf8)); rejected = false } catch { rejected = true }
            } else {
                let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: invalidPackage, uploaded: true, local: true))
                rejected = !restored
            }
            try check(rejected && !store.hasLoadedState && store.loadingFailure != nil && !store.backupRestoring &&
                      (try Data(contentsOf: source)) == damaged && store.preservedSourceURL == nil,
                      "startupInvalidRecoveryKeepsLockAndOriginalBytes-" + mode)
            if mode == "json" { try store.importBackup(json) }
            else {
                let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
                try check(restored, "startupPackageRecoveryCompletes")
            }
            guard let preserved = store.preservedSourceURL else { throw DomainError("Startup recovery original copy missing") }
            try check(preserved != source && preserved.path.hasPrefix(directory.appendingPathComponent("Recovery").path + "/") &&
                      (try Data(contentsOf: preserved)) == damaged,
                      "startupRecoveryPreservesExactOriginalBytes-" + mode)
            try check(store.hasLoadedState && store.loadingFailure == nil && !store.connected &&
                      store.state["gears"] == seed.state["gears"] && store.state["activities"] == seed.state["activities"] &&
                      store.state["attachments"] == seed.state["attachments"] && store.state["photos"] == seed.state["photos"],
                      "startupRecoveryInstallsCompleteLibraryWithoutConnectingUnknownAccount-" + mode)
            var matchingMedia = true
            for photo in seed.state["photos"].array {
                let restored = try Data(contentsOf: store.photoURL(photo.id)), original = try Data(contentsOf: seed.photoURL(photo.id))
                matchingMedia = matchingMedia && restored == original
            }
            for attachment in seed.state["attachments"].array {
                let restored = try Data(contentsOf: store.attachmentURL(attachment)), original = try Data(contentsOf: seed.attachmentURL(attachment))
                matchingMedia = matchingMedia && restored == original
            }
            try check(matchingMedia, "startupRecoveryKeepsExactPhotoAndPDFBytes-" + mode)
            let reopened = NativeStore(directory: directory, secretStore: secrets, session: session)
            try check(reopened.hasLoadedState && reopened.state["gears"] == store.state["gears"] &&
                      (try Data(contentsOf: preserved)) == damaged, "startupRecoveredLibraryPersistsBesideOriginalCopy-" + mode)
            NativeStartupAccountProtocol.configure(account: "fixture-old-account-A")
            var directRequestBlocked = false
            do { _ = try await reopened.request("/athlete/0") } catch { directRequestBlocked = true }
            reopened.startSync(); await reopened.sync(); await reopened.automaticTick()
            try check(directRequestBlocked && !reopened.connected && reopened.state["nativeRequiresConnection"].flag &&
                      !reopened.busy && NativeStartupAccountProtocol.readRequests() == 0 && secrets.read() == "fixture-old-account-A-key",
                      "startupRecoveredAccountCannotUseOldKeyAfterRestart-" + mode)
            var wrongAccountRejected = false
            do { try await reopened.connect("fixture-wrong-account-key") } catch { wrongAccountRejected = true }
            try check(wrongAccountRejected && !reopened.connected && reopened.state["nativeRequiresConnection"].flag &&
                      NativeStartupAccountProtocol.readRequests() == 1 && secrets.read() == "fixture-old-account-A-key",
                      "startupWrongAccountConnectionKeepsRequirementAndOldKey-" + mode)
            NativeStartupAccountProtocol.configure(account: seed.state["account"]["id"].text)
            try await reopened.connect("fixture-verified-account-B-key")
            reopened.cancelSync()
            for _ in 0..<1000 {
                if !reopened.busy { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let verified = NativeStore(directory: directory, secretStore: secrets, session: session)
            try check(!reopened.busy && reopened.connected && !reopened.state["nativeRequiresConnection"].flag &&
                      verified.hasLoadedState && verified.connected && !verified.state["nativeRequiresConnection"].flag &&
                      secrets.read() == "fixture-verified-account-B-key",
                      "startupMatchingAccountConnectionPersistsUnlockAcrossRestart-" + mode)
        }

        for mode in ["json", "package"] {
            let directory = root.appendingPathComponent("PreservationFailure-" + mode), source = directory.appendingPathComponent("state-v2.json")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            let marker = source.appendingPathComponent("keep-original.txt"), bytes = Data("unreadable source marker".utf8)
            try bytes.write(to: marker)
            let store = NativeStore(directory: directory, secretStore: MemorySecretStore())
            let rejected: Bool
            if mode == "json" {
                do { try store.importBackup(json); rejected = false } catch { rejected = true }
            } else {
                let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
                rejected = !restored
            }
            try check(rejected && !store.hasLoadedState && store.loadingFailure != nil && !store.backupRestoring &&
                      store.preservedSourceURL == nil && (try Data(contentsOf: marker)) == bytes &&
                      !fm.fileExists(atPath: directory.appendingPathComponent("media").path),
                      "startupRecoveryRequiresOriginalPreservationBeforeWritingMedia-" + mode)
        }

        for mode in ["json", "package"] {
            let directory = root.appendingPathComponent("ChangedSourceFailure-" + mode)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("state.json"), damaged = Data("{legacy damaged source".utf8)
            try damaged.write(to: source)
            let store = NativeStore(directory: directory, secretStore: MemorySecretStore())
            try store.preserveLocalSource()
            let blockedDestination = directory.appendingPathComponent("state-v2.json")
            try fm.createDirectory(at: blockedDestination, withIntermediateDirectories: true)
            let marker = blockedDestination.appendingPathComponent("keep.txt"), markerBytes = Data("keep failed destination".utf8)
            try markerBytes.write(to: marker)
            let rejected: Bool
            if mode == "json" {
                do { try store.importBackup(json); rejected = false } catch { rejected = true }
            } else {
                let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
                rejected = !restored
            }
            guard let preserved = store.preservedSourceURL else { throw DomainError("Earlier original copy missing") }
            try check(rejected && !store.hasLoadedState && store.loadingFailure != nil && !store.backupRestoring &&
                      (try Data(contentsOf: source)) == damaged && (try Data(contentsOf: preserved)) == damaged &&
                      (try Data(contentsOf: marker)) == markerBytes,
                      "startupChangedUnreadableSourceKeepsLockAndEarlierOriginalCopy-" + mode)
            try fm.removeItem(at: blockedDestination)
            if mode == "json" { try store.importBackup(json) }
            else {
                let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
                try check(restored, "startupPackageRecoveryRetriesAfterSourceRepair")
            }
            try check(store.hasLoadedState && store.loadingFailure == nil && store.state["gears"] == seed.state["gears"] &&
                      (try Data(contentsOf: preserved)) == damaged,
                      "startupRecoveryCanRetryAfterSourceRepair-" + mode)
        }

        for mode in ["json", "package"] {
            let directory = root.appendingPathComponent("ReplacedTarget-" + mode)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let legacy = directory.appendingPathComponent("state.json"), oldBytes = Data("{original legacy failure".utf8)
            try oldBytes.write(to: legacy)
            let store = NativeStore(directory: directory, secretStore: MemorySecretStore())
            var external = seed.state; external["externalReplacementMarker"] = "new target before restore"
            let newerBytes = Data(" \n".utf8) + (try external.jsonData()) + Data("\n".utf8)
            try newerBytes.write(to: directory.appendingPathComponent("state-v2.json"))
            if mode == "json" { try store.importBackup(json) }
            else {
                let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
                try check(restored, "startupPackageRecoveryAcceptsPreservableNewTarget")
            }
            guard let preserved = store.preservedSourceURL else { throw DomainError("New target original copy missing") }
            try check(store.hasLoadedState && preserved.lastPathComponent == "state-v2.json" &&
                      (try Data(contentsOf: preserved)) == newerBytes && (try Data(contentsOf: legacy)) == oldBytes &&
                      store.state["externalReplacementMarker"].isNull,
                      "startupRecoveryPreservesLatestReplacedTargetAndKeepsLegacy-" + mode)
        }

        let automatic = root.appendingPathComponent("Automatic"), source = automatic.appendingPathComponent("state-v2.json")
        try fm.createDirectory(at: automatic, withIntermediateDirectories: true)
        let damaged = Data("{automatic source broken".utf8)
        try damaged.write(to: source)
        let settingsURL = automatic.appendingPathComponent("cloud-backup-settings.json")
        let settings = try Value.object(["enabled":true, "bookmark":.string(Data("invalid isolated fixture bookmark".utf8).base64EncodedString()), "hash":"previous-populated-library"]).jsonData()
        try settings.write(to: settingsURL)
        let store = NativeStore(directory: automatic, secretStore: MemorySecretStore())
        var scanCount = 0
        store.cloudBackup.readVersionsForTesting = {
            scanCount += 1
            return NativeBackupVersionScan(versions: [.init(manifest: manifest, url: package, uploaded: true, local: false)], pendingCount: 0, unreadableCount: 0, discoveredCount: 1)
        }
        store.cloudBackup.changed()
        await store.cloudBackup.tick(force: true)
        await store.automaticTick()
        try await Task.sleep(for: .milliseconds(5200))
        try check(store.cloudBackup.enabled && !store.cloudBackup.working && store.cloudBackup.error == nil && scanCount == 0 &&
                  !fm.fileExists(atPath: automatic.appendingPathComponent("BackupWork").path) &&
                  !fm.fileExists(atPath: automatic.appendingPathComponent("Recovery").path) &&
                  (try Data(contentsOf: settingsURL)) == settings && (try Data(contentsOf: source)) == damaged,
                  "startupAutomaticBackupDoesNotScanPublishPruneOrReplaceSettings")
    }
    private static func checkFilePreparation(_ store: NativeStore, package: URL,
                                             check: (Bool, String) throws -> Void) async throws {
        let state = store.state, media = store.directory.appendingPathComponent("media")
        let beforeFiles = try FileManager.default.contentsOfDirectory(atPath: media.path).sorted()
        let legacy = try Value.decode(store.exportBackup())
        let exported = try await NativeBackupFiles.prepareExport(state: state, media: media)
        let decoded = try Value.decode(exported)
        try check(decoded == legacy && decoded["state"] == state, "asyncJSONExportKeepsLegacyStructureAndMedia")
        for photo in state["photos"].array {
            let bytes = try Data(contentsOf: store.photoURL(photo.id))
            try check(Data(base64Encoded: decoded["media"][photo.id].text) == bytes, "asyncJSONExportKeepsPhotoBytes")
        }
        for attachment in state["attachments"].array {
            let bytes = try Data(contentsOf: store.attachmentURL(attachment))
            try check(Data(base64Encoded: decoded["attachments"][attachment.id].text) == bytes, "asyncJSONExportKeepsAttachmentBytes")
        }
        let selectedFile = store.directory.appendingPathComponent("PreparedSelection.json")
        let raw = Data([0xef, 0xbb, 0xbf]) + Data(" \n".utf8) + exported + Data("\n".utf8)
        try raw.write(to: selectedFile)
        guard case .json(let selected) = try await NativeBackupFiles.readSelection(from: selectedFile) else { throw DomainError("Expected JSON selection") }
        try check(selected == raw, "asyncJSONSelectionPreservesExactRawBytes")
        guard case .package(let version) = try await NativeBackupFiles.readSelection(from: package) else { throw DomainError("Expected package selection") }
        let manifest = try GearBackupArchive.manifest(at: package)
        try check(version.url == package && version.local && !version.uploaded && version.manifest == manifest, "asyncPackageSelectionKeepsManifestAndLocation")

        try NativeBackupFiles.validateJSONSize(NativeBackupFiles.maximumJSONBytes - 1)
        for exporting in [false, true] {
            for count in [NativeBackupFiles.maximumJSONBytes, NativeBackupFiles.maximumJSONBytes + 1] {
                var rejected = false
                do { try NativeBackupFiles.validateJSONSize(count, exporting: exporting) } catch { rejected = true }
                try check(rejected, exporting ? "asyncJSONExportRejectsSizeBoundary" : "asyncJSONSelectionRejectsSizeBoundary")
            }
        }
        var oversizedExportRejected = false
        do { _ = try await NativeBackupFiles.prepareExport(state: ["notes":.string(String(repeating: "x", count: 128))], media: media, beforeRead: nil, maximumBytes: 64) }
        catch { oversizedExportRejected = UserFacingError.message(error) == "备份文件过大，无法导出为 JSON。请使用 iCloud Drive 自动备份。" }
        try check(oversizedExportRejected, "asyncJSONExportChecksActualSerializedSize")
        let firstPhoto = state["photos"].array[0]
        let photoBytes = try Data(contentsOf: store.photoURL(firstPhoto.id))
        var expandedMediaRejected = false
        do { _ = try await NativeBackupFiles.prepareExport(state: ["photos":[firstPhoto]], media: media, beforeRead: nil, maximumBytes: photoBytes.count + 1) }
        catch { expandedMediaRejected = UserFacingError.message(error) == "备份文件过大，无法导出为 JSON。请使用 iCloud Drive 自动备份。" }
        try check(expandedMediaRejected, "asyncJSONExportRejectsBase64Expansion")
        let smallFile = store.directory.appendingPathComponent("OversizedSelection.json")
        try Data(repeating: 0x20, count: 128).write(to: smallFile)
        var oversizedSelectionRejected = false
        do { _ = try await NativeBackupFiles.readSelection(from: smallFile, beforeRead: nil, maximumBytes: 128) }
        catch { oversizedSelectionRejected = true }
        try check(oversizedSelectionRejected, "asyncJSONSelectionChecksFileSizeBeforeRead")

        for selection in [false, true] {
            let early = Task {
                if selection { _ = try await NativeBackupFiles.readSelection(from: selectedFile) }
                else { _ = try await NativeBackupFiles.prepareExport(state: state, media: media) }
            }
            early.cancel()
            var cancelled = false
            do { try await early.value } catch is CancellationError { cancelled = true }
            try check(cancelled, selection ? "asyncJSONSelectionCancelsBeforeStart" : "asyncJSONExportCancelsBeforeStart")

            let gate = NativeBackupFileReadGate()
            var completed = false
            let operation = Task {
                defer { completed = true }
                let hook: @Sendable (URL) async throws -> Void = { _ in await gate.pause(onMainThread: NativeBackupFileReadGate.readMainThread()) }
                if selection { _ = try await NativeBackupFiles.readSelection(from: selectedFile, beforeRead: hook) }
                else { _ = try await NativeBackupFiles.prepareExport(state: state, media: media, beforeRead: hook) }
            }
            defer { operation.cancel(); Task { await gate.release() } }
            for _ in 0..<1000 {
                if await gate.entered { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try check(await gate.entered, selection ? "asyncJSONSelectionReachesReadGate" : "asyncJSONExportReachesReadGate")
            try check(!(await gate.onMainThread), selection ? "asyncJSONSelectionReadsOffMainThread" : "asyncJSONExportReadsOffMainThread")
            operation.cancel()
            for _ in 0..<3 { await Task.yield() }
            try check(!completed, selection ? "asyncJSONSelectionJoinsWorkerBeforeReturning" : "asyncJSONExportJoinsWorkerBeforeReturning")
            await gate.release()
            cancelled = false
            do { try await operation.value } catch is CancellationError { cancelled = true }
            try check(cancelled, selection ? "asyncJSONSelectionPropagatesCancellation" : "asyncJSONExportPropagatesCancellation")
        }
        var missingSelectionRejected = false
        do { _ = try await NativeBackupFiles.readSelection(from: store.directory.appendingPathComponent("MissingSelection.json")) }
        catch { missingSelectionRejected = true }
        try check(missingSelectionRejected, "asyncJSONSelectionReportsUnreadableFile")
        var missing = state
        missing["photos"] = [["id":.string(UUID().uuidString.lowercased())]]
        var missingMediaRejected = false
        do { _ = try await NativeBackupFiles.prepareExport(state: missing, media: media) }
        catch { missingMediaRejected = true }
        try check(missingMediaRejected, "asyncJSONExportReportsUnreadableMedia")
        let afterFiles = try FileManager.default.contentsOfDirectory(atPath: media.path).sorted()
        let afterSelection = try Data(contentsOf: selectedFile)
        try check(store.state == state && afterFiles == beforeFiles && afterSelection == raw, "asyncBackupPreparationNeverMutatesStateOrSourceFiles")
    }
    private static func checkVersionScanning(_ store: NativeStore, check: (Bool, String) throws -> Void) async throws {
        let fm = FileManager.default, worker = NativeBackupWorker()
        let root = store.directory.appendingPathComponent("VersionScanTests", isDirectory: true)
        let folder = root.appendingPathComponent("Cloud", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let empty = try await worker.scanVersionsForTesting(in: folder)
        try check(empty.scan.versions.isEmpty && empty.scan.discoveredCount == 0 && empty.scan.complete && empty.scan.readMessage == nil, "versionScanKeepsTrulyEmptyDirectoryEmpty")
        var state = store.state
        state["photos"] = []; state["attachments"] = []
        let media = store.directory.appendingPathComponent("media")
        let older = try GearBackupArchive.create(state: state, media: media, in: folder, at: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = try GearBackupArchive.create(state: state, media: media, in: folder, at: Date(timeIntervalSince1970: 1_700_000_100))
        let readyIDs = [try GearBackupArchive.manifest(at: newer).id, try GearBackupArchive.manifest(at: older).id]
        let pending = try GearBackupArchive.create(state: state, media: media, in: folder, at: Date(timeIntervalSince1970: 1_700_000_200))
        let pendingManifest = pending.appendingPathComponent("manifest.json"), delayed = pending.appendingPathComponent(".delayed-manifest")
        try fm.moveItem(at: pendingManifest, to: delayed)
        let pendingOnlyFolder = root.appendingPathComponent("PendingOnly", isDirectory: true)
        try fm.createDirectory(at: pendingOnlyFolder, withIntermediateDirectories: true)
        try fm.copyItem(at: pending, to: pendingOnlyFolder.appendingPathComponent(pending.lastPathComponent))
        let pendingOnly = try await worker.scanVersionsForTesting(in: pendingOnlyFolder, pendingPackages: [pending.lastPathComponent])
        try check(pendingOnly.scan.versions.isEmpty && pendingOnly.scan.discoveredCount == 1 && pendingOnly.scan.pendingCount == 1 && pendingOnly.scan.unreadableCount == 0 && pendingOnly.scan.readMessage == "有备份尚未下载完成，请稍后重新读取。", "versionScanDoesNotDescribePendingManifestAsEmpty")
        try check(pendingOnly.requestedDownloads == [pending.lastPathComponent], "versionScanRequestsPendingManifestDownload")
        let partial = try await worker.scanVersionsForTesting(in: folder, pendingPackages: [pending.lastPathComponent])
        try check(partial.scan.versions.map(\.id) == readyIDs && partial.scan.pendingCount == 1 && partial.scan.unreadableCount == 0, "versionScanRetainsReadyVersionsBesidePendingManifest")

        let unreadable = try GearBackupArchive.create(state: state, media: media, in: folder, at: Date(timeIntervalSince1970: 1_700_000_300))
        let unreadableManifest = unreadable.appendingPathComponent("manifest.json")
        let originalManifest = try Data(contentsOf: unreadableManifest)
        try Data("{invalid synthetic manifest".utf8).write(to: unreadableManifest)
        let unreadableOnlyFolder = root.appendingPathComponent("UnreadableOnly", isDirectory: true)
        try fm.createDirectory(at: unreadableOnlyFolder, withIntermediateDirectories: true)
        try fm.copyItem(at: unreadable, to: unreadableOnlyFolder.appendingPathComponent(unreadable.lastPathComponent))
        let unreadableOnly = try await worker.scanVersionsForTesting(in: unreadableOnlyFolder)
        try check(unreadableOnly.scan.versions.isEmpty && unreadableOnly.scan.unreadableCount == 1 && unreadableOnly.scan.pendingCount == 0 && unreadableOnly.scan.readMessage == "有备份无法读取，请重新读取或选择其他备份。" && unreadableOnly.requestedDownloads.isEmpty, "versionScanDoesNotCallInvalidLocalManifestADownload")
        let mixed = try await worker.scanVersionsForTesting(in: folder, pendingPackages: [pending.lastPathComponent])
        try check(mixed.scan.versions.map(\.id) == readyIDs && mixed.scan.discoveredCount == 4 && mixed.scan.pendingCount == 1 && mixed.scan.unreadableCount == 1 && !mixed.scan.complete, "versionScanRetainsSortedReadyVersionsBesideMixedFailures")
        try check(mixed.scan.readMessage == "有备份尚未下载完成，另有备份无法读取。请稍后重新读取或选择其他备份。", "versionScanMixedMessageKeepsBothRecoveryStates")

        let managerRoot = root.appendingPathComponent("Manager", isDirectory: true)
        let recoveryURL = try await worker.safety(state: state, directory: managerRoot)
        let settings: Value = ["enabled":false, "bookmark":.string(Data("synthetic scan bookmark".utf8).base64EncodedString())]
        try settings.jsonData().write(to: managerRoot.appendingPathComponent("cloud-backup-settings.json"))
        let managerStore = NativeStore(directory: managerRoot, secretStore: MemorySecretStore())
        let manager = managerStore.cloudBackup
        let uploadedPartial = NativeBackupVersionScan(versions: mixed.scan.versions.map { .init(manifest: $0.manifest, url: $0.url, uploaded: true, local: false) }, pendingCount: 1, unreadableCount: 1, discoveredCount: 4)
        manager.readVersionsForTesting = { uploadedPartial }
        let beforeReload = managerStore.state
        await manager.reload()
        try check(manager.versions.map(\.id) == readyIDs && manager.error == mixed.scan.readMessage && !manager.working, "versionReloadKeepsPartialVersionsAndWarningWithoutPruning")
        try check(manager.localVersions.contains { $0.url == recoveryURL } && managerStore.state == beforeReload, "versionReloadKeepsLocalRecoveryWithoutChangingData")
        if let recovery = manager.localVersions.first(where: { $0.url == recoveryURL }) {
            let restored = await manager.restore(recovery)
            try check(restored && managerStore.state["activities"] == state["activities"] && managerStore.state["events"] == state["events"], "versionLocalRecoveryRestoresBesideUnreadableCloudEntries")
        } else { try check(false, "versionLocalRecoveryRestoresBesideUnreadableCloudEntries") }
        await manager.reload()
        try check(manager.error == mixed.scan.readMessage, "versionReloadPreservesWarningAfterSuccessfulLocalRestore")

        try fm.moveItem(at: delayed, to: pendingManifest)
        let stillUnreadable = try await worker.scanVersionsForTesting(in: folder)
        try check(stillUnreadable.scan.pendingCount == 0 && stillUnreadable.scan.unreadableCount == 1 && stillUnreadable.scan.versions.count == 3, "versionRetryRecognizesDownloadedManifest")
        try originalManifest.write(to: unreadableManifest)
        let repaired = try await worker.scanVersionsForTesting(in: folder)
        let repairedIDs = try [unreadable, pending, newer, older].map { try GearBackupArchive.manifest(at: $0).id }
        manager.readVersionsForTesting = { repaired.scan }
        await manager.reload()
        try check(repaired.scan.complete && manager.error == nil && manager.versions.map(\.id) == repairedIDs && !manager.localVersions.isEmpty, "versionRetryClearsWarningAfterActualManifestRepair")

        let failedPackage = older.lastPathComponent
        for (code, message, key) in [
            (NSUbiquitousFileNotUploadedDueToQuotaError, "iCloud 空间不足，请清理空间后重试。", "versionScanKeepsReadyVersionsAndQuotaRecoveryAction"),
            (NSUbiquitousFileUbiquityServerNotAvailable, "暂时无法连接 iCloud，请稍后重试。", "versionScanKeepsReadyVersionsAndUnavailableRecoveryAction")
        ] {
            let failed = try await worker.scanVersionsForTesting(in: folder, uploadStatus: { file, _ in
                if file.lastPathComponent == failedPackage { throw NSError(domain: NSCocoaErrorDomain, code: code) }
                return true
            })
            manager.readVersionsForTesting = { failed.scan }
            await manager.reload()
            try check(failed.scan.versions.map(\.id) == repairedIDs && failed.scan.unreadableCount == 1 && !failed.scan.complete && failed.scan.versions.first?.uploaded == true && failed.scan.versions.last?.uploaded == false && manager.versions.map(\.id) == repairedIDs && manager.error == message && !manager.working && manager.localVersions.contains { $0.url == recoveryURL }, key)
        }

        let emptyRoot = root.appendingPathComponent("EmptyBackup", isDirectory: true)
        try fm.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        try Value.object(["enabled":true, "bookmark":settings["bookmark"]]).jsonData().write(to: emptyRoot.appendingPathComponent("cloud-backup-settings.json"))
        let emptyStore = NativeStore(directory: emptyRoot, secretStore: MemorySecretStore())
        defer { emptyStore.cloudBackup.setEnabled(false) }
        emptyStore.cloudBackup.readVersionsForTesting = { pendingOnly.scan }
        await emptyStore.cloudBackup.tick(force: true)
        try check(emptyStore.cloudBackup.error == pendingOnly.scan.readMessage && emptyStore.cloudBackup.versions.isEmpty && !fm.fileExists(atPath: emptyRoot.appendingPathComponent("BackupWork").path), "versionPendingScanDoesNotPublishInitialEmptyBackup")
    }

    static func runCloud(_ store: NativeStore) async {
        guard store.directory.lastPathComponent == "GearhousePreview" else { return }
        let output = store.directory.appendingPathComponent("cloud-backup-self-test.json")
        var report: [String: String] = [:]
        func record(_ key: String, _ value: String) {
            report[key] = value
            try? JSONEncoder().encode(report).write(to: output, options: .atomic)
        }
        func check(_ value: Bool, _ key: String) throws {
            record(key, value ? "passed" : "failed")
            if !value { throw DomainError(key) }
        }
        func sameData(_ lhs: Value, _ rhs: Value) -> Bool {
            var left = lhs.object, right = rhs.object
            left.removeValue(forKey: "revision"); right.removeValue(forKey: "revision")
            return left == right
        }
        let manager = store.cloudBackup
        var baseline: NativeBackupVersion?
        do {
            for _ in 0..<60 {
                if !manager.working { break }
                try await Task.sleep(for: .seconds(1))
            }
            await manager.reload()
            try check(manager.enabled && manager.hasLocation && !manager.working, "persistedDirectoryAccess")
            baseline = manager.versions.first(where: { $0.uploaded && !$0.manifest.photos.isEmpty })
            guard let version = baseline else { throw DomainError("No uploaded fixture backup with an image") }
            record("baselineID", version.id)
            let before = store.state
            try before.jsonData().write(to: store.directory.appendingPathComponent("cloud-test-before.json"), options: .atomic)
            let ids = manager.versions.map(\.id)
            await manager.tick()
            try check(manager.versions.map(\.id) == ids, "unchangedDataDoesNotCreateVersion")
            guard let photo = before["photos"].array.first else { throw DomainError("Fixture photo missing") }
            _ = try store.commit("hidden", ["id":"tarmac", "hidden":true])
            _ = try store.commit("photo-edit", ["ownerType":photo["ownerType"], "ownerId":photo["ownerId"], "action":"delete", "id":photo["id"], "confirmed":true])
            let changed = store.state
            try check(!FileManager.default.fileExists(atPath: store.photoURL(photo.id).path), "originalLocalImageRemoved")
            // No forced backup: the normal change debounce must publish this version.
            try await Task.sleep(for: .seconds(7))
            var edited: NativeBackupVersion?
            for _ in 0..<60 {
                await manager.reload()
                edited = manager.versions.first(where: { !ids.contains($0.id) && $0.manifest.photos.isEmpty })
                if edited?.uploaded == true { break }
                if let failure = manager.error { throw DomainError(failure) }
                try await Task.sleep(for: .seconds(1))
            }
            try check(edited?.uploaded == true, "automaticBackupOfEditsUploaded")
            if let edited { record("editedID", edited.id) }
            let restored = await manager.restore(version)
            record("restoreReturned", restored ? "true" : "false")
            if let failure = manager.error { record("restoreError", failure) }
            let differences = Set(before.object.keys).union(store.state.object.keys).filter { before[$0] != store.state[$0] }.sorted()
            if !differences.isEmpty { record("restoredDifferenceFields", differences.joined(separator: ",")) }
            try check(restored && sameData(store.state, before), "cloudVersionRestoresState")
            try check(store.revision.double > changed["revision"].double, "restoreInvalidatesOlderPreviews")
            try check(try GearBackupArchive.hash(store.photoURL(photo.id)) == version.manifest.photos.first(where: { $0.id == photo.id })?.hash, "deletedImageRestoredFromCloudVersion")
            guard let recovery = manager.localVersions.first else { throw DomainError("Pre-restore version missing") }
            let recovered = await manager.restore(recovery)
            try check(recovered && sameData(store.state, changed), "preRestoreVersionRestoresEditedState")
            let cleaned = await manager.restore(version)
            try check(cleaned && sameData(store.state, before), "fixtureRestoredAfterTest")
            record("result", "passed")
        } catch {
            record("error", error.localizedDescription)
            if let baseline { _ = await manager.restore(baseline) }
            record("result", "failed")
        }
    }

    static func run() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupRestoreTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var report: [String: String] = [:]
        func check(_ value: Bool, _ name: String) throws {
            report[name] = value ? "passed" : "failed"
            if !value { throw DomainError(name) }
        }
        func waitFor(_ name: String, _ condition: () -> Bool) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            try check(false, name)
        }
        func checkCancellation(_ fixture: NativeSyncCancellationFixture, prefix: String) throws {
            let result = fixture.readCancellationResult()
            try check(!result["busy"].flag && !result["stopping"].flag && result["progress"].text.isEmpty &&
                      result["failuresUnchanged"].flag && result["successUnchanged"].flag &&
                      result["backoffUnchanged"].flag && result["errorUnchanged"].flag, prefix + "DoesNotRecordFailureOrSuccess")
            try check(result["savedBatchPresent"].flag && result["pendingBatchAbsent"].flag &&
                      result["resumeAtPendingBatch"].flag, prefix + "PreservesCommittedBatchAndResume")
        }
        do {
            let secrets = MemorySecretStore("fixture-backup-key")
            let store = NativeStore(directory: root, secretStore: secrets)
            try store.commit("account", ["id":"backup-athlete", "name":"Fixture"])
            let bike = try store.commit("gear", ["name":"Backup Bike", "type":"Bike"])
            _ = try store.commit("category-save", ["name":"Fixture Category", "baseType":"Equipment", "indoorDistance":true])
            _ = try store.commit("component", ["parentId":bike["id"], "at":"2024-01-01T00:00:00", "gear":["name":"Backup Chain", "type":"Chain"]])
            _ = try store.commit("event-save", ["requestId":.string(UUID().uuidString), "event":["gearId":bike["id"], "kind":"maintenance", "occurredDate":"2026-10-01", "notes":"Fixture maintenance"]])
            _ = try store.commit("sync-rows", ["rows":[["id":"backup-ride", "name":"Fixture Ride", "start_date_local":"2026-10-01T12:00:00", "type":"Ride", "distance":1000, "moving_time":100]], "historical":false, "from":"2026-10-01", "to":"2026-10-01", "next":"2026-10-02"])
            _ = try store.commit("assignment", ["id":"backup-ride", "assignment":["main":bike["id"], "extras":[], "excluded":[]]])
            var reminder = GearReminder(gearID: bike.id); reminder.title = "Fixture Reminder"; reminder.mode = .total; reminder.kilometers = 10
            try store.saveReminder(reminder)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
            let photo = try store.addImage(image.pngData()!, owner: "gear", id: bike.id)
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { context in
                context.beginPage(); ("Fixture receipt" as NSString).draw(at: CGPoint(x: 8, y: 8), withAttributes: nil)
            }
            let attachment = root.appendingPathComponent("FixtureReceipt.pdf")
            try pdf.write(to: attachment)
            try await store.addAttachment(from: attachment, gearID: bike.id)
            let before = store.state
            let worker = NativeBackupWorker()
            let package = try await worker.safety(state: before, directory: root)
            let manifest = try GearBackupArchive.manifest(at: package)
            try await checkFilePreparation(store, package: package, check: check)
            try await checkFailedStartupRecovery(store, check: check)
            try checkIncompletePrototypeInputs(store, check: check)
            try await checkModernMigrationSafety(store, check: check)
            try await checkMissingMediaRecovery(store, check: check)
            try await checkVersionScanning(store, check: check)
            try check(!(try String(contentsOf: package.appendingPathComponent("state.json"))).contains("fixture-backup-key"), "credentialsExcluded")
            _ = try store.commit("gear", ["id":bike["id"], "name":"Changed Bike", "type":"Bike"])
            _ = try store.commit("photo-edit", ["ownerType":"gear", "ownerId":bike["id"], "action":"delete", "id":.string(photo), "confirmed":true])
            let changed = store.state
            let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
            try check(restored && store.gear(bike.id)["name"].text == "Backup Bike", "versionRestore")
            try check(store.connected && !store.state["nativeRequiresConnection"].flag, "healthyPackageRestoreKeepsExistingAccountConnection")
            try check(!before["events"].array.isEmpty && !before["gearEvents"].array.isEmpty && store.state["activities"] == before["activities"] && store.state["events"] == before["events"] && store.state["gearEvents"] == before["gearEvents"], "activitySnapshotsAndAssemblyHistoryPreserved")
            try check(store.state["reminders"] == before["reminders"] && store.state["gearCategories"] == before["gearCategories"], "remindersAndCategoriesPreserved")
            try check(try GearBackupArchive.hash(store.photoURL(photo)) == manifest.photos[0].hash, "imageRestoredAndVerified")
            try check(secrets.read() == "fixture-backup-key", "connectionUnchanged")
            let recovery = store.cloudBackup.localVersions.first!
            let rollback = await store.cloudBackup.restore(recovery)
            try check(rollback && store.state["gears"] == changed["gears"] && store.state["photos"] == changed["photos"], "preRestoreRecoveryAccessible")
            let stable = store.state
            try Data("broken".utf8).write(to: package.appendingPathComponent("state.json"))
            let rejected = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
            try check(!rejected && store.state == stable, "corruptBackupLeavesCurrentDataIntact")
            var foreign = stable; foreign["account"] = ["id":"another-athlete"]
            let foreignURL = try await worker.safety(state: foreign, directory: root)
            let wrongAccount = await store.cloudBackup.restore(.init(manifest: try GearBackupArchive.manifest(at: foreignURL), url: foreignURL, uploaded: true, local: true))
            try check(!wrongAccount && store.state == stable, "accountMismatchLeavesCurrentDataIntact")
            _ = try store.beginBackupRestore()
            try check((try? store.commit("hidden", ["id":bike["id"], "hidden":true])) == nil, "writesBlockedDuringRestore")
            store.endBackupRestore()

            let jsonBefore = store.state
            let jsonBackup = try store.exportBackup()
            try store.commit("gear", ["id":bike["id"], "name":"Changed after JSON export", "type":"Bike"])
            let jsonChangedRevision = store.revision.double
            try check(jsonChangedRevision == jsonBefore["revision"].double + 1, "jsonImportRevisionCollisionFixture")
            try store.importBackup(jsonBackup)
            try check(store.revision.double > jsonChangedRevision, "jsonImportInvalidatesOlderPreviews")
            var jsonExpected = jsonBefore
            jsonExpected["revision"] = store.revision
            try check(store.state == jsonExpected, "jsonImportRestoresDataAfterRevisionCollision")
            try check(store.connected && !store.state["nativeRequiresConnection"].flag, "healthyJSONRestoreKeepsExistingAccountConnection")

            let unavailableRoot = root.appendingPathComponent("UnavailableCloud", isDirectory: true)
            let localPackage = try GearBackupArchive.create(state: stable, media: root.appendingPathComponent("media"), in: unavailableRoot.appendingPathComponent("Recovery"))
            let invalidSettings: Value = ["enabled":false, "bookmark":.string(Data("invalid fixture bookmark".utf8).base64EncodedString())]
            try invalidSettings.jsonData().write(to: unavailableRoot.appendingPathComponent("cloud-backup-settings.json"))
            let offlineStore = NativeStore(directory: unavailableRoot, secretStore: MemorySecretStore())
            await offlineStore.cloudBackup.reload()
            try check(offlineStore.cloudBackup.error != nil, "cloudReadFailureReported")
            let localVersion = offlineStore.cloudBackup.localVersions.first { $0.url == localPackage }
            try check(localVersion != nil, "localRecoveryVisibleWhenCloudUnavailable")
            if let localVersion {
                let localRestored = await offlineStore.cloudBackup.restore(localVersion)
                try check(localRestored && offlineStore.state["gears"] == stable["gears"] && offlineStore.state["activities"] == stable["activities"], "localRecoveryRestoresWhenCloudUnavailable")
                guard let restoredAttachment = offlineStore.state["attachments"].array.first else { throw DomainError("Restored fixture attachment missing") }
                let restoredBytes = try Data(contentsOf: offlineStore.attachmentURL(restoredAttachment))
                try check(offlineStore.state["attachments"] == stable["attachments"] && restoredBytes == pdf, "localRecoveryRestoresAttachmentBytesWhenCloudUnavailable")
            }

            for scenario in ["cancelled", "partial", "unavailable"] {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [NativeBackupSyncProtocol.self]
                configuration.httpAdditionalHeaders = ["X-Gearhouse-Fixture": scenario]
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let syncStore = NativeStore(directory: root.appendingPathComponent("Sync-" + scenario), secretStore: MemorySecretStore("fixture-cancellation-key"), session: session)
                try syncStore.commit("account", ["id":"cancelled-sync-athlete", "name":"Fixture"])
                let previousSync = syncStore.state["autoSync"]
                await syncStore.sync(from: "2026-01-01", to: "2026-02-02")
                if scenario == "unavailable" {
                    try check(syncStore.state["autoSync"]["failures"].integer == previousSync["failures"].integer + 1 && syncStore.error != nil, "nonCancellationFailureStillReported")
                } else {
                    try check(syncStore.state["autoSync"] == previousSync && syncStore.error == nil && !syncStore.busy && !syncStore.refreshingGears, scenario == "partial" ? "cancelledPartialSyncDoesNotCountFailure" : "cancelledSyncDoesNotCountFailure")
                    if scenario == "partial" {
                        try check(syncStore.state["activities"].array.contains { $0.id == "cancelled-sync-ride" }, "cancelledSyncKeepsImportedBatches")
                    }
                }
            }

            let manual = try NativeSyncCancellationFixture(directory: root.appendingPathComponent("ManualCancellation"), automatic: false)
            defer { manual.close() }
            manual.store.startSync()
            try check(manual.store.busy, "manualSyncReservesJobBeforeReturning")
            manual.store.startSync()
            try await waitFor("manualSyncWaitsForSecondRead") { manual.readReceipt()["held"].integer == 1 }
            manual.store.cancelSync()
            try await waitFor("manualSyncStopsNetworkRequest") {
                !manual.store.busy && manual.readReceipt()["held"].integer == 0 && manual.readReceipt()["stopped"].integer == 1
            }
            try checkCancellation(manual, prefix: "manualCancellation")
            manual.releaseReads()
            await manual.store.sync()
            try check(!manual.store.busy && !manual.store.stoppingSync && manual.store.error == nil &&
                      manual.store.state["activities"].array.contains { $0.id == "sync-cancel-saved-batch" } &&
                      manual.store.state["activities"].array.contains { $0.id == "sync-cancel-finished-batch" } &&
                      manual.store.state["autoSync"]["resume"].isNull && manual.store.state["autoSync"]["failures"].integer == 0,
                      "cancelledSyncCanRestartAndFinish")

            for parentCancellation in [false, true] {
                let fixture = try NativeSyncCancellationFixture(directory: root.appendingPathComponent(parentCancellation ? "ParentCancellation" : "AutomaticCancellation"), automatic: true)
                defer { fixture.close() }
                var returned = false
                let waiter = Task { await fixture.store.automaticTick(); returned = true }
                try await waitFor("automaticSyncWaitsForSecondRead") { fixture.readReceipt()["held"].integer == 1 }
                try check(!returned && fixture.store.busy, parentCancellation ? "backgroundSyncAwaitsJob" : "automaticSyncAwaitsJob")
                if parentCancellation { waiter.cancel() } else { fixture.store.cancelSync() }
                await waiter.value
                try await waitFor("automaticSyncStopsNetworkRequest") {
                    !fixture.store.busy && fixture.readReceipt()["held"].integer == 0 && fixture.readReceipt()["stopped"].integer == 1
                }
                try checkCancellation(fixture, prefix: parentCancellation ? "parentCancellation" : "automaticCancellation")
            }

            let early = try NativeSyncCancellationFixture(directory: root.appendingPathComponent("EarlyCancellation"), automatic: false)
            defer { early.close() }
            early.store.startSync(); early.store.cancelSync()
            try await waitFor("earlyCancellationFinishes") { !early.store.busy }
            try check(early.store.state["autoSync"] == early.initialStatus && early.store.state["activities"].array.isEmpty &&
                      early.store.error == nil && !early.store.stoppingSync, "cancellationBeforeWorkerStartsDoesNotCommit")

            let race = try NativeSyncCancellationFixture(directory: root.appendingPathComponent("ResponseCancellation"), automatic: false)
            defer { race.close() }
            race.store.startSync()
            try await waitFor("responseRaceWaitsForSecondRead") { race.readReceipt()["held"].integer == 1 }
            race.releaseReads(); race.store.cancelSync()
            try await waitFor("responseRaceFinishes") { !race.store.busy }
            try checkCancellation(race, prefix: "responseCancellationRace")

            let catalog = try NativeSyncCancellationFixture(directory: root.appendingPathComponent("CatalogRefreshSingleFlight"), automatic: true, holdingCatalog: true)
            defer { catalog.close() }
            var catalogReturned = false
            let catalogTask = Task { try await catalog.store.refreshRemoteGears(); catalogReturned = true }
            try await waitFor("manualCatalogRefreshWaitsForResponse") { catalog.readReceipt()["held"].integer == 1 }
            catalog.store.startSync()
            try check(!catalog.store.busy && catalog.store.refreshingGears, "startSyncSkipsActiveGearRefresh")
            await catalog.store.automaticTick()
            try check(!catalog.store.busy && !catalog.store.stoppingSync && catalog.store.refreshingGears && !catalogReturned &&
                      catalog.store.state["autoSync"] == catalog.initialStatus && catalog.store.error == nil &&
                      catalog.store.state["syncLog"].array.isEmpty && catalog.readReceipt()["held"].integer == 1,
                      "automaticTickSkipsActiveGearRefreshWithoutFailure")
            catalog.releaseReads()
            try await catalogTask.value
            try check(catalogReturned && !catalog.store.refreshingGears && !catalog.store.busy &&
                      catalog.store.state["autoSync"] == catalog.initialStatus && catalog.store.error == nil &&
                      catalog.readReceipt()["held"].integer == 0 && catalog.readReceipt()["stopped"].integer == 0,
                      "manualGearRefreshCompletesAfterSkippedSync")
        } catch {
            report["error"] = error.localizedDescription
        }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backup-self-test.json")
        try? JSONEncoder().encode(report).write(to: url, options: .atomic)
    }
}
#endif
