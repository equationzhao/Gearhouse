#if DEBUG
import UIKit
#if canImport(GearhouseCore)
import GearhouseCore
#endif

@MainActor
enum NativeBackupSelfTest {
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
            let before = store.state
            let worker = NativeBackupWorker()
            let package = try await worker.safety(state: before, directory: root)
            let manifest = try GearBackupArchive.manifest(at: package)
            try check(!(try String(contentsOf: package.appendingPathComponent("state.json"))).contains("fixture-backup-key"), "credentialsExcluded")
            _ = try store.commit("gear", ["id":bike["id"], "name":"Changed Bike", "type":"Bike"])
            _ = try store.commit("photo-edit", ["ownerType":"gear", "ownerId":bike["id"], "action":"delete", "id":.string(photo), "confirmed":true])
            let changed = store.state
            let restored = await store.cloudBackup.restore(.init(manifest: manifest, url: package, uploaded: true, local: true))
            try check(restored && store.gear(bike.id)["name"].text == "Backup Bike", "versionRestore")
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
        } catch {
            report["error"] = error.localizedDescription
        }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backup-self-test.json")
        try? JSONEncoder().encode(report).write(to: url, options: .atomic)
    }
}
#endif
