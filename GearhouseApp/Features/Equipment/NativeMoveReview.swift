import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeMoveReview: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let changes: [Value]
    let complete: () -> Void
    @State private var mode = "move"
    @State private var at = Date()
    @State private var preview: Value = .null
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("操作", selection: $mode) { Text("变更装配").tag("move"); Text("整理层级").tag("organize") }
                    ForEach(changes, id: \.gearID) { change in
                        VStack(alignment: .leading) { Text(store.name(change["gearId"].text)); Text(store.name(change["fromParentId"].text) + " → " + store.name(change["parentId"].text)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if mode == "move" { Section { DatePicker("生效日期", selection: $at, in: ...Date(), displayedComponents: .date) } }
                else {
                    Section("影响时段") {
                        Button("预览") { do { preview = try store.query("organize-preview", ["changes": .array(changes)]); message = nil } catch let failure { message = failure.userFacingMessage } }
                        ForEach(preview["rows"].array, id: \.gearID) { row in
                            VStack(alignment: .leading) {
                                Text(store.name(row["gearId"].text))
                                ForEach(Array(row["ranges"].array.enumerated()), id: \.offset) { _, range in Text(String(range["from"].text.prefix(10)) + " – " + (range["to"].isNull ? "持续中" : String(range["to"].text.prefix(10)))).font(.caption) }
                                if row["ranges"].array.isEmpty { Text("无共同装配时段").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("保存修改").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    do {
                        if mode == "move" { try store.commit("moves", ["changes": .array(changes), "at": .string(NativeDate.format(at, "yyyy-MM-dd"))]) }
                        else { try store.commit("organize", ["changes": .array(changes), "revision": preview["revision"]]) }
                        complete(); dismiss()
                    } catch let failure { message = failure.userFacingMessage }
                }.accessibilityIdentifier("gear-moves-save").disabled(mode == "organize" && (preview["changed"].integer == 0 || preview["revision"] != store.revision)) }
            }
        }
    }
}
