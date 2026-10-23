import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeGearForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let existing: Value
    let parent: String
    let copying: Bool
    let initialPlacement: String
    @State private var condition: String
    @State private var loadedStatus = false
    @State private var copyReminders = true
    @State private var name: String
    @State private var categoryID: String
    @State private var notes: String
    @State private var retired: Bool
    @State private var remote: String
    @State private var purchased: Date
    @State private var hasPurchase: Bool
    @State private var at = Date()
    @State private var error: String?
    init(existing: Value = [:], parent: String = "", copying: Bool = false, placement: String = "active") {
        self.existing = existing; self.parent = copying ? "" : parent; self.copying = copying; self.initialPlacement = copying ? "stock" : placement
        _condition = State(initialValue: existing["condition"].isNull ? (placement == "stock" ? "unused" : "") : existing["condition"].text)
        _name = State(initialValue: existing["name"].text); _categoryID = State(initialValue: existing["categoryId"].text.isEmpty ? (existing["type"].text.isEmpty ? "Equipment" : existing["type"].text) : existing["categoryId"].text)
        _notes = State(initialValue: existing["notes"].text); _retired = State(initialValue: !copying && existing["retired"].flag)
        _remote = State(initialValue: copying ? "" : existing["remoteId"].text); _purchased = State(initialValue: NativeDate.parse(existing["purchased"].text))
        _hasPurchase = State(initialValue: !copying && !existing["purchased"].isNull)
    }
    private var type: String { store.category(categoryID)["baseType"].text }
    var body: some View {
        Form {
            Section {
                TextField("名称", text: $name)
                if copying { LabeledContent("类别", value: store.categoryName(categoryID)) }
                else { NavigationLink { NativeCategoryPicker(selection: $categoryID) } label: { LabeledContent("类别", value: store.categoryName(categoryID)) }.accessibilityIdentifier("gear-category") }
                if !copying && !existing.id.isEmpty { Toggle("已退役", isOn: $retired) }
                Picker("装备状况", selection: $condition) { Text("未填写").tag(""); Text("未使用").tag("unused"); Text("已使用").tag("used") }
                TextField("备注", text: $notes, axis: .vertical).lineLimit(3...8)
            }
            Section {
                Toggle("购买日期", isOn: $hasPurchase)
                if hasPurchase { DatePicker("日期", selection: $purchased, in: ...Date(), displayedComponents: .date) }
            }
            if !copying && parent.isEmpty && ["Bike", "Shoes"].contains(type) {
                Section {
                    Picker("Intervals.icu 装备", selection: $remote) {
                        Text("无").tag("")
                        ForEach(store.state["remoteGears"].array.filter { row in !row["component"].flag && row["type"].text == type && !store.state["gears"].array.contains(where: { gear in gear.id != existing.id && gear["remoteId"].text == row.id }) }) { row in Text(row["name"].text).tag(row.id) }
                    }
                }
            }
            if !parent.isEmpty { Section { LabeledContent("所属装备", value: store.name(parent)); DatePicker("装配日期", selection: $at, in: ...Date(), displayedComponents: .date) } }
            if copying && store.reminders.contains(where: { $0.gearID == existing.id }) { Section { Toggle("复制提醒规则", isOn: $copyReminders) } }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(copying ? "复制装备" : existing.id.isEmpty ? (parent.isEmpty ? (initialPlacement == "stock" ? "添加库存" : "添加装备") : "新建组件") : "编辑装备").navigationBarTitleDisplayMode(.inline)
        .task { if !loadedStatus { loadedStatus = true; if !existing.id.isEmpty && !copying { retired = store.status(existing.id) == "retired" } } }
        .onChange(of: type) { _, _ in remote = "" }
        .toolbar { EditorButtons(disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            do {
                var input: Value = ["name": .string(name), "type": .string(type), "categoryId": .string(categoryID), "notes": .string(notes), "retired": .bool(retired), "remoteId": .optional(remote), "purchased": hasPurchase ? .string(NativeDate.format(purchased,"yyyy-MM-dd")) : .null]
                input["condition"] = .string(condition); input["placement"] = .string(initialPlacement)
                if !existing.id.isEmpty && !copying { input["id"] = existing["id"] }
                if copying { try store.commit("gear-copy", ["sourceId": existing["id"], "gear": input, "copyReminders": .bool(copyReminders)]) }
                else if parent.isEmpty { try store.commit("gear", input) }
                else { try store.commit("component", ["parentId": .string(parent), "gear": input, "at": .string(NativeDate.format(at,"yyyy-MM-dd"))]) }
                dismiss()
            } catch let failure { error = failure.userFacingMessage }
        } }
    }
}
