import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeHistoryForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    let existing: Value
    @State private var parent: String
    @State private var at: Date
    @State private var error: String?
    init(gearID: String, existing: Value) {
        self.gearID = gearID; self.existing = existing
        _parent = State(initialValue: existing["parentId"].text); _at = State(initialValue: NativeDate.parse(existing["at"].text))
    }
    var body: some View {
        Form {
            Picker("所属装备", selection: $parent) {
                Text("未装配").tag("")
                ForEach(store.gears.filter { $0.id != gearID && $0["deletedAt"].isNull }) { Text($0["name"].text).tag($0.id) }
            }
            DatePicker("生效日期", selection: $at, in: ...Date(), displayedComponents: .date).accessibilityIdentifier("installation-date")
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(existing.id.isEmpty ? "添加装配" : "编辑装配").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorButtons {
            do {
                var input: Value = ["gearId": .string(gearID), "parentId": .optional(parent), "at": .string(NativeDate.format(at,"yyyy-MM-dd"))]
                if !existing.id.isEmpty { input["id"] = existing["id"] }
                try store.commit("history-save", input); dismiss()
            } catch let failure { error = failure.userFacingMessage }
        } }
    }
}
