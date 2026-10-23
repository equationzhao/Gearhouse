import Foundation

public struct GearTreeDrag: Codable, Equatable, Sendable {
    public let gearIDs: [String]
    private let version: Int

    public init(gearIDs: [String]) throws {
        guard !gearIDs.isEmpty, gearIDs.count < 500, gearIDs.allSatisfy({ !$0.isEmpty }) else {
            throw DomainError("请选择要移动的装备。")
        }
        var seen = Set<String>()
        self.gearIDs = gearIDs.filter { seen.insert($0).inserted }
        version = 1
    }
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> GearTreeDrag {
        guard data.count <= 65536,
              let payload = try? JSONDecoder().decode(GearTreeDrag.self, from: data), payload.version == 1 else {
            throw DomainError("无法读取拖动的装备，请重试。")
        }
        return try GearTreeDrag(gearIDs: payload.gearIDs)
    }

    /// Pending edits describe tree position only; installation history changes at save time.
    public func staging(onto target: String, originalParents: [String: String], pending: [String: String]) throws -> [String: String] {
        guard gearIDs.allSatisfy({ originalParents[$0] != nil }), target.isEmpty || originalParents[target] != nil else {
            throw DomainError("装备已不可用，请重新选择。")
        }
        func parent(_ id: String) -> String { pending[id] ?? originalParents[id] ?? "" }
        let chosen = Set(gearIDs)
        let roots = gearIDs.filter { id in
            var ancestor = parent(id), seen = Set<String>()
            while !ancestor.isEmpty && seen.insert(ancestor).inserted {
                if chosen.contains(ancestor) { return false }
                ancestor = parent(ancestor)
            }
            return true
        }
        guard !roots.isEmpty else { throw DomainError("不能移入自身或自己的组件。") }
        for id in roots {
            var ancestor = target, seen: Set<String> = [id]
            while !ancestor.isEmpty {
                guard seen.insert(ancestor).inserted else { throw DomainError("不能移入自身或自己的组件。") }
                ancestor = parent(ancestor)
            }
        }
        var next = pending
        for id in roots {
            if originalParents[id] == target { next.removeValue(forKey: id) }
            else { next[id] = target }
        }
        return next
    }
}
