import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeGearForm: View {
    private enum Field: Hashable { case name, notes }
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
    @State private var refreshError: String?
    @State private var initialDraft: Value?
    @State private var confirmingDiscard = false
    @State private var editedName = false
    @FocusState private var focusedField: Field?
    init(existing: Value = [:], parent: String = "", copying: Bool = false, placement: String = "active") {
        self.existing = existing; self.parent = copying ? "" : parent; self.copying = copying; self.initialPlacement = copying ? "stock" : placement
        _condition = State(initialValue: existing["condition"].isNull ? (placement == "stock" ? "unused" : "") : existing["condition"].text)
        _name = State(initialValue: existing["name"].text); _categoryID = State(initialValue: existing["categoryId"].text.isEmpty ? (existing["type"].text.isEmpty ? "Equipment" : existing["type"].text) : existing["categoryId"].text)
        _notes = State(initialValue: existing["notes"].text); _retired = State(initialValue: !copying && existing["retired"].flag)
        _remote = State(initialValue: copying ? "" : existing["remoteId"].text); _purchased = State(initialValue: NativeDate.parse(existing["purchased"].text))
        _hasPurchase = State(initialValue: !copying && !existing["purchased"].isNull)
    }
    private var type: String { store.category(categoryID)["baseType"].text }
    private var missingName: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasChanges: Bool { initialDraft.map { $0 != buildDraft() } ?? false }
    var body: some View {
        Form {
            Section("装备信息") {
                TextField("名称", text: $name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .notes }
                    .accessibilityIdentifier("gear-name")
                if editedName && missingName {
                    Text("请输入装备名称").font(.footnote).foregroundStyle(NativeAppearance.dangerText)
                        .accessibilityIdentifier("gear-name-error")
                }
                if copying { LabeledContent("类别", value: store.categoryName(categoryID)) }
                else { NavigationLink { NativeCategoryPicker(selection: $categoryID) } label: { LabeledContent("类别", value: store.categoryName(categoryID)) }.accessibilityIdentifier("gear-category") }
                if !copying && !existing.id.isEmpty { Toggle("已退役", isOn: $retired) }
                Picker("装备状况", selection: $condition) { Text("未填写").tag(""); Text("未使用").tag("unused"); Text("已使用").tag("used") }
            }
            Section("备注") {
                TextField("备注", text: $notes, axis: .vertical).lineLimit(3...8)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("gear-notes")
            }
            Section("购买信息") {
                Toggle("记录购买日期", isOn: $hasPurchase)
                if hasPurchase { DatePicker("日期", selection: $purchased, in: ...Date(), displayedComponents: .date) }
            }
            if !copying && parent.isEmpty && ["Bike", "Shoes"].contains(type) {
                Section {
                    Picker("Intervals.icu 装备", selection: $remote) {
                        Text("无").tag("")
                        ForEach(store.state["remoteGears"].array.filter { row in !row["component"].flag && row["type"].text == type && !store.state["gears"].array.contains(where: { gear in gear.id != existing.id && gear["remoteId"].text == row.id }) }) { row in Text(row["name"].text).tag(row.id) }
                        if !remote.isEmpty && !store.state["remoteGears"].array.contains(where: { $0.id == remote }) {
                            Text("保留现有关联").tag(remote)
                        }
                    }
                    Button(store.refreshingGears ? "刷新中…" : "刷新 ICU 装备") {
                        Task { do { try await store.refreshRemoteGears(); refreshError = nil } catch let failure { refreshError = failure.userFacingMessage } }
                    }.disabled(!store.connected || store.busy || store.refreshingGears).accessibilityIdentifier("gear-refresh-remote")
                    if let refreshError { Text(refreshError).foregroundStyle(NativeAppearance.dangerText) }
                }
            }
            if !parent.isEmpty { Section { LabeledContent("所属装备", value: store.name(parent)); DatePicker("装配日期", selection: $at, in: ...Date(), displayedComponents: .date) } }
            if copying && store.reminders.contains(where: { $0.gearID == existing.id }) { Section { Toggle("复制提醒规则", isOn: $copyReminders) } }
            if let error { Text(error).foregroundStyle(NativeAppearance.dangerText) }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(copying ? "复制装备" : existing.id.isEmpty ? (parent.isEmpty ? (initialPlacement == "stock" ? "添加库存" : "添加装备") : "新建组件") : "编辑装备").navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loadedStatus else { return }
            loadedStatus = true
            if !existing.id.isEmpty && !copying { retired = GearInventory.readOwnStatus(state: store.state, gearID: existing.id, at: NativeDate.now) == "retired" }
            initialDraft = buildDraft()
        }
        .onChange(of: name) { _, _ in editedName = true }
        .onChange(of: focusedField) { previous, _ in if previous == .name { editedName = true } }
        .onChange(of: type) { _, _ in remote = "" }
        .interactiveDismissDisabled(hasChanges)
        .navigationBarBackButtonHidden(hasChanges)
        .alert("放弃未保存的更改？", isPresented: $confirmingDiscard) {
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: requestCancel) }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: saveGear).disabled(missingName) }
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil { Spacer(); Button("完成") { focusedField = nil }.accessibilityIdentifier("gear-keyboard-done") }
            }
        }
    }
    private func buildGearInput() -> Value {
        var input: Value = ["name": .string(name), "type": .string(type), "categoryId": .string(categoryID), "notes": .string(notes), "retired": .bool(retired), "remoteId": .optional(remote), "purchased": hasPurchase ? .string(NativeDate.format(purchased,"yyyy-MM-dd")) : .null]
        input["condition"] = .string(condition); input["placement"] = .string(initialPlacement)
        if !existing.id.isEmpty && !copying { input["id"] = existing["id"] }
        return input
    }
    private func buildDraft() -> Value {
        ["gear": buildGearInput(), "copyReminders": .bool(copyReminders), "at": parent.isEmpty ? .null : .string(NativeDate.format(at, "yyyy-MM-dd"))]
    }
    private func requestCancel() {
        focusedField = nil
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }
    private func saveGear() {
        focusedField = nil
        do {
            let input = buildGearInput()
            if copying { try store.commit("gear-copy", ["sourceId": existing["id"], "gear": input, "copyReminders": .bool(copyReminders)]) }
            else if parent.isEmpty { try store.commit("gear", input) }
            else { try store.commit("component", ["parentId": .string(parent), "gear": input, "at": .string(NativeDate.format(at,"yyyy-MM-dd"))]) }
            dismiss()
        } catch let failure { error = failure.userFacingMessage }
    }
}
