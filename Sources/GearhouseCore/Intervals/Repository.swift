import Foundation

public protocol SecretStore: Sendable { func read() -> String?; func write(_ value: String) throws; func remove() throws }
public struct MemorySecretStore: SecretStore { private let box: LockedString; public init(_ value: String? = nil) { box=LockedString(value) }; public func read()->String? { box.value }; public func write(_ value:String)throws { box.value=value }; public func remove()throws { box.value=nil } }
private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ value: String?) { stored = value }
    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

public actor LocalRepository {
    public private(set) var state: GearhouseState
    private let url: URL
    private let secretStore: SecretStore
    public init(url: URL, secretStore: SecretStore) { self.url=url; self.secretStore=secretStore; self.state=(try? Self.load(url)) ?? GearhouseState() }
    private static func load(_ url: URL) throws -> GearhouseState { try JSONDecoder.gearhouse.decode(GearhouseState.self, from: Data(contentsOf: url)) }
    private func persist(_ next: GearhouseState) throws { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder.gearhouse.encode(next).write(to: url, options: .atomic) }
    public func apiKey() -> String? { secretStore.read() }
    public func saveAPIKey(_ key: String) throws { try secretStore.write(key) }
    public func clearAPIKey() throws { try secretStore.remove() }
    public func replace(_ next: GearhouseState) throws { try persist(next); state=next }
    public func sync(client: ICUClient, oldest: String, newest: String) async throws {
        async let athlete = client.athlete(); async let remoteGears = client.gears(); async let remoteActivities = client.activities(oldest: oldest, newest: newest)
        let account=try await athlete, rGears=try await remoteGears, rActivities=try await remoteActivities
        var next=state; next.accountName=account.name ?? account.firstname ?? account.id.value
        next.gears = mergeGears(local: next.gears, remote: rGears)
        next.activities = mergeActivities(local: next.activities, remote: rActivities, gears: next.gears)
        next.lastSync = Date(); try replace(next)
    }
    private func mergeGears(local: [Gear], remote: [ICUGear]) -> [Gear] {
        var result=local; for r in remote { let id=r.id.value; let type=GearType(rawValue:r.type ?? "") ?? .other; if let i=result.firstIndex(where:{$0.remoteID==id}) { result[i].name=r.name ?? id; if result[i].type == .other { result[i].type=type } } else { result.append(Gear(id: "icu-\(id)", name:r.name ?? id, type:type, remoteID:id)) } }; return result
    }
    private func mergeActivities(local: [Activity], remote: [ICUActivity], gears: [Gear]) -> [Activity] {
        var result = local
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        let local = DateFormatter(); local.calendar = Calendar(identifier: .gregorian); local.locale = Locale(identifier: "en_US_POSIX"); local.timeZone = TimeZone(identifier: "Asia/Shanghai"); local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        for r in remote {
            let rawDate = r.startDateLocal ?? ""
            guard let date = iso.date(from: rawDate) ?? plain.date(from: rawDate) ?? local.date(from: rawDate) else { continue }
            let id = r.id.value
            let remoteGear = r.gear?.id.value
            let main = remoteGear.flatMap { remoteID in
                gears.first(where: { gear in
                    gear.remoteID == remoteID && (gear.type == .bike || gear.type == .shoes)
                })?.id
            }
            let virtualRide = (r.type ?? "").replacingOccurrences(of: " ", with: "").lowercased() == "virtualride"
            let value = Activity(id: id, name: r.name ?? "未命名活动", type: r.type ?? "", at: date, distance: r.distance, seconds: r.movingTime, remoteGearID: remoteGear, mainGearID: main, deleted: false, trainer: r.trainer, equipmentDistanceIncluded: !virtualRide && r.trainer != true)
            if let i = result.firstIndex(where: { $0.id == id }) {
                var saved = result[i]
                saved.name = value.name; saved.type = value.type; saved.at = value.at; saved.distance = value.distance; saved.seconds = value.seconds; saved.remoteGearID = value.remoteGearID
                saved.mainGearID = main
                saved.trainer = r.trainer
                saved.deleted = false; result[i] = saved
            } else { result.append(value) }
        }
        return result.sorted { $0.at > $1.at }
    }
}

extension JSONDecoder { static let gearhouse: JSONDecoder = { let d=JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }() }
extension JSONEncoder { static let gearhouse: JSONEncoder = { let e=JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }() }
