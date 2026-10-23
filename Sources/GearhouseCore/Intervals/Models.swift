import Foundation

public enum GearType: String, Codable, CaseIterable, Sendable {
    case bike = "Bike", shoes = "Shoes", cyclingShoes = "CyclingShoes", cleats = "Cleats", pedals = "Pedals", wheelset = "Wheelset", chain = "Chain", trainer = "Trainer", other = "Equipment"
    public var title: String {
        switch self { case .bike: "自行车"; case .shoes: "跑鞋"; case .cyclingShoes: "锁鞋"; case .cleats: "锁片"; case .pedals: "锁踏"; case .wheelset: "轮组"; case .chain: "链条"; case .trainer: "骑行台"; case .other: "其他" }
    }
}

public struct Gear: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: GearType
    public var remoteID: String?
    public var purchased: String?
    public var retired: Bool
    public var parentID: String?
    public var coverPhotoID: String?
    public init(id: String, name: String, type: GearType, remoteID: String? = nil, purchased: String? = nil, retired: Bool = false, parentID: String? = nil, coverPhotoID: String? = nil) { self.id=id; self.name=name; self.type=type; self.remoteID=remoteID; self.purchased=purchased; self.retired=retired; self.parentID=parentID; self.coverPhotoID=coverPhotoID }
}

public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: String
    public var at: Date
    public var distance: Double?
    public var seconds: Int?
    public var remoteGearID: String?
    public var mainGearID: String?
    public var deleted: Bool
    public var trainer: Bool?
    // nil is the legacy policy: do not silently recalculate existing records.
    public var equipmentDistanceIncluded: Bool?
    public var equipmentDistance: Double? {
        equipmentDistanceIncluded == false ? 0 : distance
    }
    public init(id: String, name: String, type: String, at: Date, distance: Double? = nil, seconds: Int? = nil, remoteGearID: String? = nil, mainGearID: String? = nil, deleted: Bool = false, trainer: Bool? = nil, equipmentDistanceIncluded: Bool? = nil) { self.id=id; self.name=name; self.type=type; self.at=at; self.distance=distance; self.seconds=seconds; self.remoteGearID=remoteGearID; self.mainGearID=mainGearID; self.deleted=deleted; self.trainer=trainer; self.equipmentDistanceIncluded=equipmentDistanceIncluded }
}

public struct GearhouseState: Codable, Sendable {
    public var accountName: String?
    public var gears: [Gear]
    public var activities: [Activity]
    public var lastSync: Date?
    public init(accountName: String? = nil, gears: [Gear] = [], activities: [Activity] = [], lastSync: Date? = nil) { self.accountName=accountName; self.gears=gears; self.activities=activities; self.lastSync=lastSync }
}

public struct StringValue: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let value: String
    public init(stringLiteral value: String) { self.value = value }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string; return }
        if let integer = try? container.decode(Int.self) { value = String(integer); return }
        throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected string or integer"))
    }
    public init(_ value: String) { self.value = value }
}

public struct ICUAthlete: Decodable, Sendable {
    public let id: StringValue
    public let name: String?
    public let firstname: String?
}

public struct ICUGearReference: Codable, Sendable {
    public let id: StringValue
    public init(from decoder: Decoder) throws {
        if let scalar = try? StringValue(from: decoder) { id = scalar; return }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(StringValue.self, forKey: .id)
    }
    private enum CodingKeys: String, CodingKey { case id }
}

public struct ICUActivity: Codable, Sendable {
    public let id: StringValue
    public let name: String?
    public let type: String?
    public let startDateLocal: String?
    public let distance: Double?
    public let movingTime: Int?
    public let gear: ICUGearReference?
    public let trainer: Bool?
    enum CodingKeys: String, CodingKey { case id, name, type, startDateLocal = "start_date_local", distance, movingTime = "moving_time", gear, trainer }
}

public struct ICUGear: Codable, Identifiable, Sendable {
    public let id: StringValue
    public let name: String?
    public let type: String?
    public let component: Bool?
    public let componentIDs: [StringValue]?
    enum CodingKeys: String, CodingKey { case id, name, type, component, componentIDs = "component_ids" }
}
