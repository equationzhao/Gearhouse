#if DEBUG
import Foundation
import UIKit
import CryptoKit
#if canImport(GearhouseCore)
import GearhouseCore
#endif

private final class NativeFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var deleted = false
    private static var target = "bike1"
    private static var failWrite = false
    private static var includeNewGear = false
    private static var failCatalog = false
    private static var loseConfirmation = false
    private static var putCount = 0
    private static var requestCount = 0
    private static var source = "MANUAL"
    private static var omitGear = false
    static func configure(deleted: Bool = false, failWrite: Bool = false, target: String? = nil, includeNewGear: Bool = false, failCatalog: Bool = false, loseConfirmation: Bool = false, source: String = "MANUAL", omitGear: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        self.deleted = deleted; self.failWrite = failWrite; self.includeNewGear = includeNewGear
        self.failCatalog = failCatalog; self.loseConfirmation = loseConfirmation; self.putCount = 0; self.requestCount = 0
        self.source = source; self.omitGear = omitGear
        if let target { self.target = target }
    }
    static func readPutCount() -> Int { lock.lock(); defer { lock.unlock() }; return putCount }
    static func readRequestCount() -> Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer {Self.lock.unlock()}
        Self.requestCount += 1
        let path=request.url!.path
        var status=200, payload:Value=[:]
        if path.hasSuffix("/gear") {
            payload=[["id":"bike1","name":"Fixture Bike","type":"Bike","component_ids":["wheel"]],["id":"bike2","name":"Other Bike","type":"Bike"],["id":"wheel","name":"Fixture Wheel","type":"Wheelset","component":true,"distance":1000,"time":100,"activities":1]]
            if Self.includeNewGear { payload = .array(payload.array + [["id":"bike3", "name":"New Bike", "type":"Bike"]]) }
            if Self.failCatalog { status = 500 }
        } else if path.hasSuffix("/activities") {
            payload=Self.deleted ? [] : [Self.activity()]
        } else if path.contains("/activity/") {
            if Self.deleted { status=404 }
            else if request.httpMethod=="PUT" {
                Self.putCount += 1
                if Self.failWrite {status=500}
                else {
                    var data=request.httpBody
                    if data==nil,let stream=request.httpBodyStream {
                        stream.open();defer{stream.close()};var collected=Data(),buffer=[UInt8](repeating:0,count:4096)
                        while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};collected.append(buffer,count:n)}
                        data=collected
                    }
                    if let data,let body=try? Value.decode(data){Self.target=body["gear"]["id"].text}
                    payload=Self.activity()
                    if Self.loseConfirmation { status = 500 }
                }
            } else {payload=Self.activity()}
        } else {payload=["id":"fixture-athlete","name":"Fixture Account"]}
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:(try? payload.jsonData()) ?? Data());client?.urlProtocolDidFinishLoading(self)
    }
    private static func activity() -> Value {
        let row: Value = ["id":"fixture-ride","name":"Fixture Ride","type":"Ride","start_date_local":"2026-10-01T08:00:00","distance":12000,"moving_time":1200,"source":.string(source),"icu_athlete_id":"fixture-athlete","gear":["id":.optional(target)]]
        if omitGear { var fields = row.object; fields.removeValue(forKey:"gear"); return .object(fields) }
        return row
    }
    override func stopLoading() {}
}

private actor NativeImagePreparationGate {
    private var prepared = false
    private var preparedOffMain = false
    private var preparationCount = 0
    private var ready: CheckedContinuation<Void, Never>?
    private var continuing: CheckedContinuation<Void, Never>?
    func pause(preparedOffMain: Bool) async {
        prepared = true
        self.preparedOffMain = preparedOffMain
        ready?.resume(); ready = nil
        await withCheckedContinuation { continuing = $0 }
    }
    func waitUntilPrepared() async {
        if prepared { return }
        await withCheckedContinuation { ready = $0 }
    }
    func failPreparation() { prepared = true; ready?.resume(); ready = nil }
    func resume() { continuing?.resume(); continuing = nil }
    func readPreparedOffMain() -> Bool { preparedOffMain }
    func countPreparation() -> Int { preparationCount += 1; return preparationCount }
}

private actor NativeAttachmentOperationGate {
    private var paused = false
    private var destination: URL?
    private var offMain = false
    private var cancelled = false
    private var continuing: CheckedContinuation<Void, Never>?
    func pause(destination: URL? = nil, offMain: Bool) async {
        self.destination = destination; self.offMain = offMain; paused = true
        await withCheckedContinuation { continuing = $0 }
    }
    func waitUntilPaused() async throws {
        for _ in 0..<1500 {
            if paused { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw DomainError("Self-test attachment worker did not reach its gate")
    }
    func resume() { continuing?.resume(); continuing = nil }
    func recordCancellation(_ value: Bool) { cancelled = value }
    func readCancellation() -> Bool { cancelled }
    func readOffMain() -> Bool { offMain }
    func readDestination() -> URL? { destination }
}

private final class NativePhotoTransferProbe: @unchecked Sendable {
    let progress = Progress(totalUnitCount: 1)
    private let lock = NSLock()
    private var completion: NativePhotoDataLoader.Completion?
    private var waiting: CheckedContinuation<Void, Never>?
    func startRequest(_ completion: @escaping NativePhotoDataLoader.Completion) -> Progress {
        lock.lock()
        self.completion = completion
        let ready = waiting; waiting = nil
        lock.unlock()
        ready?.resume()
        return progress
    }
    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if completion != nil { lock.unlock(); continuation.resume() }
            else { waiting = continuation; lock.unlock() }
        }
    }
    func finishRequest(_ result: Result<Data?, Error>) {
        lock.lock(); let callback = completion; lock.unlock()
        callback?(result)
    }
    func readStarted() -> Bool { lock.lock(); defer { lock.unlock() }; return completion != nil }
}

@MainActor
enum NativeStartupFormatFixtures {
    static func buildPrototype(empty: Bool = false) throws -> Value {
        let instant = ISO8601DateFormatter().date(from: "2026-10-01T01:02:03Z")!
        let state = empty ? GearhouseState() : GearhouseState(accountName: "Synthetic legacy account", gears: [
            Gear(id: "legacy-bike", name: "Legacy fixture", type: .bike, remoteID: "legacy-remote"),
            Gear(id: "legacy-chain", name: "Legacy component", type: .chain, parentID: "legacy-bike")
        ], activities: [
            Activity(id: "legacy-ride", name: "Legacy activity", type: "Ride", at: instant, distance: 1234, seconds: 120,
                     remoteGearID: "legacy-remote", mainGearID: "legacy-bike", equipmentDistanceIncluded: false)
        ], lastSync: instant)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try Value.decode(encoder.encode(state))
    }
    static func buildRejectedStates(modern: Value) throws -> [(String, Value)] {
        var fields = modern.object; fields.removeValue(forKey: "events")
        var emptyModern = fields; emptyModern["gears"] = []; emptyModern["activities"] = []
        var rows: [(String, Value)] = [("modernNonempty", .object(fields)), ("modernEmpty", .object(emptyModern))]
        let emptyPrototype = try buildPrototype(empty: true)
        for (name, field, content): (String, String, Value) in [
            ("modernReminderRoot", "reminders", []), ("modernPhotoRoot", "photos", []),
            ("modernMaintenanceRoot", "gearEvents", []), ("modernInventoryRoot", "gearOperations", []),
            ("modernConnectionRoot", "nativeRequiresConnection", true), ("modernRevisionRoot", "revision", 7)
        ] {
            var raw = emptyPrototype; raw[field] = content; rows.append((name, raw))
        }
        let prototype = try buildPrototype()
        var gearMarked = prototype, markedGear = prototype["gears"].array[0]
        markedGear["remoteId"] = "modern-remote"; gearMarked["gears"] = [markedGear]
        rows.append(("modernGearRow", gearMarked))
        var activityMarked = prototype, markedActivity = prototype["activities"].array[0]
        markedActivity["snapshot"] = [["id":"legacy-bike", "parentId":.null]]
        activityMarked["activities"] = [markedActivity]; rows.append(("modernActivityRow", activityMarked))
        var missingRetired = prototype, missingFields = prototype["gears"].array[0].object
        missingFields.removeValue(forKey: "retired"); missingRetired["gears"] = [.object(missingFields)]
        rows.append(("prototypeMissingRequiredRetired", missingRetired))
        var wrongType = prototype, wrongGear = prototype["gears"].array[0]
        wrongGear["retired"] = "false"; wrongType["gears"] = [wrongGear]
        rows.append(("prototypeWrongRetiredType", wrongType))
        var invalidDate = prototype, activity = prototype["activities"].array[0]
        activity["at"] = "2026-10-01T01:02:03"; invalidDate["activities"] = [activity]
        rows.append(("prototypeMissingUTCOffset", invalidDate))
        var nullEvents = emptyPrototype; nullEvents["events"] = .null
        rows.append(("nullEvents", nullEvents))
        return rows
    }
    static func hasMigratedPrototypeDetails(_ store: NativeStore) -> Bool {
        let activity = store.state["activities"].array.first ?? [:]
        return store.hasLoadedState && store.state["gears"].array.map(\.id) == ["legacy-bike", "legacy-chain"] &&
            store.state["events"].array.contains { $0["gearId"].text == "legacy-chain" && $0["parentId"].text == "legacy-bike" } &&
            activity["at"].text == "2026-10-01T09:02:03" && activity["startInstant"].text == "2026-10-01T01:02:03.000Z" && activity["main"].text == "legacy-bike" &&
            activity["snapshot"] == [["id":"legacy-bike", "parentId":.null, "distanceIncluded":false]]
    }
}

@MainActor
enum NativeSelfTest {
    private static func verifyFailedStartup(in directory: URL, check: (Bool, String) throws -> Void) async throws {
        let fm = FileManager.default
        let seed = NativeStore(directory: directory.appendingPathComponent("Seed"), secretStore: MemorySecretStore())
        let gear = try seed.commit("gear", ["name":"Startup repair fixture", "type":"Bike"])
        let repairedBytes = try seed.state.jsonData()
        let invalid: [(String, Data)] = [
            ("brokenJSON", Data("{\"unfinished\":\n".utf8)),
            ("null", Data("null".utf8)),
            ("emptyObject", Data("{}".utf8)),
            ("missingActivities", Data("{\"gears\":[]}".utf8)),
            ("wrongGears", Data("{\"gears\":{},\"activities\":[]}".utf8)),
            ("wrongEvents", Data("{\"gears\":[],\"activities\":[],\"events\":{}}".utf8)),
            ("invalidReminder", Data("{\"gears\":[],\"activities\":[],\"events\":[],\"reminders\":[{}]}".utf8))
        ]
        for (name, bytes) in invalid {
            let root = directory.appendingPathComponent(name), file = root.appendingPathComponent("state-v2.json")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try bytes.write(to: file)
            try repairedBytes.write(to: root.appendingPathComponent("state.json"))
            let store = NativeStore(directory: root, secretStore: MemorySecretStore("fixture-startup-key"))
            try check(!store.hasLoadedState && store.loadingFailure != nil && !store.connected && store.gears.isEmpty,
                      "startupRejectsInvalidLibrary-" + name)
            var rejected = false
            do { try store.reloadLocalState() } catch { rejected = true }
            try check(rejected && !store.hasLoadedState && (try Data(contentsOf: file)) == bytes &&
                      (try Data(contentsOf: root.appendingPathComponent("state.json"))) == repairedBytes,
                      "startupFailedRetryPreservesSourceAndDoesNotFallback-" + name)
        }
        for (name, raw) in try NativeStartupFormatFixtures.buildRejectedStates(modern: seed.state) {
            let root = directory.appendingPathComponent("Format-" + name), file = root.appendingPathComponent("state-v2.json")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let bytes = Data(" \n".utf8) + (try raw.jsonData()) + Data("\n".utf8)
            try bytes.write(to: file); try repairedBytes.write(to: root.appendingPathComponent("state.json"))
            let store = NativeStore(directory: root, secretStore: MemorySecretStore())
            try check(!store.hasLoadedState && store.loadingFailure != nil && store.gears.isEmpty,
                      "startupRejectsIncompleteFormat-" + name)
            var rejected = false
            do { try store.reloadLocalState() } catch { rejected = true }
            try check(rejected && !store.hasLoadedState && (try Data(contentsOf: file)) == bytes &&
                      (try Data(contentsOf: root.appendingPathComponent("state.json"))) == repairedBytes &&
                      !fm.fileExists(atPath: root.appendingPathComponent("Recovery").path),
                      "startupIncompleteFormatPreservesExactBytes-" + name)
        }

        let root = directory.appendingPathComponent("Guarded"), file = root.appendingPathComponent("state-v2.json")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let broken = invalid[0].1
        try broken.write(to: file)
        let secrets = MemorySecretStore("fixture-startup-key")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NativeFixtureProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let store = NativeStore(directory: root, secretStore: secrets, session: session)
        func blocks(_ operation: () throws -> Void) -> Bool {
            do { try operation(); return false }
            catch { return (error as? DomainError)?.message == store.loadingFailure }
        }
        try check(blocks { try store.commit("gear", ["name":"Must not save", "type":"Bike"]) }, "startupFailureBlocksCommit")
        try check(blocks { _ = try store.exportBackup() }, "startupFailureBlocksExport")
        try check(blocks { try store.replaceReminders([]) }, "startupFailureBlocksReminderWrites")
        try check(blocks { _ = try store.addImage(Data(), owner: "gear", id: gear.id) }, "startupFailureBlocksImageBeforeDecode")
        var readImage = false, blockedImage = false
        do { _ = try await store.importImages(count: 1, owner: "gear", id: gear.id) { _ in readImage = true; return Data() } }
        catch { blockedImage = (error as? DomainError)?.message == store.loadingFailure }
        try check(blockedImage && !readImage, "startupFailureBlocksPhotoLoader")
        var preparedAttachment = false, blockedAttachment = false
        store.prepareAttachmentForTesting = { throw DomainError("Startup attachment preparation must not run") }
        do { try await store.addAttachment(from: root.appendingPathComponent("Missing.pdf"), gearID: gear.id); preparedAttachment = true }
        catch { blockedAttachment = (error as? DomainError)?.message == store.loadingFailure }
        try check(blockedAttachment && !preparedAttachment && !fm.fileExists(atPath: root.appendingPathComponent("media").path), "startupFailureBlocksAttachmentBeforePreparation")
        NativeFixtureProtocol.configure(target: "bike1")
        var blockedConnect = false
        do { try await store.connect("fixture-new-key") } catch { blockedConnect = (error as? DomainError)?.message == store.loadingFailure }
        // Exercise readiness independently of the initial connected=false state.
        store.connected = true
        store.startSync(); await store.sync(); await store.automaticTick()
        await store.flushNotifications(); store.refreshNotifications()
        try check(blockedConnect && NativeFixtureProtocol.readRequestCount() == 0 && !store.busy && !store.refreshingGears,
                  "startupFailureBlocksConnectManualAndBackgroundSyncBeforeRequest")
        try check(secrets.read() == "fixture-startup-key" && (try Data(contentsOf: file)) == broken && !store.hasLoadedState,
                  "startupBlockedOperationsKeepOriginalFileAndCredentials")
        store.connected = false
        try repairedBytes.write(to: file, options: .atomic)
        try store.reloadLocalState()
        try check(store.hasLoadedState && store.loadingFailure == nil && !store.connected && store.state["nativeRequiresConnection"].flag && store.gear(gear.id)["name"].text == "Startup repair fixture",
                  "startupRepairedFileCanReloadButRequiresExplicitConnection")
        let restarted = NativeStore(directory: root, secretStore: secrets, session: session)
        try check(restarted.hasLoadedState && !restarted.connected && restarted.state["nativeRequiresConnection"].flag,
                  "startupRepairedRetryConnectionRequirementSurvivesRestart")
        try store.commit("hidden", ["id":gear["id"], "hidden":true])
        try check(store.gear(gear.id)["hidden"].flag && secrets.read() == "fixture-startup-key", "startupSuccessfulRetryRestoresWritesWithoutChangingCredentials")
        try broken.write(to: file, options: .atomic)
        var healthyReloadFailed = false
        do { try store.reloadLocalState() } catch { healthyReloadFailed = true }
        try check(healthyReloadFailed && !store.hasLoadedState && blocks { try store.replaceReminders([]) } && (try Data(contentsOf: file)) == broken,
                  "startupLaterReadFailureRelocksPreviouslyLoadedStore")

        let legacyRoot = directory.appendingPathComponent("Legacy"), legacyFile = legacyRoot.appendingPathComponent("state.json")
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let legacy = try NativeStartupFormatFixtures.buildPrototype()
        let legacyBytes = Data(" \n".utf8) + (try legacy.jsonData()) + Data("\n".utf8); try legacyBytes.write(to: legacyFile)
        let migrated = NativeStore(directory: legacyRoot, secretStore: MemorySecretStore())
        try check(migrated.hasLoadedState && migrated.gear("legacy-bike")["name"].text == "Legacy fixture" && (try Data(contentsOf: legacyFile)) == legacyBytes,
                  "startupStillMigratesOriginalSwiftLibrary")
        try check(NativeStartupFormatFixtures.hasMigratedPrototypeDetails(migrated), "startupPrototypePreservesIdentifiersParentUTCAndSnapshot")
        let package = try GearBackupArchive.create(state: migrated.state, media: legacyRoot.appendingPathComponent("media"), in: legacyRoot.appendingPathComponent("TestPackages"))
        let validated = try GearBackupArchive.validate(at: package)
        let restored = NativeStore(directory: directory.appendingPathComponent("RestoredPrototype"), secretStore: MemorySecretStore())
        _ = try restored.beginBackupRestore()
        do { try restored.applyRestoredBackup(validated.state); restored.endBackupRestore() }
        catch { restored.endBackupRestore(); throw error }
        try check(NativeStartupFormatFixtures.hasMigratedPrototypeDetails(restored) && restored.state["events"] == migrated.state["events"],
                  "prototypeMigrationPackageRestorePreservesHistory")
        let fullOriginal = try migrated.preservedSourceURL.map { try Data(contentsOf: $0) }
        try check(fullOriginal == legacyBytes && migrated.preservedSourceURL?.lastPathComponent == "state.json" &&
                  migrated.preservedSourceURL?.deletingLastPathComponent().lastPathComponent.hasPrefix("Original-") == true,
                  "prototypeMigrationPreservesExactOriginalBytes-legacy-full")
        let emptyLegacyRoot = directory.appendingPathComponent("EmptyLegacy"), emptyLegacyFile = emptyLegacyRoot.appendingPathComponent("state-v2.json")
        try fm.createDirectory(at: emptyLegacyRoot, withIntermediateDirectories: true)
        let emptyLegacyBytes = Data("\n ".utf8) + (try NativeStartupFormatFixtures.buildPrototype(empty: true).jsonData()) + Data("\n".utf8)
        try emptyLegacyBytes.write(to: emptyLegacyFile)
        let emptyMigrated = NativeStore(directory: emptyLegacyRoot, secretStore: MemorySecretStore())
        try check(emptyMigrated.hasLoadedState && emptyMigrated.gears.isEmpty && emptyMigrated.activities.isEmpty, "startupPrototypeEmptyLibraryStillLoads")
        let emptyOriginal = try emptyMigrated.preservedSourceURL.map { try Data(contentsOf: $0) }
        try check(emptyOriginal == emptyLegacyBytes && emptyMigrated.preservedSourceURL?.lastPathComponent == "state-v2.json" &&
                  emptyMigrated.preservedSourceURL?.deletingLastPathComponent().lastPathComponent.hasPrefix("Original-") == true &&
                  (try Value.decode(Data(contentsOf: emptyLegacyFile)))["events"] == [],
                  "prototypeMigrationPreservesExactOriginalBytes-v2-empty")
        let worker = NativeBackupWorker()
        let fullVersions = await worker.localVersions(legacyRoot), emptyVersions = await worker.localVersions(emptyLegacyRoot)
        let fullFiles = try fm.contentsOfDirectory(at: legacyRoot.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        let emptyFiles = try fm.contentsOfDirectory(at: emptyLegacyRoot.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        try check(fullVersions.isEmpty && emptyVersions.isEmpty &&
                  !fullFiles.contains { $0.pathExtension == GearBackupArchive.fileExtension } &&
                  !emptyFiles.contains { $0.pathExtension == GearBackupArchive.fileExtension },
                  "prototypeMigrationDoesNotListUnrestorablePackages")

        let blockedRoot = directory.appendingPathComponent("BlockedPrototypeCopy"), blockedSource = blockedRoot.appendingPathComponent("state.json")
        try fm.createDirectory(at: blockedRoot, withIntermediateDirectories: true)
        try legacyBytes.write(to: blockedSource)
        let blockedRecovery = blockedRoot.appendingPathComponent("Recovery"), marker = Data("keep blocked copy location".utf8)
        try marker.write(to: blockedRecovery)
        let blocked = NativeStore(directory: blockedRoot, secretStore: MemorySecretStore())
        try check(!blocked.hasLoadedState && blocked.loadingFailure != nil && blocked.preservedSourceURL == nil &&
                  (try Data(contentsOf: blockedSource)) == legacyBytes && (try Data(contentsOf: blockedRecovery)) == marker &&
                  !fm.fileExists(atPath: blockedRoot.appendingPathComponent("state-v2.json").path),
                  "prototypeMigrationCopyFailurePreventsV2Write")
        try fm.removeItem(at: blockedRecovery)
        try blocked.reloadLocalState()
        let repairedOriginal = try blocked.preservedSourceURL.map { try Data(contentsOf: $0) }
        try check(NativeStartupFormatFixtures.hasMigratedPrototypeDetails(blocked) && repairedOriginal == legacyBytes &&
                  (try Data(contentsOf: blockedSource)) == legacyBytes && blocked.state["nativeRequiresConnection"].flag,
                  "prototypeMigrationRetriesAfterCopyRepair")
        let fresh = NativeStore(directory: directory.appendingPathComponent("Absent"), secretStore: MemorySecretStore())
        try check(fresh.hasLoadedState && fresh.loadingFailure == nil && fresh.gears.isEmpty, "startupMissingFilesInitializeFreshLibrary")
    }
    private static func verifyAttachmentImport(in directory: URL, check: (Bool, String) throws -> Void) async throws {
        let fm = FileManager.default
        let sources = directory.appendingPathComponent("Sources")
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 250)).pdfData { context in
            context.beginPage()
            ("Synthetic attachment receipt" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font:UIFont.systemFont(ofSize: 20)])
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1800), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1800))
        }
        guard let png = image.pngData() else { throw DomainError("Self-test attachment image unavailable") }
        let pdfURL = sources.appendingPathComponent("Receipt.pdf"), imageURL = sources.appendingPathComponent("Attachment.png")
        try pdf.write(to: pdfURL); try png.write(to: imageURL)
        func mediaFiles(_ store: NativeStore) -> Set<URL> {
            Set((try? fm.contentsOfDirectory(at: store.directory.appendingPathComponent("media"), includingPropertiesForKeys: nil)) ?? [])
        }
        let successful = NativeStore(directory: directory.appendingPathComponent("Success"), secretStore: MemorySecretStore())
        let gear = try successful.commit("gear", ["name":"Fixture Attachment Gear", "type":"Bike"])
        try await successful.addAttachment(from: pdfURL, gearID: gear.id)
        try await successful.addAttachment(from: imageURL, gearID: gear.id)
        let saved = successful.state["attachments"].array
        try check(saved.count == 2 && saved[0]["contentType"] == "application/pdf" && saved[1]["contentType"] == "image/jpeg", "asyncAttachmentPreservesPDFAndNormalizesImage")
        let savedPDF = try successful.attachmentURL(saved[0]), savedImage = try successful.attachmentURL(saved[1])
        let jpeg = try Data(contentsOf: savedImage)
        try check(try Data(contentsOf: savedPDF) == pdf && UIImage(data: jpeg)?.cgImage?.width == 2560 && UIImage(data: jpeg)?.cgImage?.height == 1536,
                  "asyncAttachmentPreservesPDFBytesAndImageBounds")
        try check(try Data(contentsOf: pdfURL) == pdf && Data(contentsOf: imageURL) == png, "asyncAttachmentKeepsSourceFiles")
        let reopened = NativeStore(directory: successful.directory, secretStore: MemorySecretStore())
        try check(reopened.state["attachments"] == successful.state["attachments"] && mediaFiles(reopened) == mediaFiles(successful), "asyncAttachmentPersistsAcrossRestart")

        for mode in ["json", "package"] {
            let store = NativeStore(directory: directory.appendingPathComponent("BetweenItems-" + mode), secretStore: MemorySecretStore())
            let gear = try store.commit("gear", ["name":"Fixture Attachment Gear", "type":"Bike"])
            let generation = store.imageImportGeneration
            try await store.addAttachment(from: pdfURL, gearID: gear.id, expectedGeneration: generation)
            let beforeFiles = mediaFiles(store), saved = store.state["attachments"]
            if mode == "json" { try store.importBackup(store.exportBackup()) }
            else {
                let package = try GearBackupArchive.create(state: store.state, media: store.directory.appendingPathComponent("media"), in: store.directory.appendingPathComponent("Packages"))
                let version = NativeBackupVersion(manifest: try GearBackupArchive.manifest(at: package), url: package, uploaded: true, local: true)
                let restored = await store.cloudBackup.restore(version)
                try check(restored, "asyncAttachmentRestoresBetweenSelectedItems")
            }
            let restored = store.state
            // A different failure proves that the stale selection never reaches preparation.
            store.prepareAttachmentForTesting = { throw URLError(.unsupportedURL) }
            var rejectedBeforePreparation = false
            do { try await store.addAttachment(from: imageURL, gearID: gear.id, expectedGeneration: generation) }
            catch { rejectedBeforePreparation = (error as? DomainError)?.message == "无法添加附件，请重新选择文件。" }
            store.prepareAttachmentForTesting = nil
            try check(rejectedBeforePreparation && store.state == restored && store.state["attachments"] == saved && mediaFiles(store) == beforeFiles,
                      "asyncAttachmentRejectsRestoredSelectionBeforeNextItem-" + mode)
            try check(try Data(contentsOf: store.attachmentURL(saved.array[0])) == pdf, "asyncAttachmentKeepsEarlierSelectedFile-" + mode)
        }

        for phase in ["prepare", "write"] {
            for scenario in ["cancelled", "jsonRestored", "packageRestored", "ownerDeleted", "snapshot", "restoreLocked", "unrelatedEdit"] {
                let store = NativeStore(directory: directory.appendingPathComponent(phase + "-" + scenario), secretStore: MemorySecretStore())
                let gear = try store.commit("gear", ["name":"Fixture Attachment Gear", "type":"Bike"])
                try await store.addAttachment(from: pdfURL, gearID: gear.id)
                let beforeRecords = store.state["attachments"], beforeFiles = mediaFiles(store), backup = try store.exportBackup()
                let gate = NativeAttachmentOperationGate()
                if phase == "prepare" {
                    store.prepareAttachmentForTesting = {
                        await gate.pause(offMain: !Thread.isMainThread)
                        await gate.recordCancellation(Task.isCancelled)
                    }
                } else {
                    store.afterWritingAttachmentForTesting = { url in
                        await gate.pause(destination: url, offMain: !Thread.isMainThread)
                        await gate.recordCancellation(Task.isCancelled)
                    }
                }
                var finished = false, locked = false
                let operation = Task {
                    defer { finished = true }
                    try await store.addAttachment(from: imageURL, gearID: gear.id)
                }
                defer { store.prepareAttachmentForTesting = nil; store.afterWritingAttachmentForTesting = nil }
                do {
                    try await gate.waitUntilPaused()
                    let offMain = await gate.readOffMain()
                    let destination = await gate.readDestination()
                    try check(offMain && store.state["attachments"] == beforeRecords, "asyncAttachmentWaitsOffMain-" + phase + "-" + scenario)
                    if phase == "write" {
                        try check(destination.map { fm.fileExists(atPath: $0.path) } == true && mediaFiles(store).count == beforeFiles.count + 1,
                                  "asyncAttachmentStagesFileBeforeCommit-" + scenario)
                    }
                    switch scenario {
                    case "cancelled":
                        operation.cancel()
                        await Task.yield()
                        try check(!finished, "asyncAttachmentCancellationJoinsWorker-" + phase)
                        if let destination { try check(fm.fileExists(atPath: destination.path), "asyncAttachmentDoesNotCleanActiveWriter") }
                    case "jsonRestored": try store.importBackup(backup)
                    case "packageRestored":
                        let package = try GearBackupArchive.create(state: store.state, media: store.directory.appendingPathComponent("media"), in: store.directory.appendingPathComponent("Packages"))
                        let version = NativeBackupVersion(manifest: try GearBackupArchive.manifest(at: package), url: package, uploaded: true, local: true)
                        let restored = await store.cloudBackup.restore(version)
                        try check(restored && store.gear(gear.id).id == gear.id, "asyncAttachmentRestoresSameOwner-" + phase)
                    case "ownerDeleted": try store.commit("delete", ["id":gear["id"]])
                    case "snapshot": store.snapshotDate = NativeDate.today
                    case "restoreLocked": _ = try store.beginBackupRestore(); locked = true
                    default: try store.commit("hidden", ["id":gear["id"], "hidden":true])
                    }
                    let expected = store.state
                    await gate.resume()
                    let result = await operation.result
                    if locked { store.endBackupRestore(); locked = false }
                    if scenario == "unrelatedEdit" {
                        guard case .success = result else { throw DomainError("Self-test attachment unrelated edit rejected") }
                        let records = store.state["attachments"].array
                        try check(records.count == 2 && records[0] == beforeRecords.array[0] && store.gear(gear.id)["hidden"].flag,
                                  "asyncAttachmentAllowsUnrelatedEdits-" + phase)
                        let expectedFiles = try Set(records.map { try store.attachmentURL($0) })
                        try check(mediaFiles(store) == expectedFiles && store.state["revision"].integer == expected["revision"].integer + 1,
                                  "asyncAttachmentCommitsOnlyPreparedFile-" + phase)
                    } else {
                        guard case .failure(let failure) = result else { throw DomainError("Self-test stale attachment unexpectedly committed") }
                        if scenario == "cancelled" {
                            let workerCancelled = await gate.readCancellation()
                            try check(failure is CancellationError && workerCancelled, "asyncAttachmentCancellationPropagates-" + phase)
                        }
                        try check(store.state == expected && store.state["attachments"] == beforeRecords && mediaFiles(store) == beforeFiles,
                                  "asyncAttachmentRejectsWithoutOrphans-" + phase + "-" + scenario)
                    }
                    try check(try Data(contentsOf: store.attachmentURL(beforeRecords.array[0])) == pdf,
                              "asyncAttachmentKeepsExistingBytes-" + phase + "-" + scenario)
                } catch {
                    operation.cancel(); await gate.resume(); _ = await operation.result
                    if locked { store.endBackupRestore() }
                    throw error
                }
            }
        }

        let share = try await NativeAttachmentFiles.prepareShare(pdfURL, name: "Receipt.pdf")
        try check(try Data(contentsOf: share) == pdf && share.lastPathComponent == "Receipt.pdf", "attachmentShareCopiesOriginalBytes")
        try fm.removeItem(at: share.deletingLastPathComponent())
        let shareGate = NativeAttachmentOperationGate()
        var shareFinished = false
        let sharing = Task {
            defer { shareFinished = true }
            return try await NativeAttachmentFiles.prepareShare(pdfURL, name: "Receipt.pdf") { url in
                await shareGate.pause(destination: url, offMain: !Thread.isMainThread)
                await shareGate.recordCancellation(Task.isCancelled)
            }
        }
        do {
            try await shareGate.waitUntilPaused()
            guard let copied = await shareGate.readDestination() else { throw DomainError("Self-test share copy missing") }
            sharing.cancel(); await Task.yield()
            try check(!shareFinished && fm.fileExists(atPath: copied.path), "attachmentShareCancellationJoinsWorker")
            await shareGate.resume()
            let result = await sharing.result
            guard case .failure(let failure) = result else { throw DomainError("Self-test cancelled share unexpectedly published") }
            let workerCancelled = await shareGate.readCancellation()
            try check(failure is CancellationError && workerCancelled && !fm.fileExists(atPath: copied.deletingLastPathComponent().path), "attachmentShareCancellationRemovesTemporaryDirectory")
            try check(try Data(contentsOf: pdfURL) == pdf, "attachmentShareCancellationKeepsSource")
        } catch {
            sharing.cancel(); await shareGate.resume(); _ = await sharing.result
            throw error
        }
    }

    private static func verifyImageImport(in directory: URL, bytes: Data, check: (Bool, String) throws -> Void) async throws {
        let parityStore = NativeStore(directory: directory.appendingPathComponent("Parity"), secretStore: MemorySecretStore())
        let parityGear = try parityStore.commit("gear", ["name":"Fixture Image Gear", "type":"Bike"])
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1800), format: format).image { context in
            UIColor.systemBlue.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1500, height: 1800))
        }
        guard let source = image.pngData() else { throw DomainError("无法创建图片预览。") }
        let syncID = try parityStore.addImage(source, owner: "gear", id: parityGear.id)
        let parityGate = NativeImagePreparationGate()
        parityStore.prepareImageForTesting = { data in
            do {
                let prepared = try NativeImageFiles.prepareImage(data)
                await parityGate.pause(preparedOffMain: !Thread.isMainThread)
                return prepared
            } catch { await parityGate.failPreparation(); throw error }
        }
        let importing = Task { try await parityStore.importImage(source, owner: "gear", id: parityGear.id) }
        await parityGate.waitUntilPrepared()
        await parityGate.resume()
        let asyncID = try await importing.value
        parityStore.prepareImageForTesting = nil
        try check(await parityGate.readPreparedOffMain(), "asyncImagePreparationRunsOffMain")
        let syncPhoto = parityStore.state["photos"].array.first { $0.id == syncID }!
        let asyncPhoto = parityStore.state["photos"].array.first { $0.id == asyncID }!
        try check(["width", "height", "bytes", "hash"].allSatisfy { syncPhoto[$0] == asyncPhoto[$0] }, "asyncImageMetadataMatchesSync")
        try check(try Data(contentsOf: parityStore.photoURL(syncID)) == Data(contentsOf: parityStore.photoURL(asyncID)), "asyncImageJPEGMatchesSync")
        try check(asyncPhoto["width"].double == 2560 && asyncPhoto["height"].double == 1536, "asyncImageKeepsSizeLimit")

        for mode in ["json", "package"] {
            let store = NativeStore(directory: directory.appendingPathComponent("BetweenItems-" + mode), secretStore: MemorySecretStore())
            let gear = try store.commit("gear", ["name":"Fixture Image Gear", "type":"Bike"])
            let generation = store.imageImportGeneration, before = store.state
            if mode == "json" { try store.importBackup(store.exportBackup()) }
            else {
                _ = try store.beginBackupRestore()
                do { try store.applyRestoredBackup(before) }
                catch { store.endBackupRestore(); throw error }
                store.endBackupRestore()
            }
            let restored = store.state
            // This different error identifies an unexpected preparation attempt.
            store.prepareImageForTesting = { _ in throw URLError(.unsupportedURL) }
            var rejectedBeforePreparation = false
            do { _ = try await store.importImage(bytes, owner: "gear", id: gear.id, expectedGeneration: generation) }
            catch { rejectedBeforePreparation = error is DomainError }
            store.prepareImageForTesting = nil
            let files = (try? FileManager.default.contentsOfDirectory(at: store.directory.appendingPathComponent("media"), includingPropertiesForKeys: nil)) ?? []
            try check(rejectedBeforePreparation && store.state == restored && store.state["photos"].array.isEmpty && files.isEmpty,
                      "asyncImageRejectsRestoredBatchBeforeNextItem-" + mode)
        }

        for scenario in ["cancelled", "ownerDeleted", "restoreLocked", "jsonRestored", "packageRestored", "snapshot", "unrelatedEdit"] {
            let store = NativeStore(directory: directory.appendingPathComponent(scenario), secretStore: MemorySecretStore())
            let gear = try store.commit("gear", ["name":"Fixture Image Gear", "type":"Bike"])
            let backup = try store.exportBackup(), before = store.state
            let gate = NativeImagePreparationGate()
            store.prepareImageForTesting = { data in
                do {
                    let prepared = try NativeImageFiles.prepareImage(data)
                    await gate.pause(preparedOffMain: !Thread.isMainThread)
                    return prepared
                } catch { await gate.failPreparation(); throw error }
            }
            let operation = Task { try await store.importImage(bytes, owner: "gear", id: gear.id) }
            await gate.waitUntilPrepared()
            var locked = false
            do {
                switch scenario {
                case "cancelled": operation.cancel()
                case "ownerDeleted": try store.commit("delete", ["id": gear["id"]])
                case "restoreLocked": _ = try store.beginBackupRestore(); locked = true
                case "jsonRestored": try store.importBackup(backup)
                case "packageRestored":
                    _ = try store.beginBackupRestore(); locked = true
                    try store.applyRestoredBackup(before)
                    store.endBackupRestore(); locked = false
                case "snapshot": store.snapshotDate = NativeDate.today
                default: try store.commit("hidden", ["id": gear["id"], "hidden": true])
                }
            } catch {
                operation.cancel(); await gate.resume(); _ = await operation.result
                if locked { store.endBackupRestore() }
                throw error
            }
            await gate.resume()
            let result = await operation.result
            if locked { store.endBackupRestore() }
            store.prepareImageForTesting = nil
            let files = (try? FileManager.default.contentsOfDirectory(at: store.directory.appendingPathComponent("media"), includingPropertiesForKeys: nil)) ?? []
            if scenario == "unrelatedEdit" {
                guard case .success(let id) = result else { throw DomainError("asyncImageUnrelatedEditExpectedSuccess") }
                try check(store.state["photos"].array.count == 1 && files == [store.photoURL(id)] && store.gear(gear.id)["hidden"].flag, "asyncImageAllowsUnrelatedEdits")
            } else {
                guard case .failure(let failure) = result else { throw DomainError("asyncImageExpectedFailure-" + scenario) }
                if scenario == "cancelled" { try check(failure is CancellationError, "asyncImageCancellationPropagates") }
                try check(store.state["photos"].array.isEmpty && files.isEmpty, "asyncImageRejects-" + scenario + "-WithoutOrphans")
            }
        }
        try await verifyImageBatchImport(in: directory.appendingPathComponent("Batches"), bytes: bytes, check: check)
        try await verifyPhotoReadCancellation(in: directory.appendingPathComponent("PhotoReadCancellation"), bytes: bytes, check: check)
    }
    private static func verifyImageBatchImport(in directory: URL, bytes: Data, check: (Bool, String) throws -> Void) async throws {
        func mediaFiles(_ store: NativeStore) -> Set<URL> {
            Set((try? FileManager.default.contentsOfDirectory(at: store.directory.appendingPathComponent("media"), includingPropertiesForKeys: nil)) ?? [])
        }
        let successful = NativeStore(directory: directory.appendingPathComponent("Success"), secretStore: MemorySecretStore())
        let gear = try successful.commit("gear", ["name":"Fixture Batch Gear", "type":"Bike"])
        let revision = successful.state["revision"].integer, refreshes = successful.viewGeneration
        var loaded: [Int] = []
        let ids = try await successful.importImages(count: 2, owner: "gear", id: gear.id) { index in
            loaded.append(index)
            try check(successful.state["photos"].array.isEmpty, "asyncImageBatchDoesNotCommitWhileLoading")
            return bytes
        }
        try check(loaded == [0, 1] && successful.state["photos"].array.map(\.id) == ids && mediaFiles(successful) == Set(ids.map(successful.photoURL)),
                  "asyncImageBatchLoadsSequentiallyAndKeepsOrder")
        try check(successful.state["revision"].integer == revision + 1 && successful.viewGeneration == refreshes + 1,
                  "asyncImageBatchPersistsAndRefreshesOnce")
        let reopened = NativeStore(directory: successful.directory, secretStore: MemorySecretStore())
        try check(reopened.state["photos"] == successful.state["photos"], "asyncImageBatchPersistsAcrossRestart")

        for scenario in ["secondLoadFailure", "secondPreparationFailure", "cancelledLoadingSecond", "cancelledPreparingSecond", "ownerDeleted", "restoreLocked", "jsonRestored", "packageRestored", "snapshot"] {
            let store = NativeStore(directory: directory.appendingPathComponent(scenario), secretStore: MemorySecretStore())
            let gear = try store.commit("gear", ["name":"Fixture Batch Gear", "type":"Bike"])
            let backup = try store.exportBackup(), before = store.state
            let gate = NativeImagePreparationGate()
            if scenario == "cancelledPreparingSecond" {
                store.prepareImageForTesting = { data in
                    do {
                        let image = try NativeImageFiles.prepareImage(data)
                        if await gate.countPreparation() == 2 { await gate.pause(preparedOffMain: !Thread.isMainThread) }
                        return image
                    } catch { await gate.failPreparation(); throw error }
                }
            }
            let operation = Task {
                try await store.importImages(count: 2, owner: "gear", id: gear.id) { index in
                    if index == 1 && scenario != "cancelledPreparingSecond" {
                        await gate.pause(preparedOffMain: false)
                        if scenario == "secondLoadFailure" { throw DomainError("Fixture second image could not load") }
                        if scenario == "secondPreparationFailure" { return Data() }
                    }
                    return bytes
                }
            }
            await gate.waitUntilPrepared()
            var locked = false
            do {
                try check(store.state["photos"].array.isEmpty && mediaFiles(store).count == 1, "asyncImageBatchStagesFirstBefore-" + scenario)
                switch scenario {
                case "cancelledLoadingSecond", "cancelledPreparingSecond": operation.cancel()
                case "ownerDeleted": try store.commit("delete", ["id": gear["id"]])
                case "restoreLocked": _ = try store.beginBackupRestore(); locked = true
                case "jsonRestored": try store.importBackup(backup)
                case "packageRestored":
                    _ = try store.beginBackupRestore(); locked = true
                    try store.applyRestoredBackup(before)
                    store.endBackupRestore(); locked = false
                case "snapshot": store.snapshotDate = NativeDate.today
                default: break
                }
            } catch {
                operation.cancel(); await gate.resume(); _ = await operation.result
                if locked { store.endBackupRestore() }
                throw error
            }
            let expected = store.state
            await gate.resume()
            let result = await operation.result
            if locked { store.endBackupRestore() }
            store.prepareImageForTesting = nil
            guard case .failure(let error) = result else { throw DomainError("asyncImageBatchExpectedFailure-" + scenario) }
            if scenario.hasPrefix("cancelled") { try check(error is CancellationError, "asyncImageBatchCancellationPropagates-" + scenario) }
            try check(store.state == expected && store.state["photos"].array.isEmpty && mediaFiles(store).isEmpty,
                      "asyncImageBatchRollsBackAllFiles-" + scenario)
        }

        let limited = NativeStore(directory: directory.appendingPathComponent("Limit"), secretStore: MemorySecretStore())
        let limitedGear = try limited.commit("gear", ["name":"Fixture Batch Gear", "type":"Bike"])
        _ = try await limited.importImages(count: 39, owner: "gear", id: limitedGear.id) { _ in bytes }
        let beforeLimit = limited.state, beforeFiles = mediaFiles(limited)
        var rejected = false
        do { _ = try await limited.importImages(count: 2, owner: "gear", id: limitedGear.id) { _ in bytes } }
        catch { rejected = true }
        try check(rejected && limited.state == beforeLimit && mediaFiles(limited) == beforeFiles,
                  "asyncImageBatchOverLimitPreservesExistingFiles")
        for count in [0, 41] {
            var loaded = false, rejected = false
            do {
                _ = try await limited.importImages(count: count, owner: "gear", id: limitedGear.id) { _ in loaded = true; return bytes }
            } catch { rejected = true }
            try check(rejected && !loaded && limited.state == beforeLimit && mediaFiles(limited) == beforeFiles,
                      "asyncImageBatchRejectsCountBeforeLoading-" + String(count))
        }
    }
    private static func verifyPhotoReadCancellation(in directory: URL, bytes: Data, check: (Bool, String) throws -> Void) async throws {
        let synchronousProgress = Progress(totalUnitCount: 1)
        let synchronous = try await NativePhotoDataLoader.loadData { completion in
            completion(.success(bytes))
            completion(.failure(DomainError("Fixture duplicate callback")))
            return synchronousProgress
        }
        try check(synchronous == bytes && !synchronousProgress.isCancelled, "photoReadSynchronousCallbackCompletesOnlyOnce")

        let beforeInstall = NativePhotoDataRequest()
        beforeInstall.cancelRequest()
        beforeInstall.finishRequest(.success(bytes))
        let installedProgress = Progress(totalUnitCount: 1)
        beforeInstall.installProgress(installedProgress)
        let preCancelled = Task<Data?, Error> {
            try await withCheckedThrowingContinuation { beforeInstall.installContinuation($0) }
        }
        guard case .failure(let preCancelError) = await preCancelled.result else { throw DomainError("photoReadExpectedCancellationBeforeInstall") }
        try check(preCancelError is CancellationError && installedProgress.isCancelled, "photoReadCancellationBeforeInstallCancelsLateProgress")
        let neverStarted = NativePhotoTransferProbe()
        let cancelledBeforeStart = Task { try await NativePhotoDataLoader.loadData { neverStarted.startRequest($0) } }
        cancelledBeforeStart.cancel()
        guard case .failure(let beforeStartError) = await cancelledBeforeStart.result else { throw DomainError("photoReadExpectedCancellationBeforeStart") }
        try check(beforeStartError is CancellationError && !neverStarted.readStarted(), "photoReadAlreadyCancelledTaskDoesNotStartProvider")

        for callbackOnCancel in [false, true] {
            let probe = NativePhotoTransferProbe()
            if callbackOnCancel {
                probe.progress.cancellationHandler = { [weak probe] in probe?.finishRequest(.success(bytes)) }
            }
            let loading = Task { try await NativePhotoDataLoader.loadData { probe.startRequest($0) } }
            await probe.waitUntilStarted()
            loading.cancel()
            guard case .failure(let error) = await loading.result else { throw DomainError("photoReadExpectedCancellation") }
            try check(error is CancellationError && probe.progress.isCancelled,
                      callbackOnCancel ? "photoReadSynchronousCancelCallbackCannotWin" : "photoReadCancellationDoesNotWaitForProviderCallback")
            probe.finishRequest(.success(bytes))
            probe.finishRequest(.failure(DomainError("Fixture late duplicate callback")))
            probe.progress.cancellationHandler = nil
        }
        var nilRejected = false
        do { _ = try await NativePhotoDataLoader.loadData { completion in completion(.success(nil)); return Progress(totalUnitCount: 1) } }
        catch { nilRejected = error is DomainError }
        try check(nilRejected, "photoReadUnsupportedDataReportsFailure")

        let store = NativeStore(directory: directory, secretStore: MemorySecretStore())
        let gear = try store.commit("gear", ["name":"Fixture Event Photo Gear", "type":"Bike"])
        let savedDraft = UUID().uuidString.lowercased(), editingDraft = UUID().uuidString.lowercased()
        let savedPhoto = try store.addImage(bytes, owner: "draft", id: savedDraft, gearID: gear.id)
        try store.commit("event-save", ["requestId":.string(UUID().uuidString), "event":["gearId":gear["id"], "kind":"maintenance", "occurredDate":"2024-01-01", "notes":"Original saved notes", "photoDraftId":.string(savedDraft), "photoIds":[.string(savedPhoto)]]])
        let draftPhoto = try store.addImage(bytes, owner: "draft", id: editingDraft, gearID: gear.id)
        var selected = [savedPhoto, draftPhoto]
        let originalSelection = selected, originalState = store.state
        let media = store.directory.appendingPathComponent("media")
        let originalFiles = Set(try FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil))
        let secondRead = NativePhotoTransferProbe()
        let importing = Task {
            let added = try await store.importImages(count: 2, owner: "draft", id: editingDraft, gearID: gear.id) { index in
                if index == 0 { return bytes }
                return try await NativePhotoDataLoader.loadData { secondRead.startRequest($0) }
            }
            selected.append(contentsOf: added)
        }
        await secondRead.waitUntilStarted()
        do {
            try check(store.state == originalState && (try FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)).count == originalFiles.count + 1,
                      "photoReadSecondItemWaitKeepsFirstUncommitted")
        } catch {
            importing.cancel(); _ = await importing.result
            throw error
        }
        importing.cancel()
        guard case .failure(let error) = await importing.result else { throw DomainError("photoReadExpectedBatchCancellation") }
        let cleanedFiles = Set(try FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil))
        try check(error is CancellationError && secondRead.progress.isCancelled && selected == originalSelection && store.state == originalState && cleanedFiles == originalFiles,
                  "photoReadCancelledBatchPreservesSavedAndDraftPhotosAndSelection")
        secondRead.finishRequest(.success(bytes))
        secondRead.finishRequest(.success(bytes))
        try check(store.state == originalState && selected == originalSelection, "photoReadLateCallbackDoesNotAppendOrCommit")
        let retried = try await store.importImages(count: 1, owner: "draft", id: editingDraft, gearID: gear.id) { _ in bytes }
        selected.append(contentsOf: retried)
        try check(selected == originalSelection + retried && store.state["photos"].array.count == originalState["photos"].array.count + 1,
                  "photoReadCanRetryAfterCancellation")
    }
    static func seedDuplicateChoicesPreview(_ store: NativeStore) {
        guard store.directory.lastPathComponent == "GearhousePreview", !store.gears.contains(where: { $0["name"].text == "备用锁鞋" }) else { return }
        do {
            for (name, type) in [("备用车", "Bike"), ("备用锁鞋", "CyclingShoes"), ("备用骑行台", "Trainer")] {
                for _ in 0..<2 { try store.commit("gear", ["name": .string(name), "type": .string(type)]) }
            }
        } catch { store.error = error.userFacingMessage }
    }
    static func seedReplacementEditPreview(_ store: NativeStore) throws -> Value {
        guard store.directory.lastPathComponent == "GearhousePreview" else { throw DomainError("预览不可用") }
        if let operation = store.state["gearOperations"].array.first(where: { $0["gearId"].text == "clii" && $0["kind"].text == "replace" }) { return operation }
        let replacement = try store.commit("gear", ["name": "备用轮组", "categoryId": "Wheelset", "placement": "stock",
                                                   "purchased": .string(NativeDate.shift(NativeDate.today, -3))])
        return try store.commit("inventory-save", [
            "kind": "replace", "gearId": "clii", "replacementId": replacement["id"],
            "at": .string(NativeDate.shift(NativeDate.today, -2)), "destination": "stock", "childIds": ["front"]
        ])
    }
    static func seedInheritedRetirementPreview(_ store: NativeStore, retired: Bool) {
        guard store.directory.lastPathComponent == "GearhousePreview" else { return }
        var gear = store.gear("tarmac")
        gear["retired"] = .bool(retired)
        store.perform("gear", gear)
    }
    static func seedActivityPreview(_ store: NativeStore, scenario: String) {
        guard store.directory.lastPathComponent == "GearhousePreview" else { return }
        do {
            if scenario == "unlinked" {
                try store.commit("gear", ["name":"备用公路车", "type":"Bike"])
                try store.commit("gear-refresh", ["rows":[["id":"demo-new", "name":"Endurance Bike", "type":"Bike"]]])
                try store.commit("sync-rows", ["rows":[["id":"demo-ride", "name":"周末公路骑行", "type":"Ride", "start_date_local":"2026-10-12T07:30:00", "distance":82400, "moving_time":10420, "gear":["id":"demo-new", "name":"Endurance Bike"]]], "from":"2026-10-12", "to":"2026-10-12"])
            } else {
                try store.commit("assignment", ["id":"demo-ride", "assignment":["main":"tarmac", "shoe":"shoes"]])
                try store.commit("write-result", ["id":"demo-ride", "error":"网络已断开，请连接网络后重试。"])
                if scenario == "conflict" { try store.commit("assignment-observe", ["id":"demo-ride", "remoteId":.null]) }
            }
        } catch { store.error = error.userFacingMessage }
    }
    static func seedAttachments(_ store: NativeStore) async {
        guard store.directory.lastPathComponent == "GearhousePreview", store.state["attachments"].array.isEmpty else { return }
        do {
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x:0,y:0,width:400,height:250)).pdfData { context in
                context.beginPage()
                ("Gearhouse Receipt" as NSString).draw(at:CGPoint(x:30,y:40),withAttributes:[.font:UIFont.systemFont(ofSize:24)])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("发票.pdf")
            try pdf.write(to:url)
            defer { try? FileManager.default.removeItem(at:url) }
            try await store.addAttachment(from:url,gearID:"tarmac")
        } catch { store.error = error.userFacingMessage }
    }
    static func seedPhotoFallbackPreview(_ store: NativeStore) {
        guard store.directory.lastPathComponent == "GearhousePreview",
              !store.state["photos"].array.contains(where: { $0["ownerType"].text == "gear" && $0["ownerId"].text == "tarmac" }) else { return }
        do {
            let photos: [(String, UIColor)] = [
                ("b1000000-0000-4000-8000-000000000001", UIColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 1)),
                ("b1000000-0000-4000-8000-000000000002", UIColor(red: 0.95, green: 0.45, blue: 0.10, alpha: 1))
            ]
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            for photo in photos {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 480), format: format).image { renderer in
                    photo.1.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 800, height: 480))
                }
                guard let data = image.jpegData(compressionQuality: 0.9) else { throw DomainError("无法创建图片预览。") }
                let url = store.photoURL(photo.0)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                do {
                    try store.commit("photo-add", ["id": .string(photo.0), "ownerType": "gear", "ownerId": "tarmac", "metadata": [
                        "width": 800, "height": 480, "bytes": .number(Double(data.count)),
                        "hash": .string(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
                    ]])
                } catch { try? FileManager.default.removeItem(at: url); throw error }
            }
        } catch { store.error = error.userFacingMessage }
    }
    static func seedEquipmentPreview(_ store: NativeStore) async {
        guard store.directory.lastPathComponent == "GearhousePreview", store.gear("tarmac")["coverPhotoId"].isNull else { return }
        do {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 720)).image { renderer in
                let context = renderer.cgContext
                UIColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 720))
                UIColor(red: 0.83, green: 0.87, blue: 0.91, alpha: 1).setFill()
                context.fillEllipse(in: CGRect(x: 180, y: 540, width: 850, height: 45))
                context.setStrokeColor(UIColor(red: 0.09, green: 0.13, blue: 0.19, alpha: 1).cgColor)
                context.setLineWidth(16)
                for x in [250, 900] { context.strokeEllipse(in: CGRect(x: x - 142, y: 285, width: 284, height: 284)) }
                context.setStrokeColor(UIColor(red: 0.20, green: 0.42, blue: 0.80, alpha: 1).cgColor)
                context.setLineWidth(19); context.setLineJoin(.round)
                let frame = UIBezierPath()
                frame.move(to: CGPoint(x: 250, y: 427)); frame.addLine(to: CGPoint(x: 525, y: 445))
                frame.addLine(to: CGPoint(x: 416, y: 232)); frame.addLine(to: CGPoint(x: 250, y: 427))
                frame.move(to: CGPoint(x: 416, y: 232)); frame.addLine(to: CGPoint(x: 790, y: 240))
                frame.addLine(to: CGPoint(x: 525, y: 445)); frame.move(to: CGPoint(x: 790, y: 240)); frame.addLine(to: CGPoint(x: 900, y: 427))
                context.addPath(frame.cgPath); context.strokePath()
                context.setStrokeColor(UIColor.darkGray.cgColor); context.setLineWidth(13)
                context.move(to: CGPoint(x: 416, y: 232)); context.addLine(to: CGPoint(x: 400, y: 190))
                context.move(to: CGPoint(x: 790, y: 240)); context.addLine(to: CGPoint(x: 776, y: 178)); context.addLine(to: CGPoint(x: 862, y: 178)); context.addLine(to: CGPoint(x: 880, y: 212)); context.strokePath()
                context.setLineWidth(18); context.move(to: CGPoint(x: 352, y: 184)); context.addLine(to: CGPoint(x: 449, y: 184)); context.strokePath()
                context.setLineWidth(9); context.strokeEllipse(in: CGRect(x: 487, y: 407, width: 76, height: 76))
            }
            if let data = image.jpegData(compressionQuality: 0.9) {
                let id = try store.addImage(data, owner: "gear", id: "tarmac", gearID: "tarmac")
                try store.commit("photo-edit", ["ownerType": "gear", "ownerId": "tarmac", "action": "cover", "id": .string(id)])
            }
            try store.commit("event-save", ["requestId": .string(UUID().uuidString), "event": [
                "gearId": "tarmac", "kind": "maintenance", "occurredDate": .string(NativeDate.shift(NativeDate.today, -1)),
                "notes": "清洁车架，检查螺丝"
            ]])
            var reminder = GearReminder(gearID: "tarmac")
            reminder.title = "检查胎压"; reminder.mode = .date; reminder.date = Date().addingTimeInterval(2 * 86400)
            try store.saveReminder(reminder)
            for _ in 0..<2 { try store.commit("gear", ["name": "L05A-RF", "categoryId": "BrakePads", "placement": "stock", "condition": "unused"]) }
        } catch { store.error = error.userFacingMessage }
    }
    static func seedLongContentPreview(_ store: NativeStore) async {
        guard store.directory.lastPathComponent == "GearhousePreview",
              store.gear("tarmac")["name"].text != "Tarmac SL8 Pro · Shimano Ultegra Di2" else { return }
        await seedEquipmentPreview(store)
        do {
            var backup = try Value.decode(store.exportBackup())
            var state = backup["state"]
            state["gears"] = .array(state["gears"].array.map { original in
                guard original.id == "tarmac" else { return original }
                var gear = original
                gear["name"] = "Tarmac SL8 Pro · Shimano Ultegra Di2"
                gear["importedTotals"] = ["distance": 56789012, "seconds": 4537110, "count": 2467, "through": .string(NativeDate.now)]
                gear["totalsMode"] = "imported"
                return gear
            })
            state["activities"] = .array(state["activities"].array.map { original in
                guard original["snapshot"].array.contains(where: { $0.id == "tarmac" }) else { return original }
                var activity = original
                activity["distance"] = 12345678
                activity["seconds"] = 3456789
                return activity
            })
            backup["state"] = state
            try store.importBackup(backup.jsonData())
            try store.commit("event-save", ["requestId": .string(UUID().uuidString), "event": [
                "gearId": "tarmac", "kind": "custom", "customName": "更换链条并检查前后变速器、飞轮与盘片的磨损情况",
                "occurredDate": .string(NativeDate.today),
                "notes": "清洁传动系统后重新煮蜡，检查前后变速器、飞轮、盘片与链条的磨损情况。随后检查轮组、外胎、碟片与来令片，并确认所有螺丝已经按规定扭矩锁紧。"
            ]])
            await seedAttachments(store)
        } catch { store.error = error.userFacingMessage }
    }
    static func run() async {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseTests-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:directory)}
        var report:[String:String]=[:]
        func check(_ condition:Bool,_ name:String)throws{report[name]=condition ? "passed":"failed";if !condition{throw DomainError("Self-test failed: "+name)}}
        do {
            NativeFixtureProtocol.configure(target: "bike1")
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[NativeFixtureProtocol.self]
            let store=NativeStore(directory:directory,secretStore:MemorySecretStore("fixture-test-key"),session:URLSession(configuration:config))
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            if let error=store.error { report["syncError"] = error }; try check(store.state["activities"].array.count==1 && store.state["gears"].array.count==3,"initialSync")
            let bike=store.state["gears"].array.first{$0["remoteId"].text=="bike1"}!,other=store.state["gears"].array.first{$0["remoteId"].text=="bike2"}!
            let total = store.currentStatistics[bike.id]["distance"].double
            try check(total == 12000, "initialCurrentTotals")
            var reminder = GearReminder(gearID: bike.id); reminder.title = "Fixture"; reminder.mode = .total; reminder.kilometers = 1
            try store.saveReminder(reminder)
            store.snapshotDate = "2025-01-01"
            try check(store.reminderOccurrence(reminder).distance == total && store.currentStatistics[bike.id]["distance"].double == total, "snapshotDoesNotReplaceReminderTotals")
            store.snapshotDate = nil
            try check(try store.query("view") == store.query("view"), "repeatedViewQueryStable")

            let shoe = try store.commit("gear", ["name":"Fixture Shoes", "type":"CyclingShoes"])
            NativeFixtureProtocol.configure(target:"bike2")
            try await store.assign(id:"fixture-ride", assignment:["shoe":shoe["id"]])
            try check(NativeFixtureProtocol.readPutCount() == 0 && store.state["activities"].array[0]["main"] == bike["id"], "shoeSaveDoesNotUploadMain")
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            try check(store.state["activities"].array[0]["main"] == other["id"] && store.state["activities"].array[0]["extras"] == .array([shoe["id"]]), "shoeSaveFollowsRemoteMain")
            let localCount = store.gears.count
            NativeFixtureProtocol.configure(target:"bike3", includeNewGear:true)
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            try check(store.state["remoteGears"].array.contains { $0.id == "bike3" } && store.gears.count == localCount, "catalogRefreshDoesNotCreateEquipment")
            try check(store.state["activities"].array[0]["unknown"].flag, "newRemoteMainNeedsLink")
            let linked = try store.commit("gear", ["name":"New Local Bike", "type":"Bike", "remoteId":"bike3"])
            try check(store.state["activities"].array[0]["main"] == linked["id"] && store.state["activities"].array[0]["extras"] == .array([shoe["id"]]), "linkResolvesUnknownActivity")
            let catalog = store.state["remoteGears"]
            NativeFixtureProtocol.configure(failCatalog:true)
            do { try await store.refreshRemoteGears() } catch { }
            try check(store.state["remoteGears"] == catalog && !store.refreshingGears, "catalogFailureKeepsLastGoodData")
            NativeFixtureProtocol.configure(target:"bike1", includeNewGear:true)
            await store.sync(from:"2026-10-01",to:"2026-10-02")

            try await store.assign(id:"fixture-ride",assignment:["main":other["id"],"extras":[],"excluded":[]])
            let written=store.state["activities"].array[0]
            try check(written["remoteId"].text=="bike2" && !written["pending"].flag,"gearWriteReadback")
            NativeFixtureProtocol.configure(failWrite:true)
            do {try await store.assign(id:"fixture-ride",assignment:["main":bike["id"],"extras":[],"excluded":[]]);throw DomainError("Expected failed write")}catch{}
            try check(store.state["activities"].array[0]["pending"].flag && !store.state["activities"].array[0]["error"].isNull,"writeFailurePreservesIntent")
            let reopened = NativeStore(directory:directory, secretStore:MemorySecretStore(), session:URLSession(configuration:config))
            try check(reopened.state["activities"] == store.state["activities"], "failedUploadPersistsAcrossRestart")
            NativeFixtureProtocol.configure()
            try await store.sendGear("fixture-ride")
            try check(!store.state["activities"].array[0]["pending"].flag,"retryWrite")

            NativeFixtureProtocol.configure(failWrite:true)
            do { try await store.assign(id:"fixture-ride",assignment:["main":other["id"]]) } catch { }
            NativeFixtureProtocol.configure(target:"bike3", includeNewGear:true)
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            do { try await store.sendGear("fixture-ride") } catch { }
            try check(NativeFixtureProtocol.readPutCount() == 0 && store.state["activities"].array[0]["mainConflict"].flag, "ordinarySyncCannotEraseWriteConflict")
            try await store.assign(id:"fixture-ride",assignment:["shoe":shoe["id"]])
            try check(NativeFixtureProtocol.readPutCount() == 0 && store.state["activities"].array[0]["pending"].flag, "shoeSaveDoesNotRetryPendingMain")
            NativeFixtureProtocol.configure(target:"bike1", includeNewGear:true)
            do { try await store.sendGear("fixture-ride", adoptingRemote:"bike3") } catch { }
            try check(NativeFixtureProtocol.readPutCount() == 0 && store.state["activities"].array[0]["mainConflict"].flag, "remoteChangesAgainRequiresNewChoice")
            try await store.sendGear("fixture-ride", adoptingRemote:"bike1")
            try check(NativeFixtureProtocol.readPutCount() == 1 && !store.state["activities"].array[0]["pending"].flag, "adoptLocalChecksRemoteBeforeUploading")
            NativeFixtureProtocol.configure(loseConfirmation:true)
            do { try await store.assign(id:"fixture-ride",assignment:["main":bike["id"]]) } catch { }
            try check(store.state["activities"].array[0]["pending"].flag, "lostConfirmationPreservesLocalSave")
            NativeFixtureProtocol.configure()
            try await store.sendGear("fixture-ride")
            try check(NativeFixtureProtocol.readPutCount() == 0 && !store.state["activities"].array[0]["pending"].flag, "lostConfirmationRetryAvoidsDuplicatePUT")
            try store.saveAssignment(id:"fixture-ride", assignment:["followRemote":true])
            NativeFixtureProtocol.configure(source:"STRAVA")
            do { try await store.assign(id:"fixture-ride", assignment:["main":other["id"]]) } catch { }
            try check(NativeFixtureProtocol.readPutCount() == 0 && store.state["activities"].array[0]["pending"].flag && store.state["activities"].array[0]["source"].text == "STRAVA", "stravaMainSaveRemainsLocal")
            try store.saveAssignment(id:"fixture-ride", assignment:["followRemote":true])
            NativeFixtureProtocol.configure(omitGear:true)
            do { try await store.assign(id:"fixture-ride", assignment:["main":other["id"]]) } catch { }
            try check(NativeFixtureProtocol.readPutCount() == 0 && store.state["activities"].array[0]["pending"].flag, "missingRemoteGearFieldCannotAuthorizePUT")
            try store.saveAssignment(id:"fixture-ride", assignment:["followRemote":true])
            NativeFixtureProtocol.configure()
            let image=UIGraphicsImageRenderer(size:CGSize(width:80,height:60)).image{ctx in UIColor.blue.setFill();ctx.fill(CGRect(x:0,y:0,width:80,height:60))}
            let photo=try store.addImage(image.pngData()!,owner:"gear",id:bike.id)
            try await verifyImageImport(in: directory.appendingPathComponent("AsyncImages"), bytes: image.pngData()!, check: check)
            try store.commit("photo-edit",["ownerType":"gear","ownerId":bike["id"],"action":"cover","id":.string(photo)])
            let copied = try store.commit("gear-copy", ["sourceId":bike["id"], "gear":["name":"Independent copy"], "copyReminders":true])
            try check(copied["remoteId"].isNull && store.currentStatistics[copied.id]["distance"].double == 0 && store.reminders.filter { $0.gearID == copied.id }.count == 1, "copyEquipmentAndReminderRules")
            let wheel = store.gears.first { $0["type"].text == "Wheelset" }!
            let installation = store.state["events"].array.first { $0["gearId"].text == wheel.id }!
            try store.commit("history-save", ["id":installation["id"], "gearId":wheel["id"], "parentId":bike["id"], "at":"2026-10-01"])
            let record = try store.commit("event-save", ["requestId":.string(UUID().uuidString), "event":["gearId":wheel["id"], "kind":"inspection", "occurredDate":"2026-10-02"]])
            try check(GearTimeline.buildRows(state: store.view, gearID: bike.id).contains { $0.id == record.id && $0["subjectGearId"].text == wheel.id }, "bikeTimelineIncludesComponentRecord")
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x:0,y:0,width:200,height:100)).pdfData { context in context.beginPage(); ("Receipt" as NSString).draw(at:CGPoint(x:20,y:20),withAttributes:nil) }
            let sourcePDF = directory.appendingPathComponent("Receipt.pdf")
            try pdf.write(to:sourcePDF)
            try await store.addAttachment(from:sourcePDF,gearID:bike.id)
            let sourceImage = directory.appendingPathComponent("Warranty.png")
            try image.pngData()!.write(to:sourceImage)
            try await store.addAttachment(from:sourceImage,gearID:bike.id)
            let attachments = store.state["attachments"].array
            try check(attachments.count == 2 && attachments.contains { $0["contentType"].text == "application/pdf" } && attachments.contains { $0["contentType"].text == "image/jpeg" }, "pdfAndImageAttachments")
            let backup=try store.exportBackup()
            let restored=NativeStore(directory:directory.appendingPathComponent("Restored"),secretStore:MemorySecretStore(),session:URLSession(configuration:config))
            try restored.importBackup(backup)
            try check(restored.state["photos"].array.count==1 && FileManager.default.fileExists(atPath:restored.photoURL(photo).path),"photoBackupRoundTrip")
            try check(restored.state["attachments"] == store.state["attachments"] && (try Data(contentsOf:restored.attachmentURL(attachments[0]))) == pdf, "attachmentJSONBackupRoundTrip")
            let worker = NativeBackupWorker()
            let package = try await worker.safety(state:store.state,directory:directory)
            let manifest = try GearBackupArchive.validate(at:package).manifest
            try check(manifest.attachments?.count == 2, "attachmentVersionBackup")
            try store.commit("attachment-delete",["id":attachments[0]["id"],"confirmed":true])
            try check(!FileManager.default.fileExists(atPath:try store.attachmentURL(attachments[0]).path), "attachmentDeleteRemovesFile")
            let prepared = try await worker.prepare(.init(manifest:manifest,url:package,uploaded:true,local:true),bookmark:nil,namespace:"Gearhouse QA Backups",work:directory.appendingPathComponent("BackupWork"))
            _ = try store.beginBackupRestore()
            _ = try await worker.installMedia(from:prepared.url,state:prepared.state,into:directory)
            try store.applyRestoredBackup(prepared.state); store.endBackupRestore()
            try check(store.state["attachments"].array.count == 2 && (try Data(contentsOf:store.attachmentURL(attachments[0]))) == pdf, "attachmentVersionRestoreAfterDelete")
            try await verifyAttachmentImport(in: directory.appendingPathComponent("AsyncAttachments"), check: check)
            try store.commit("photo-edit",["ownerType":"gear","ownerId":bike["id"],"action":"delete","id":.string(photo),"confirmed":true])
            try check(!FileManager.default.fileExists(atPath:store.photoURL(photo).path),"photoDeleteRemovesFile")
            NativeFixtureProtocol.configure(deleted:true)
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            try check(store.state["activities"].array[0]["deleted"].flag,"remote404RemovesActivity")
            try check(store.activities.isEmpty, "activityListInvalidatesAfterDeletion")
            try check(store.reminderOccurrence(reminder).distance == 0, "reminderCacheInvalidatesAfterDeletion")
            let summary=try store.query("view")
            try check(summary["statistics"][bike.id]["distance"].double==0,"deletedActivityRemovedFromUsage")
            try await verifyFailedStartup(in: directory.appendingPathComponent("FailedStartup"), check: check)
        } catch let failure {report["error"]=failure.localizedDescription}
        let reportURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("native-self-test.json")
        try? JSONEncoder().encode(report).write(to:reportURL,options:.atomic)
    }
}
#endif
