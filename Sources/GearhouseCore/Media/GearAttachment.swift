import Foundation

public enum GearAttachment {
    public static let maximumBytes = 20 * 1024 * 1024

    public static func fileName(_ record: Value) throws -> String {
        guard UUID(uuidString: record.id) != nil,
              ["application/pdf", "image/jpeg"].contains(record["contentType"].text) else {
            throw DomainError("无法读取附件，请重新选择完整备份。")
        }
        return record.id + (record["contentType"].text == "application/pdf" ? ".pdf" : ".jpg")
    }

    public static func validateRecords(in state: Value) throws {
        switch state["attachments"] {
        case .null, .array: break
        default: throw DomainError("无法读取附件，请重新选择完整备份。")
        }
        var seen = Set<String>()
        let gears = Set(state["gears"].array.map(\.id))
        for row in state["attachments"].array {
            _ = try fileName(row)
            guard seen.insert(row.id).inserted, gears.contains(row["gearId"].text),
                  !row["name"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row["bytes"].double > 0, row["bytes"].double <= Double(maximumBytes), row["bytes"].double.rounded() == row["bytes"].double,
                  row["hash"].text.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw DomainError("附件信息不完整，请重新选择完整备份。")
            }
        }
    }
}
