import SwiftUI
import CryptoKit
import BackgroundTasks
#if canImport(GearhouseCore)
import GearhouseCore
#endif

@MainActor
final class NativeStore: ObservableObject {
    @Published private(set) var state: Value = [:] {
        didSet { currentViewCache = nil; decodedReminders = nil; occurrenceCache = [:]; reminderActivityIndex = nil }
    }
    @Published private(set) var view: Value = [:]
    @Published var error: String?
    @Published var busy = false
    @Published var progress = ""
    @Published var connected = false
    @Published var snapshotDate: String? { didSet { refreshView() } }
    private var currentViewCache: (day: String, value: Value)?
    private var decodedReminders: [GearReminder]?
    private var occurrenceCache: [String: (reminder: GearReminder, second: Int, value: ReminderOccurrence)] = [:]
    private var reminderActivityIndex: GearReminderActivityIndex?
    private var allGearsByID: [String: Value] = [:]
    private var instanceNumbers: [String: Int] = [:]
    private var activitySource: Value = .null
    private(set) var treeIndex = GearTreeIndex()
    private(set) var viewGeneration = 0
    private(set) var currentStatistics: Value = [:]
    private(set) var activities: [Value] = []
    private var engine: NativeDomain?
    private let secrets: any SecretStore
    private let session: URLSession
    let cloudBackup: NativeCloudBackup
    private(set) var backupRestoring = false
    let directory: URL
    private let file: URL
    private var syncTask: Task<Void, Never>?
    private var writing = Set<String>()
    private let notificationsEnabled: Bool
    static let backgroundID = (Bundle.main.bundleIdentifier ?? "org.gearhouse.Gearhouse") + ".refresh"

    init(directory root: URL? = nil, secretStore: (any SecretStore)? = nil, session: URLSession = .shared) {
        #if DEBUG
        let preview = root == nil && ProcessInfo.processInfo.arguments.contains("-preview-route")
        #else
        let preview = false
        #endif
        notificationsEnabled = root == nil && !preview && !ProcessInfo.processInfo.arguments.contains("-reminder-self-test")
        self.session = session
        secrets = secretStore ?? (preview ? MemorySecretStore() : KeychainSecretStore())
        directory = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(preview ? "GearhousePreview" : "Gearhouse")
        file = directory.appendingPathComponent("state-v2.json")
        cloudBackup = NativeCloudBackup(directory: directory, isolated: preview || root != nil)
        do {
            engine = try NativeDomain()
            let old = directory.appendingPathComponent("state.json")
            let source = FileManager.default.fileExists(atPath: file.path) ? file : old
            var raw: Value = FileManager.default.fileExists(atPath: source.path) ? try Value.decode(Data(contentsOf: source)) : .null
            if preview && (!ProcessInfo.processInfo.arguments.contains("-preserve-preview") || raw.isNull), let fixture = Bundle.main.url(forResource: "preview-fixture", withExtension: "json") { raw = try Value.decode(Data(contentsOf: fixture)) }
            let initialized = try engine!.execute(state: raw, action: "initialize")["state"]
            try validateReminders(in: initialized)
            try GearAttachment.validateRecords(in: initialized)
            if !raw["gears"].array.isEmpty && (raw["events"] != initialized["events"] || raw["gearCategories"] != initialized["gearCategories"] || raw["gears"] != initialized["gears"]) {
                _ = try GearBackupArchive.create(state: raw, media: directory.appendingPathComponent("media"), in: directory.appendingPathComponent("Recovery"))
            }
            try persist(initialized)
            state = initialized
            refreshView()
            connected = secrets.read()?.isEmpty == false
            refreshNotifications()
        } catch let failure { error = failure.userFacingMessage }
        cloudBackup.attach(self)
    }
    var gears: [Value] { view["gears"].array }
    var revision: Value { state["revision"] }
    var readOnly: Bool { snapshotDate != nil }
    private var needsPrototypeMetadata: Bool { state["gears"].array.contains { !$0["remoteID"].isNull && $0["sourceComponent"].isNull } }
    func gear(_ id: String) -> Value { treeIndex.byID[id] ?? allGearsByID[id] ?? [:] }
    func conditionName(_ gear: Value) -> String {
        if gear["condition"].text == "used" || view["statistics"][gear.id]["count"].integer > 0 { return "已使用" }
        return gear["condition"].text == "unused" ? "未使用" : ""
    }
    func status(_ id: String, at: String? = nil) -> String {
        if let at { return GearInventory.readStatus(state: state, gearID: id, at: at) }
        return view["gearStatuses"][id].isNull ? (gear(id)["retired"].flag ? "retired" : "active") : view["gearStatuses"][id].text
    }
    func name(_ id: String) -> String { id.isEmpty ? "顶层装备" : gear(id)["name"].text }
    func displayName(_ id: String) -> String {
        guard let number = instanceNumbers[id] else { return name(id) }
        return name(id) + " · \(number)"
    }
    func parent(_ id: String, at: String? = nil) -> String {
        if let at { return GearTreeIndex(gears: gears, events: view["events"].array, at: at).parents[id] ?? "" }
        return treeIndex.parents[id] ?? ""
    }
    func refreshView() {
        do {
            let current = try query("view")
            let next = try snapshotDate.map { try query("view", ["date": .string($0)]) } ?? current
            currentStatistics = current["statistics"]
            treeIndex = GearTreeIndex(gears: next["gears"].array, events: next["events"].array, at: NativeDate.now)
            allGearsByID = Dictionary(state["gears"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            instanceNumbers = GearInventory.buildInstanceNumbers(state["gears"].array)
            if activitySource != next["activities"] {
                activitySource = next["activities"]
                activities = activitySource.array.filter { !$0["deleted"].flag }.sorted { $0["at"].text > $1["at"].text }
            }
            viewGeneration += 1
            view = next
        } catch let failure { error = failure.userFacingMessage }
    }
    func query(_ action: String, _ input: Value = [:]) throws -> Value {
        guard let engine else { throw DomainError("装备计算模块不可用") }
        if action == "view" && input["date"].isNull {
            let day = NativeDate.today
            if let cached = currentViewCache, cached.day == day { return cached.value }
            let result = try engine.execute(state: state, action: action, input: input)["result"]
            currentViewCache = (day, result)
            return result
        }
        return try engine.execute(state: state, action: action, input: input)["result"]
    }
    var reminders: [GearReminder] {
        if let cached = decodedReminders { return cached }
        let rows = (try? JSONDecoder().decode([GearReminder].self, from: state["reminders"].jsonData())) ?? []
        decodedReminders = rows
        return rows
    }
    func reminderOccurrence(_ reminder: GearReminder, now: Date = Date()) -> ReminderOccurrence {
        let second = Int(now.timeIntervalSince1970)
        if let cached = occurrenceCache[reminder.id], cached.second == second && cached.reminder == reminder { return cached.value }
        if reminder.enabled && reminder.mode == .usage && reminderActivityIndex == nil {
            reminderActivityIndex = GearReminderActivityIndex(state["activities"].array)
        }
        let result = GearReminderEngine.evaluate(reminder, state: state, total: currentStatistics[reminder.gearID]["distance"].double,
                                                now: now, activities: reminderActivityIndex)
        occurrenceCache[reminder.id] = (reminder, second, result)
        return result
    }
    @discardableResult
    func commit(_ action: String, _ input: Value = [:], internalSync: Bool = false) throws -> Value {
        guard !backupRestoring else { throw DomainError("正在恢复备份，请完成后重试。") }
        guard !readOnly || internalSync else { throw DomainError("请返回当前后再修改") }
        guard let engine else { throw DomainError("装备计算模块不可用") }
        let response = try engine.execute(state: state, action: action, input: input)
        var next = response["state"]
        if action == "gear-copy", input["copyReminders"].flag {
            let copies = reminders.filter { $0.gearID == input["sourceId"].text }.map { $0.copyRule(to: response["result"].id, state: state) }
            next["reminders"] = try Value.decode(JSONEncoder().encode(reminders + copies))
        }
        if action == "purge" { next["reminders"] = .array(next["reminders"].array.filter { $0["gearID"].text != input["id"].text }) }
        try GearAttachment.validateRecords(in: next)
        try persist(next)
        let obsolete = Set(state["photos"].array.map(\.id)).subtracting(next["photos"].array.map(\.id))
        let obsoleteAttachments = state["attachments"].array.filter { row in !next["attachments"].array.contains { $0.id == row.id } }
        state = next
        for id in obsolete { try? FileManager.default.removeItem(at: photoURL(id)) }
        for attachment in obsoleteAttachments { if let url = try? attachmentURL(attachment) { try? FileManager.default.removeItem(at: url) } }
        refreshView()
        refreshNotifications()
        cloudBackup.changed()
        return response["result"]
    }
    func perform(_ action: String, _ input: Value = [:]) { do { try commit(action, input) } catch let failure { error = failure.userFacingMessage } }
    private func persist(_ value: Value) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try value.jsonData().write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func request(_ path: String, method: String = "GET", body: Value? = nil, key override: String? = nil) async throws -> Value {
        guard let key = override ?? secrets.read(), !key.isEmpty else { throw DomainError("请连接 Intervals.icu") }
        guard let url = URL(string: "https://intervals.icu/api/v1" + path) else { throw DomainError("接口地址无效") }
        var request = URLRequest(url: url); request.timeoutInterval = 45; request.httpMethod = method
        request.setValue("Basic " + Data("API_KEY:\(key)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try body.jsonData(); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DomainError("网络响应无效") }
        guard (200..<300).contains(http.statusCode) else { throw ICUClientError.badResponse(http.statusCode) }
        return data.isEmpty ? .null : try Value.decode(data)
    }
    func connect(_ key: String) async throws {
        guard !busy && !backupRestoring else { throw DomainError("请等待同步完成") }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = try await request("/athlete/0", key: trimmed)
        let id = account["id"].text
        guard !id.isEmpty else { throw DomainError("ICU 未返回账户") }
        guard state["account"].isNull || state["account"]["id"].text == id else { throw DomainError("此数据库属于其他 ICU 账户") }
        guard !backupRestoring else { throw DomainError("正在恢复备份，请完成后重试。") }
        try secrets.write(trimmed)
        try commit("account", ["id": .string(id), "name": account["name"].isNull ? account["firstname"] : account["name"]], internalSync: true)
        connected = true
        try commit("sync-settings", ["pausedAuth": false, "nextAt": .null], internalSync: true)
        startSync()
    }
    func setAutoSync(_ enabled: Bool) {
        do { try commit("sync-settings", ["enabled": .bool(enabled), "pausedAuth": false, "nextAt": .null], internalSync: true); scheduleBackground(); if enabled { startSync() } }
        catch let failure { error = failure.userFacingMessage }
    }
    func automaticTick() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-verify-installation-migration") { return }
        #endif
        guard !backupRestoring else { return }
        await cloudBackup.tick()
        if currentViewCache?.day != NativeDate.today || treeIndex.nextEventAt.map({ $0 <= NativeDate.now }) == true { refreshView() }
        refreshNotifications()
        guard connected, !busy, state["autoSync"]["enabled"] != false, !state["autoSync"]["pausedAuth"].flag else { return }
        if let next = ISO8601DateFormatter().date(from: state["autoSync"]["nextAt"].text), next > Date(), !needsPrototypeMetadata { return }
        await sync()
        // Include newly synced activities in the same background execution opportunity.
        await cloudBackup.tick()
    }
    func startSync(from: String? = nil, to: String? = nil) {
        guard !busy else { return }
        syncTask = Task { await sync(from: from, to: to) }
    }
    func cancelSync() { syncTask?.cancel() }
    func sync(from: String? = nil, to: String? = nil) async {
        guard !busy, connected, !backupRestoring else { return }; busy = true
        defer { busy = false; progress = ""; scheduleBackground(); refreshNotifications() }
        do {
            if state["account"].isNull {
                let account = try await request("/athlete/0")
                try commit("account", ["id": .string(account["id"].text), "name": account["name"].isNull ? account["firstname"] : account["name"]], internalSync: true)
            }
            let plan = try query("sync-plan"), first = !state["gearImported"].flag
            if state["gearImportVersion"].integer < 3 || needsPrototypeMetadata {
                progress = "读取装备"
                let remote = try await request("/athlete/0/gear")
                try commit("gear-import", ["rows": remote], internalSync: true)
            }
            var cursor = from ?? plan["oldest"].text
            let end = to ?? plan["newest"].text
            guard cursor >= "2000-01-01", cursor <= end, end <= NativeDate.today else { throw DomainError("日期范围无效") }
            while cursor <= end {
                try Task.checkCancellation()
                let until = min(NativeDate.shift(cursor, 30), end)
                progress = cursor + " – " + until
                let writes: Value = .object(Dictionary(uniqueKeysWithValues: state["activities"].array.map { ($0.id, $0["lastWriteAt"]) }))
                let fields = "id,name,type,start_date_local,start_date,distance,moving_time,elapsed_time,gear,source,trainer"
                let rows = try await request("/athlete/0/activities?oldest=\(cursor)&newest=\(until)T23:59:59&fields=\(fields)")
                guard case .array = rows, rows.array.allSatisfy({ !$0.id.isEmpty }) else { throw DomainError("ICU 活动返回格式无效") }
                let present = Set(rows.array.map(\.id))
                let missing = state["activities"].array.filter { !$0["deleted"].flag && !$0["at"].text.isEmpty && $0["at"].text.prefix(10) >= cursor && $0["at"].text.prefix(10) <= until && !present.contains($0.id) }
                var deleted: [Value] = [], recovered: [Value] = []
                for activity in missing {
                    try Task.checkCancellation()
                    let before = try activity.jsonString()
                    do {
                        let row = try await request("/activity/\(activity.id)?intervals=false")
                        guard row.id == activity.id else { throw DomainError("ICU 活动详情返回格式无效") }
                        recovered.append(["row": row, "before": .string(before)])
                    } catch ICUClientError.badResponse(404) { deleted.append(["id": .string(activity.id), "before": .string(before)]) }
                }
                let next = NativeDate.shift(until, 1)
                try commit("sync-rows", ["rows": rows, "recovered": .array(recovered), "deleted": .array(deleted), "writes": writes, "historical": .bool(first || from != nil), "saveResume": .bool(from == nil), "from": .string(cursor), "to": .string(until), "next": .string(next)], internalSync: true)
                cursor = next
            }
            let stamp = ISO8601DateFormatter().string(from: Date())
            var status: Value = ["error": .null, "failures": 0, "pausedAuth": false, "nextAt": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(300)))]
            if from == nil { status["lastSuccess"] = .string(stamp); status["resume"] = .null }
            if plan["daily"].flag && from == nil { status["dailyThrough"] = .string(NativeDate.today) }
            try commit("sync-settings", status, internalSync: true)
        } catch let failure {
            let auth: Bool
            if case ICUClientError.badResponse(let code) = failure { auth = code == 401 || code == 403 } else { auth = false }
            let failures = state["autoSync"]["failures"].integer + 1
            var delay = min(3600.0, 300 * pow(2, Double(min(failures - 1, 4))))
            if case ICUClientError.badResponse(429) = failure { delay = max(delay, 900) }
            _ = try? commit("sync-settings", ["error": .string(failure.userFacingMessage), "failures": .number(Double(failures)), "pausedAuth": .bool(auth), "nextAt": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(delay)))], internalSync: true)
            if !(failure is CancellationError) { error = failure.userFacingMessage }
        }
    }
    func assign(id: String, assignment: Value) async throws {
        guard !writing.contains(id) else { throw DomainError("正在同步该活动") }
        try commit("assignment", ["id": .string(id), "assignment": assignment])
        try await sendGear(id)
    }
    func sendGear(_ id: String) async throws {
        guard !backupRestoring else { throw DomainError("正在恢复备份，请完成后重试。") }
        guard !writing.contains(id), let activity = state["activities"].array.first(where: { $0.id == id }), activity["pending"].flag else { return }
        writing.insert(id); defer { writing.remove(id) }
        do {
            let main = activity["main"].text, target = gear(main)["remoteId"]
            guard main.isEmpty || !target.isNull else { throw DomainError("请先在装备编辑中关联 ICU 装备") }
            let path = "/activity/" + id
            let existing = try await request(path + "?intervals=false")
            guard existing.id == id, !existing["start_date_local"].text.isEmpty else { throw DomainError("该活动不可通过 API 修改") }
            guard existing["source"].text != "STRAVA" else { throw DomainError("Strava 来源活动不能通过 ICU API 修改") }
            guard existing["icu_athlete_id"].isNull || existing["icu_athlete_id"].text == state["account"]["id"].text else { throw DomainError("活动账户不匹配") }
            let current = existing["gear"]["id"]
            guard current.text == activity["remoteId"].text || current.text == target.text else { throw DomainError("ICU 主装备已在别处修改，请先同步活动") }
            if current.text != target.text { _ = try await request(path, method: "PUT", body: ["gear": target.isNull ? .null : ["id": target]]) }
            let verified = try await request(path + "?intervals=false")
            guard verified.id == id, verified["gear"]["id"].text == target.text else { throw DomainError("ICU 未确认装备修改，请重试") }
            try commit("write-result", ["id": .string(id), "main": activity["main"], "target": target], internalSync: true)
        } catch let failure {
            _ = try? commit("write-result", ["id": .string(id), "error": .string(failure.userFacingMessage)], internalSync: true)
            throw failure
        }
    }
    func photoURL(_ id: String) -> URL { directory.appendingPathComponent("media").appendingPathComponent(id + ".jpg") }
    func attachmentURL(_ record: Value) throws -> URL { directory.appendingPathComponent("media").appendingPathComponent(try GearAttachment.fileName(record)) }
    func addAttachment(from url: URL, gearID: String) async throws {
        let prepared = try await NativeAttachmentFiles.prepare(url)
        guard !backupRestoring, !readOnly else { throw DomainError("请完成恢复或返回当前后再添加附件。") }
        let id = UUID().uuidString.lowercased()
        let record: Value = ["id": .string(id), "gearId": .string(gearID), "name": .string(prepared.name), "contentType": .string(prepared.contentType), "bytes": .number(Double(prepared.data.count)), "hash": .string(SHA256.hash(data: prepared.data).map { String(format: "%02x", $0) }.joined())]
        let destination = try attachmentURL(record)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try prepared.data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }.value
        do { try commit("attachment-add", record) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func addImage(_ bytes: Data, owner: String, id: String, gearID: String = "") throws -> String {
        guard !backupRestoring else { throw DomainError("正在恢复备份，请完成后重试。") }
        guard let source = UIImage(data: bytes), source.size.width > 0, source.size.height > 0 else { throw DomainError("图片无效") }
        let scale = min(1, 2560 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size)); source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.85), data.count <= 10 * 1024 * 1024 else { throw DomainError("图片过大") }
        let photoID = UUID().uuidString.lowercased(), url = photoURL(photoID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do {
            try commit("photo-add", ["id": .string(photoID), "ownerType": .string(owner), "ownerId": .string(id), "gearId": .string(gearID), "metadata": ["width": .number(size.width), "height": .number(size.height), "bytes": .number(Double(data.count)), "hash": .string(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())]])
        } catch { try? FileManager.default.removeItem(at: url); throw error }
        return photoID
    }
    func exportBackup() throws -> Data {
        var media: [String: Value] = [:]
        for p in state["photos"].array { media[p.id] = .string(try Data(contentsOf: photoURL(p.id)).base64EncodedString()) }
        var attachments: [String: Value] = [:]
        for record in state["attachments"].array { attachments[record.id] = .string(try Data(contentsOf: attachmentURL(record)).base64EncodedString()) }
        return try Value.object(["state": state, "media": .object(media), "attachments": .object(attachments)]).jsonData()
    }
    func importBackup(_ data: Data) throws {
        guard !busy && writing.isEmpty && !backupRestoring else { throw DomainError("请等待同步完成") }
        let backup = try Value.decode(data), raw = backup["state"].isNull ? backup : backup["state"]
        guard let engine else { throw DomainError("计算模块不可用") }
        let next = try engine.execute(state: raw, action: "initialize")["state"]
        try validateReminders(in: next)
        try GearAttachment.validateRecords(in: next)
        guard state["account"].isNull || next["account"]["id"].text == state["account"]["id"].text else { throw DomainError("备份属于其他 ICU 账户") }
        var images: [(URL, Data)] = []
        for photo in next["photos"].array {
            guard UUID(uuidString: photo.id) != nil else { throw DomainError("备份图片标识无效") }
            guard let bytes = Data(base64Encoded: backup["media"][photo.id].text), bytes.count <= 10 * 1024 * 1024, UIImage(data: bytes) != nil else { throw DomainError("备份缺少图片，请使用包含图片的完整备份") }
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard photo["hash"].text == hash else { throw DomainError("备份图片校验失败") }
            let destination = photoURL(photo.id)
            if FileManager.default.fileExists(atPath: destination.path) {
                let existing = try Data(contentsOf: destination)
                guard SHA256.hash(data: existing).map({ String(format: "%02x", $0) }).joined() == hash else { throw DomainError("备份图片与本机同名图片冲突") }
            }
            images.append((destination, bytes))
        }
        for record in next["attachments"].array {
            guard let bytes = Data(base64Encoded: backup["attachments"][record.id].text), bytes.count == record["bytes"].integer,
                  bytes.count <= GearAttachment.maximumBytes,
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == record["hash"].text else { throw DomainError("备份缺少附件或附件已损坏，请重新选择完整备份。") }
            let destination = try attachmentURL(record)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try GearBackupArchive.hash(destination) == record["hash"].text else { throw DomainError("备份附件与本机文件冲突，请重新选择备份。") }
            }
            images.append((destination, bytes))
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("media"), withIntermediateDirectories: true)
        _ = try GearBackupArchive.create(state: state, media: directory.appendingPathComponent("media"), in: directory.appendingPathComponent("Recovery"))
        for (url, bytes) in images { try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        try persist(next); state = next; snapshotDate = nil; refreshView(); refreshNotifications(); cloudBackup.changed()
    }
    private func validateReminders(in state: Value) throws {
        guard !state["reminders"].isNull else { return }
        let rows = try JSONDecoder().decode([GearReminder].self, from: state["reminders"].jsonData())
        guard Set(rows.map(\.id)).count == rows.count else { throw DomainError("备份包含重复提醒") }
        for row in rows { try row.validate() }
    }
    func replaceReminders(_ reminders: [GearReminder]) throws {
        guard !backupRestoring else { throw DomainError("正在恢复备份，请完成后重试。") }
        guard !readOnly else { throw DomainError("请返回当前后再修改") }
        var next = state
        next["reminders"] = try Value.decode(JSONEncoder().encode(reminders))
        next["revision"] = .number(state["revision"].double + 1)
        try persist(next); state = next; refreshView(); refreshNotifications(); cloudBackup.changed()
    }
    func beginBackupRestore() throws -> Value {
        guard !busy && writing.isEmpty && !backupRestoring else { throw NativeBackupError.busy }
        guard !readOnly else { throw DomainError("请返回当前后再修改") }
        backupRestoring = true
        return state
    }
    func applyRestoredBackup(_ value: Value) throws {
        guard backupRestoring else { throw NativeBackupError.busy }
        try validateReminders(in: value)
        guard let engine else { throw DomainError("计算模块不可用") }
        var next = try engine.execute(state: value, action: "initialize")["state"]
        try GearAttachment.validateRecords(in: next)
        // Restoring an old snapshot must invalidate previews opened before recovery.
        next["revision"] = .number(max(state["revision"].double, value["revision"].double) + 1)
        try persist(next)
        state = next; snapshotDate = nil; refreshView(); refreshNotifications()
    }
    func endBackupRestore() { backupRestoring = false; cloudBackup.changed() }
    func flushNotifications() async {
        guard notificationsEnabled, !busy else { return }
        await NativeNotifications.shared.flush(notificationPlans())
    }
    func refreshNotifications() {
        guard notificationsEnabled, !busy else { return }
        NativeNotifications.shared.reconcile { [weak self] in self?.notificationPlans() ?? [] }
    }
    #if DEBUG
    func recordDragPerformance(updates: Int, treeBuilds: Int) {
        guard ProcessInfo.processInfo.arguments.contains("-preview-route") else { return }
        let url = directory.appendingPathComponent("drag-performance.json")
        var records = (try? Value.decode(Data(contentsOf: url)).array) ?? []
        records.append(["updates": .number(Double(updates)), "treeBuildsDuringGesture": .number(Double(treeBuilds))])
        try? Value.array(records).jsonData().write(to: url, options: .atomic)
    }
    #endif
    func scheduleBackground() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
        guard cloudBackup.enabled || (connected && state["autoSync"]["enabled"] != false) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum NativeDate {
    static var zone: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    private static let formatters = NSCache<NSString, DateFormatter>()
    private static func formatter(_ pattern: String) -> DateFormatter {
        if let existing = formatters.object(forKey: pattern as NSString) { return existing }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.dateFormat = pattern
        formatters.setObject(formatter, forKey: pattern as NSString)
        return formatter
    }
    static func format(_ date: Date, _ pattern: String) -> String { formatter(pattern).string(from: date) }
    static var now: String { format(Date(), "yyyy-MM-dd'T'HH:mm:ss") }
    static var today: String { String(now.prefix(10)) }
    static func parse(_ value: String) -> Date {
        formatter(value.count > 10 ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd").date(from: value.count == 16 ? value + ":00" : value) ?? Date()
    }
    static func shift(_ value: String, _ days: Int) -> String { format(parse(value).addingTimeInterval(Double(days) * 86400), "yyyy-MM-dd") }
}
