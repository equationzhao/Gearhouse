import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeInventoryForm: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    let kind: String
    var operation: Value = [:]
    @State private var date = Date()
    @State private var replacementID = ""
    @State private var parentID = ""
    @State private var oldID = ""
    @State private var destination = "stock"
    @State private var childIDs = Set<String>()
    @State private var transferChildren = false
    @State private var newName = ""
    @State private var purchased = Date()
    @State private var hasPurchase = false
    @State private var condition = "unused"
    @State private var options: Value = [:]
    @State private var preview: Value = [:]
    @State private var error: String?
    @State private var reviewing = false
    @State private var saved = false
    @State private var deleting = false
    @State private var loaded = false
    private var gear: Value { options["gear"].isNull ? store.gear(gearID) : options["gear"] }
    private var day: String { NativeDate.format(date, "yyyy-MM-dd") }
    private var isReplacement: Bool { kind == "replace" || (kind == "install" && !oldID.isEmpty && oldID != "choose") }
    private var title: String {
        switch kind {
        case "replace": return "更换" + store.categoryName(for: gear)
        case "store": return store.parent(gearID).isEmpty ? "放入库存" : "拆下并入库"
        case "activate": return "取出使用"
        default: return "装到装备"
        }
    }
    private var submitTitle: String { isReplacement ? "完成更换" : kind == "install" ? "完成装配" : title }
    private var targets: [Value] {
        guard !parentID.isEmpty else { return [] }
        return store.gears.filter { $0.id != gearID && $0["deletedAt"].isNull && $0["categoryId"] == gear["categoryId"] && store.parent($0.id, at: day + "T23:59:59") == parentID && store.status($0.id, at: day + "T23:59:59") != "retired" }
    }
    private var children: [Value] {
        if kind == "replace" { return options["children"].array }
        return store.gears.filter { $0["deletedAt"].isNull && store.parent($0.id, at: day + "T23:59:59") == oldID && !oldID.isEmpty }
    }
    private var input: Value {
        var value: Value = ["kind": .string(isReplacement ? "replace" : kind), "gearId": .string(kind == "install" && isReplacement ? oldID : gearID), "at": .string(day), "destination": .string(destination), "childIds": .array(transferChildren ? childIDs.sorted().map(Value.string) : [])]
        if !operation.id.isEmpty { value["operationId"] = operation["id"] }
        if kind == "replace" {
            if replacementID == "new" {
                value["newGear"] = ["name": .string(newName), "categoryId": gear["categoryId"], "condition": .string(condition), "purchased": hasPurchase ? .string(NativeDate.format(purchased, "yyyy-MM-dd")) : .null]
            } else { value["replacementId"] = .string(replacementID) }
        } else if kind == "install" {
            if isReplacement { value["replacementId"] = .string(gearID) }
            else { value["parentId"] = .string(parentID) }
        }
        return value
    }
    private var canPreview: Bool {
        if !error.isNilOrEmpty && options["gear"].isNull { return false }
        if kind == "replace" { return !replacementID.isEmpty && (replacementID != "new" || !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        return kind != "install" || (!parentID.isEmpty && (targets.isEmpty || oldID != "choose"))
    }
    var body: some View {
        Form {
            if saved {
                Section {
                    LabeledContent("日期", value: day)
                    if isReplacement { LabeledContent("换上", value: store.displayName(preview["replacementId"].text)) }
                    if preview["affectedActivities"].integer > 0 {
                        Text("有 \(preview["affectedActivities"].integer) 条已有活动的装配与本次修改不同。")
                        ForEach(preview["recomputeGearIds"].array.map(\.text), id: \.self) { id in
                            NavigationLink("重算 " + store.name(id)) { NativeRecompute(gearID: id, from: preview["recomputeFrom"].text, scope: "subtree") }
                        }
                    }
                }
            } else if reviewing {
                Section {
                    LabeledContent("日期", value: day)
                    LabeledContent(isReplacement ? "换下" : "装备", value: store.displayName(preview["gearId"].text))
                    if isReplacement {
                        LabeledContent("换上", value: store.gear(preview["replacementId"].text).id.isEmpty ? preview["newName"].text : store.displayName(preview["replacementId"].text))
                        LabeledContent("旧件去向", value: destination == "stock" ? "库存" : "退役")
                    }
                    if !preview["parentName"].isNull && (isReplacement || kind == "install") { LabeledContent("装到", value: preview["parentName"].text) }
                    ForEach(preview["transferred"].array) { row in LabeledContent(row["name"].text, value: "转装到新件") }
                }
                if preview["sameDayActivities"].integer > 0 {
                    Section { Text("当天有 \(preview["sameDayActivities"].integer) 条已有活动。已有记录保持原样，之后导入的当天活动按修改后的装配计算。") }
                }
                if preview["affectedActivities"].integer > 0 {
                    Section { Text("本次修改涉及 \(preview["affectedActivities"].integer) 条已有活动，保存后可预览重算。") }
                }
            } else {
                editSections
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(saved ? "已保存" : reviewing ? "确认" + title : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(saved ? "完成" : reviewing ? "返回" : "取消") {
                    if reviewing && !saved { reviewing = false; error = nil } else { dismiss() }
                }
            }
            if !saved {
                ToolbarItem(placement: .confirmationAction) {
                    Button(reviewing ? submitTitle : "下一步") { reviewing ? saveOperation() : loadPreview() }
                        .disabled(!canPreview).accessibilityIdentifier("inventory-next")
                }
            }
        }
        .task {
            guard !loaded else { return }; loaded = true
            if !operation.id.isEmpty {
                date = NativeDate.parse(operation["at"].text); replacementID = operation["replacementId"].text
                parentID = operation["parentId"].text; destination = operation["destination"].text
                childIDs = Set(operation["childIds"].array.map(\.text)); transferChildren = !childIDs.isEmpty
            }
            newName = store.name(gearID) + " 新件"
            loadOptions()
        }
        .onChange(of: day) { _, _ in
            if purchased > date { purchased = date }
            loadOptions()
            if kind == "install" { oldID = targets.isEmpty ? "" : "choose" }
        }
        .onChange(of: parentID) { _, _ in oldID = targets.isEmpty ? "" : "choose" }
        .onChange(of: oldID) { _, _ in childIDs = []; transferChildren = false }
        .onChange(of: store.revision) { _, _ in if !saved { reviewing = false; loadOptions() } }
        .confirmationDialog("删除这条记录？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do { try store.commit("inventory-delete", ["id": operation["id"], "confirmed": true, "revision": preview["revision"]]); dismiss() }
                catch { self.error = error.userFacingMessage }
            }
        } message: { Text("这次装配和库存变更将一起撤回，已有活动记录保留。") }
    }
    @ViewBuilder private var editSections: some View {
        Section { LabeledContent(kind == "replace" ? "换下" : "装备", value: store.displayName(gearID))
            DatePicker(kind == "replace" ? "更换日期" : "生效日期", selection: $date, in: ...Date(), displayedComponents: .date)
                .accessibilityIdentifier("inventory-date")
        }
        if kind == "replace" {
            Section("换上") {
                NavigationLink {
                    NativeReplacementPicker(candidates: options["candidates"].array, selection: $replacementID)
                } label: {
                    LabeledContent("装备", value: replacementID == "new" ? "新建装备" : replacementID.isEmpty ? "请选择" : store.displayName(replacementID))
                }.accessibilityIdentifier("replacement-choice")
                if replacementID == "new" {
                    TextField("名称", text: $newName).accessibilityIdentifier("replacement-name")
                    LabeledContent("类别", value: store.categoryName(for: gear))
                    Picker("装备状况", selection: $condition) { Text("未使用").tag("unused"); Text("已使用").tag("used"); Text("未填写").tag("") }
                    Toggle("购买日期", isOn: $hasPurchase)
                    if hasPurchase { DatePicker("日期", selection: $purchased, in: ...date, displayedComponents: .date) }
                }
            }
        }
        if kind == "install" {
            Section {
                Picker("所属装备", selection: $parentID) { Text("请选择").tag(""); ForEach(options["parents"].array) { row in Text(row["name"].text).tag(row.id) } }.accessibilityIdentifier("inventory-parent")
                if !targets.isEmpty {
                    Picker("装配方式", selection: $oldID) {
                        Text("请选择").tag("choose")
                        Text("作为新增组件").tag("")
                        ForEach(targets) { row in Text("替换 " + row["name"].text).tag(row.id) }
                    }.accessibilityIdentifier("inventory-install-mode")
                }
            }
        }
        if isReplacement {
            Section { Picker("旧件去向", selection: $destination) { Text("放入库存").tag("stock"); Text("退役").tag("retired") } }
            if !children.isEmpty {
                Section("子组件") {
                    Toggle("转装到新件", isOn: $transferChildren)
                    if transferChildren {
                        ForEach(children) { row in
                            Toggle(row["name"].text, isOn: Binding(get: { childIDs.contains(row.id) }, set: { if $0 { childIDs.insert(row.id) } else { childIDs.remove(row.id) } }))
                        }
                    } else { ForEach(children) { row in LabeledContent(row["name"].text, value: "随旧件保留") } }
                }
            }
        }
        if !operation.id.isEmpty {
            Section { Button("删除记录", role: .destructive) {
                do { preview = try store.query("inventory-delete-preview", ["id": operation["id"]]); deleting = true; error = nil }
                catch { self.error = error.userFacingMessage }
            } }
        }
    }
    private func loadOptions() {
        do {
            var request: Value = ["gearId": .string(gearID), "at": .string(day)]
            if !operation.id.isEmpty { request["operationId"] = operation["id"] }
            options = try store.query("inventory-options", request)
            if replacementID != "new" && !replacementID.isEmpty && !options["candidates"].array.contains(where: { $0.id == replacementID }) { replacementID = "" }
            childIDs.formIntersection(Set(children.map(\.id)))
            error = nil
        } catch { options = [:]; self.error = error.userFacingMessage }
    }
    private func loadPreview() {
        do { preview = try store.query("inventory-preview", input); reviewing = true; error = nil }
        catch { self.error = error.userFacingMessage }
    }
    private func saveOperation() {
        do {
            var request = input; request["revision"] = preview["revision"]
            preview = try store.commit("inventory-save", request)
            saved = true; error = nil
            if preview["affectedActivities"].integer == 0 { dismiss() }
        } catch { self.error = error.userFacingMessage; reviewing = false }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty != false }
}

struct NativeInventoryActions: View {
    @EnvironmentObject private var store: NativeStore
    let gearID: String
    let open: (String) -> Void
    var body: some View {
        let status = store.status(gearID)
        if status == "retired" {
            Button("恢复使用", systemImage: "arrow.uturn.backward") { open("activate") }
        } else {
            if !store.parent(gearID).isEmpty {
                Button("更换", systemImage: "arrow.triangle.2.circlepath") { open("replace") }.accessibilityIdentifier("gear-replace")
            }
            if status == "stock" {
                Button("装到装备", systemImage: "link") { open("install") }.accessibilityIdentifier("gear-install")
                if ["Bike", "Shoes", "CyclingShoes", "Trainer"].contains(store.gear(gearID)["type"].text) {
                    Button("取出使用", systemImage: "arrow.up.forward.app") { open("activate") }
                }
            } else {
                Button(store.parent(gearID).isEmpty ? "放入库存" : "拆下", systemImage: "shippingbox") { open("store") }.accessibilityIdentifier("gear-store")
            }
        }
    }
}

struct NativeReplacementPicker: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let candidates: [Value]
    @Binding var selection: String
    @State private var query = ""
    var body: some View {
        List {
            Section { Button("新建装备", systemImage: "plus") { selection = "new"; dismiss() } }
            Section("库存") {
                ForEach(candidates.filter { query.isEmpty || $0["name"].text.localizedCaseInsensitiveContains(query) }) { gear in
                    Button { selection = gear.id; dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(store.displayName(gear.id)); Text(nativeDistance(store.view["statistics"][gear.id]["distance"])).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if selection == gear.id { Image(systemName: "checkmark") }
                        }
                    }.foregroundStyle(.primary).accessibilityIdentifier("replacement-" + gear.id)
                }
                if candidates.isEmpty { Text("暂无同类别库存").foregroundStyle(.secondary) }
            }
        }.navigationTitle("选择装备").searchable(text: $query, prompt: "查找同类别装备")
    }
}

struct NativeInventoryBatchForm: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearIDs: [String]
    @State private var date = Date()
    @State private var preview: Value = .null
    @State private var error: String?
    @State private var saved = false
    private var input: Value { ["gearIds": .array(gearIDs.map(Value.string)), "at": .string(NativeDate.format(date, "yyyy-MM-dd"))] }
    var body: some View {
        Form {
            if preview.isNull {
                Section { DatePicker("入库日期", selection: $date, in: ...Date(), displayedComponents: .date) }
                Section { ForEach(gearIDs, id: \.self) { Text(store.name($0)) } }
            } else {
                Section { ForEach(preview["rows"].array) { row in LabeledContent(row["oldName"].text, value: "放入库存") } }
                if preview["affectedActivities"].integer > 0 {
                    Section {
                        Text("有 \(preview["affectedActivities"].integer) 条已有活动的装配与此次修改不同，已有记录保持原样。")
                        if saved {
                            ForEach(Array(Set(preview["rows"].array.flatMap { $0["recomputeGearIds"].array.map(\.text) })).sorted(), id: \.self) { id in
                                NavigationLink("重算 " + store.name(id)) { NativeRecompute(gearID: id, from: input["at"].text, scope: "subtree") }
                            }
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(preview.isNull ? "放入库存" : "确认入库").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(saved ? "完成" : "取消") { dismiss() } }
            if !saved { ToolbarItem(placement: .confirmationAction) {
                Button(preview.isNull ? "下一步" : "放入库存") {
                    do {
                        if preview.isNull { preview = try store.query("inventory-batch-preview", input) }
                        else { var request = input; request["revision"] = preview["revision"]; preview = try store.commit("inventory-batch", request); saved = true; if preview["affectedActivities"].integer == 0 { dismiss() } }
                        error = nil
                    } catch { self.error = error.userFacingMessage; preview = .null }
                }
            } }
        }
    }
}
