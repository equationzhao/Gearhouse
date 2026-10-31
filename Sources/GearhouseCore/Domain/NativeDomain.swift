import Foundation
import JavaScriptCore
import CryptoKit
import OSLog

public enum Value: Codable, Equatable, Sendable, Identifiable, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    case null, string(String), number(Double), bool(Bool), array([Value]), object([String: Value])
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: Value...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, Value)...) { self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b })) }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let a = try? c.decode([Value].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Value].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
    public subscript(key: String) -> Value {
        get { if case .object(let o) = self { return o[key] ?? .null }; return .null }
        set { var o = object; o[key] = newValue; self = .object(o) }
    }
    public var object: [String: Value] { if case .object(let o) = self { return o }; return [:] }
    public var array: [Value] { if case .array(let a) = self { return a }; return [] }
    public var text: String {
        switch self { case .string(let s): return s; case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n); default: return "" }
    }
    public var flag: Bool { if case .bool(let b) = self { return b }; return false }
    public var double: Double { if case .number(let n) = self { return n }; return 0 }
    public var integer: Int { Int(double) }
    public var isNull: Bool { self == .null }
    public var id: String { self["id"].text }
    public func jsonData() throws -> Data { try JSONEncoder().encode(self) }
    public func jsonString() throws -> String { String(decoding: try jsonData(), as: UTF8.self) }
    public static func decode(_ data: Data) throws -> Value { try JSONDecoder().decode(Value.self, from: data) }
    public static func optional(_ value: String) -> Value { value.isEmpty ? .null : .string(value) }
}

public struct DomainError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Confine each engine to its owning actor/thread; no web view or network code is involved.
public final class NativeDomain {
    private let context: JSContext
    public init() throws {
        guard let context = JSContext() else { throw DomainError("无法启动装备计算模块") }
        self.context = context
        let uuid: @convention(block) () -> String = { UUID().uuidString.lowercased() }
        let hash: @convention(block) (String) -> String = { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
        context.setObject(uuid, forKeyedSubscript: "nativeUUID" as NSString)
        context.setObject(hash, forKeyedSubscript: "nativeHash" as NSString)
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "gearhouse-rules", withExtension: "js") else { throw DomainError("装备计算模块缺失") }
        context.evaluateScript(try String(contentsOf: url))
        if let error = context.exception { throw DomainError(error.toString() ?? "计算模块加载失败") }
    }
    public func execute(state: Value, action: String, input: Value = [:]) throws -> Value {
        context.exception = nil
        let readOnly = ["view", "usage", "recompute-preview", "organize-preview", "purge-preview", "assignment-preview", "sync-plan", "inventory-options", "inventory-preview", "inventory-delete-preview", "inventory-batch-preview"].contains(action)
        var payload = state
        if readOnly, case .object(var fields) = payload {
            for field in ["recalculations", "historyEdits", "organizations", "gearEventRequests"] { fields.removeValue(forKey: field) }
            payload = .object(fields)
        }
        let request: Value = ["state": payload, "action": .string(action), "input": input]
        guard let output = context.objectForKeyedSubscript("gearhouseCall")?.call(withArguments: [try request.jsonString()])?.toString(), context.exception == nil else {
            throw DomainError(context.exception?.toString() ?? "装备计算失败")
        }
        var result = try Value.decode(Data(output.utf8))
        if readOnly { result["state"] = state }
        if !result["error"].isNull { throw DomainError(result["error"].text) }
        return result
    }
}

/// Only reviewed, actionable copy crosses the UI boundary. Raw errors stay in diagnostics.
public enum UserFacingError {
    public static func message(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return "网络已断开，请连接网络后重试。"
            case .timedOut: return "连接超时，请重试。"
            case .cancelled: return "操作已取消。"
            default: return "无法连接 Intervals.icu，请稍后重试。"
            }
        }
        if let error = error as? ICUClientError {
            switch error {
            case .invalidKey: return "连接失败，请检查 API Key。"
            case .badResponse(let code): return httpMessage(code)
            case .invalidPayload: return "无法读取 Intervals.icu 的数据，请稍后重试。"
            case .transport(let raw): return text(raw)
            }
        }
        if error is DecodingError { return "无法读取数据，内容可能不完整。" }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteOutOfSpaceError: return "存储空间不足，请清理空间后重试。"
            case NSFileReadNoSuchFileError: return "找不到文件，请重新选择。"
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return "无法访问文件，请重新选择保存位置或文件。"
            case NSUserCancelledError: return "操作已取消。"
            default: return "无法读取或保存文件，请重试。"
            }
        }
        return text((error as? DomainError)?.message ?? error.localizedDescription)
    }

    /// Also handles error strings saved by earlier versions without exposing raw exceptions.
    public static func text(_ raw: String) -> String {
        if let copy = replacements[raw] { return copy }
        if safeMessages.contains(raw) || replacements.values.contains(raw) { return raw }
        if raw.hasPrefix("Intervals.icu 请求失败（HTTP "), let code = Int(raw.filter(\.isNumber)) { return httpMessage(code) }
        if raw.hasPrefix("无法保存到钥匙串（") { return "无法保存连接信息，请重试。" }
        return "操作未完成，请重试。"
    }
    private static func httpMessage(_ code: Int) -> String {
        switch code {
        case 401, 403: return "连接已失效，请检查并更新 API Key。"
        case 404: return "找不到这条记录，可能已被删除。"
        case 429: return "请求过于频繁，请稍后重试。"
        default: return "Intervals.icu 暂时无法完成请求，请稍后重试。"
        }
    }
    private static let replacements: [String: String] = [
        "请先在装备编辑中关联 ICU 装备": "请先关联主装备，再上传到 ICU。",
        "该活动不可通过 API 修改": "这条活动无法上传装备修改，请在 Intervals.icu 中修改。",
        "Strava 来源活动不能通过 ICU API 修改": "Strava 来源的活动无法上传装备修改。",
        "活动账户不匹配": "活动与当前账户不一致，请检查 Intervals.icu 连接。",
        "ICU 未确认装备修改，请重试": "本机已保存，尚未确认 ICU 的修改结果，请重试。",
        "正在同步该活动": "正在上传这条活动，请完成后重试。",
        "装备计算模块不可用": "无法载入装备数据，请重新打开 App。",
        "无法启动装备计算模块": "无法载入装备数据，请重新打开 App。",
        "装备计算模块缺失": "此版本无法载入装备数据，请更新 App。",
        "计算模块不可用": "无法载入装备数据，请重新打开 App。",
        "计算模块加载失败": "无法载入装备数据，请重新打开 App。",
        "装备计算失败": "无法计算装备使用量，请重试。",
        "接口地址无效": "无法连接 Intervals.icu，请稍后重试。",
        "网络响应无效": "无法连接 Intervals.icu，请稍后重试。",
        "ICU 未返回账户": "无法获取账户信息，请稍后重新连接。",
        "此数据库属于其他 ICU 账户": "当前数据关联了另一个 Intervals.icu 账户，请使用原账户连接。",
        "备份属于其他 ICU 账户": "备份关联的 Intervals.icu 账户与当前账户不同，无法导入。",
        "ICU 活动返回格式无效": "无法读取活动，请稍后重新同步。",
        "ICU 活动详情返回格式无效": "无法读取活动详情，请稍后重新同步。",
        "ICU Gear 返回格式无效": "无法读取装备，请稍后重新同步。",
        "请连接 Intervals.icu": "请先连接 Intervals.icu。",
        "请等待同步完成": "正在同步，请完成后重试。",
        "正在恢复备份，请完成后重试。": "正在恢复备份，请完成后重试。",
        "请返回当前后再修改": "历史快照无法修改，请先返回当前。",
        "ICU 主装备已在别处修改，请先同步活动": "Intervals.icu 上的主装备已更改，请同步活动后重试。",
        "图片无效": "无法读取这张图片，请重新选择。",
        "图片过大": "处理后的图片超过 10 MB，请选择较小的图片。",
        "备份过大": "备份必须小于 500 MB，请选择较小的备份文件。",
        "备份数据无效": "无法读取备份，请选择完整的 Gearhouse 备份。",
        "备份图片标识无效": "备份中的图片信息损坏，请重新导出备份。",
        "备份缺少图片，请使用包含图片的完整备份": "备份中的图片缺失或无法读取，请重新导出完整备份。",
        "备份图片校验失败": "备份中的图片损坏，请重新导出备份。",
        "备份图片与本机同名图片冲突": "备份图片与现有图片冲突，无法导入。",
        "备份包含重复提醒": "备份中的提醒重复，无法导入，请重新导出备份。",
        "当前 App 缺少钥匙串签名权限，请安装修复后的版本。": "此版本无法保存连接信息，请安装修复后的版本。",
        "请求标识无效": "无法保存记录，请重新打开后重试。",
        "请求标识已用于其他修改": "无法保存记录，请重新打开后重试。",
        "装配历史存在环路": "装配记录中的装备互相包含，请检查装配记录。",
        "所属装备不能是自身或子装备（含后续历史关系）": "无法移动：这会让装备包含自身，请检查装配记录。",
        "所属装备不能是自身或子装备（含历史关系）": "无法移动：这会让装备包含自身，请检查装配记录。",
        "所属装备不能是自身或子装备": "不能移入自身或自己的组件。",
        "所属装备不能是自身": "不能将装备装到自身。",
        "装备重复": "同一件装备只能选择一次。",
        "没有可整理的共同装配时段": "这两件装备没有同时安装的时段，无法整理层级。",
        "整理层级不能改变装备归属，请使用变更装配": "移到另一件装备时，请选择“变更装配”。",
        "请确认停用 ICU 历史基数": "请确认不再计入导入的历史累计值。",
        "请选择可关联的 Bike / Shoes": "请选择 Intervals.icu 中的自行车或跑鞋。",
        "主装备必须是 Bike / Shoes": "主装备只能选择自行车或跑鞋。",
        "装备类型与远端类型不一致": "请选择相同类型的 Intervals.icu 装备。",
        "该 ICU 装备已关联其他本地装备": "这件 Intervals.icu 装备已关联另一件装备，请重新选择。",
        "活动不可编辑，请先读取完整数据": "活动信息不完整，暂时无法修改装备，请重新同步。",
        "附加装备无效": "所选锁鞋或骑行台已不可用，请重新选择。",
        "排除装备无效": "活动的装备信息已变化，请重新打开活动。",
        "记录无效": "无法读取记录，请重新打开后重试。",
        "事件类型无效": "请选择记录类型。",
        "日期无效": "请选择有效的日期。",
        "时刻无效": "请选择有效的时间。",
        "时间格式无效": "请选择有效的时间。",
        "日期范围无效": "请选择有效的日期范围，结束日期不能晚于今天。",
        "购买时间格式无效": "请选择有效的购买日期。",
        "购买时间无效": "请选择有效的购买日期。",
        "类型无效": "请选择装备类型。",
        "备注无效": "请重新填写备注。",
        "图片标识无效": "无法添加图片，请重新选择。",
        "上传标识已用于其他图片": "无法添加图片，请重新选择。",
        "图片列表无效": "图片已变化，请重新打开记录。",
        "图片大小无效": "无法读取图片，请重新选择。",
        "图片格式无效": "无法读取图片，请重新选择。",
        "图片尺寸过大": "图片边长不能超过 2560 像素，请选择较小的图片。",
        "请重新选择图片以移除附带信息": "无法处理图片，请重新选择。",
        "图片所属内容不存在或不可编辑": "这条装备、活动或记录已不可编辑，无法添加图片。",
        "请输入装备名称": "请填写装备名称，最多 160 字。",
        "请输入有效的距离或天数": "距离须在 0–1,000,000 公里之间，天数须在 0–36,500 天之间。",
        "请填写累计公里数": "累计距离须大于 0 公里。",
        "请填写重复间隔": "重复间隔至少为 1 天。",
        "请选择一条历史记录": "请选择开始累计的记录。",
        "请选择有效的起点记录": "开始累计的记录已不可用，请重新选择。"
    ]
    private static let safeMessages: Set<String> = [
        "无法读取本机数据，请重新读取或从备份恢复。", "无法保留本机原文件，请检查存储空间后重试恢复。",
        "请重新连接 Intervals.icu 后再同步。",
        "备份文件过大，无法导出为 JSON。请使用 iCloud Drive 自动备份。", "本机数据已恢复，请重新导出备份。",
        "有备份尚未下载完成，请稍后重新读取。", "有备份无法读取，请重新读取或选择其他备份。",
        "有备份尚未下载完成，另有备份无法读取。请稍后重新读取或选择其他备份。",
        "ICU 主装备已变化，请重新选择。", "ICU 主装备已变化，请选择要保留的装备。", "请等待装备刷新完成。",
        "该日期已有更换或库存记录，请编辑原记录。",
        "已有后续装配或库存记录，请先处理后续记录。",
        "更换或库存记录已不存在，请重新打开。",
        "相关记录已修改，请重新打开后检查。",
        "库存记录不完整，请选择完整备份。",
        "请选择装备状况。", "购买日期不能晚于今天。",
        "请选择装备操作。",
        "该装备在所选日期未装配，请选择其他日期。",
        "请先恢复使用，再更换装备。",
        "只能更换同一类别的装备。",
        "所选装备不在库存，请重新选择。",
        "装配日期不能早于新件的购买日期。",
        "不能使用自身或上级装备进行更换。",
        "不能使用自身或组件进行更换。",
        "请选择旧件去向。",
        "所选组件已改变，请重新选择。",
        "请先恢复使用，再放入库存。",
        "该装备已在库存。",
        "请先恢复所属装备。",
        "请通过更换或库存记录修改这次装配。",
        "该装备在活动当天未使用，请先调整使用日期。",
        "当天已有装配记录，请编辑原记录。", "请选择 PDF 或图片。", "附件不能超过 20 MB。",
        "无法添加附件，请重新选择文件。", "无法读取附件，请重新选择文件。", "附件已存在，请重新选择文件。",
        "文件名过长，请重命名后重试。", "无法打开 PDF，请选择可正常阅读的文件。",
        "附件已删除，请重新打开装备。", "请确认删除附件。", "找不到附件，请从完整备份恢复或重新添加。",
        "无法读取附件，请重新选择完整备份。", "附件信息不完整，请重新选择完整备份。",
        "附件文件不完整，请重新添加后再备份。", "附件校验失败，请重新添加后再备份。",
        "备份附件信息不完整，请重新选择完整备份。", "备份附件校验失败，请重新选择完整备份。",
        "备份附件与本机文件冲突，请重新选择备份。", "备份缺少附件或附件已损坏，请重新选择完整备份。",
        "请完成恢复或返回当前后再添加附件。",
        "请选择要移动的装备。", "无法读取拖动的装备，请重试。", "装备已不可用，请重新选择。",
        "每次最多调整 499 件装备，请先保存或撤销部分修改。",
        "每次最多调整 499 件装备，请减少选择后重试。",
        "无法读取装备类别，请选择完整备份。", "备份中的装备类别重复或损坏，请重新导出备份。",
        "备份中的装备类别名称重复或损坏，请重新导出备份。", "内置类别的基础类型不能修改。",
        "装备的类别已不存在，请检查备份。", "类别已不存在，请重新打开。", "请填写类别名称，最多 80 字。",
        "已有同名类别，请使用其他名称。", "请选择基础类型。", "该类别已有装备，不能修改基础类型。",
        "请选择是否计入室内骑行距离。", "内置类别不能删除。", "请确认删除类别。",
        "请为关联装备选择替代类别。", "请选择相同基础类型的替代类别。", "请选择装备类别。",
        "该类别下没有可重算的装备。", "备份中的装备类别不一致，请重新导出备份。",
        "操作未完成，请重试。", "网络已断开，请连接网络后重试。", "连接超时，请重试。", "操作已取消。",
        "连接失败，请检查 API Key。", "连接已失效，请检查并更新 API Key。", "找不到这条记录，可能已被删除。",
        "请求过于频繁，请稍后重试。", "Intervals.icu 暂时无法完成请求，请稍后重试。",
        "无法读取 Intervals.icu 的数据，请稍后重试。", "无法读取数据，内容可能不完整。",
        "存储空间不足，请清理空间后重试。", "找不到文件，请重新选择。", "无法访问文件，请重新选择保存位置或文件。",
        "无法读取或保存文件，请重试。", "无法保存连接信息，请重试。",
        "装备不存在", "装备不存在或已删除", "装备已删除", "所属装备不存在或已删除", "装备不在回收站",
        "请先恢复装备", "请先恢复所属装备", "请先将装备移入回收站", "请先移出该装备下的组件",
        "没有可保存的修改", "该时间已有装配记录，请编辑原记录", "不能设置未来的装配时间",
        "装配记录不存在", "不能修改记录所属装备", "记录不存在", "不能记录未来的事件", "请输入 1–80 字的名称",
        "备注不能超过 2000 字", "数据已更新，请重新预览", "活动已有后续修改", "活动不存在",
        "请先恢复装备，或选择有效装备", "请确认删除记录", "请确认永久删除", "请创建新装备",
        "整理层级需要选择不同的所属装备", "请选择日期范围", "重算选项无效",
        "请选择有效的图片", "请通过编辑记录添加图片", "最多添加 40 张图片", "请通过编辑记录管理图片",
        "请确认删除图片", "请选择装备照片", "图片列表已更新，请重新打开", "图片不属于这条记录",
        "请填写提醒事项（最多 100 字）", "请设置距离或天数", "无法安排通知，请重试。", "无法开启通知，请重试。"
    ]
}
public extension Error {
    var userFacingMessage: String {
        Logger(subsystem: "com.equationzhao.Gearhouse", category: "Errors").error("\(String(reflecting: self), privacy: .private)")
        return UserFacingError.message(self)
    }
}
