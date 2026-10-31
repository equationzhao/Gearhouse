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
    @State private var precise = false
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
    @State private var saving = false
    @State private var discarding = false
    @State private var initialDraft: Value?
    @FocusState private var editingName: Bool
    private var hasChanges: Bool { !saved && (initialDraft.map { $0 != input } ?? false) }
    private var gear: Value { options["gear"].isNull ? store.gear(gearID) : options["gear"] }
    private var day: String { NativeDate.format(date, "yyyy-MM-dd") }
    private var optionKey: String { day + (precise ? savedInstant : "") }
    private var savedInstant: String {
        if let original = NativeDate.parseInstant(operation["instant"].text), original == date { return operation["instant"].text }
        return NativeDate.instant(date)
    }
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
        return store.gears.filter { $0.id != gearID && $0["deletedAt"].isNull && $0["categoryId"] == gear["categoryId"] && options["parentsByID"][$0.id].text == parentID && options["statuses"][$0.id].text != "retired" }
    }
    private var children: [Value] {
        if kind == "replace" { return options["children"].array }
        return store.gears.filter { $0["deletedAt"].isNull && options["parentsByID"][$0.id].text == oldID && !oldID.isEmpty }
    }
    private var input: Value {
        var value: Value = ["kind": .string(isReplacement ? "replace" : kind), "gearId": .string(kind == "install" && isReplacement ? oldID : gearID), "at": .string(day), "destination": .string(destination), "childIds": .array(transferChildren ? childIDs.sorted().map(Value.string) : [])]
        if precise { value["instant"] = .string(savedInstant) }
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
                    LabeledContent(precise ? "生效时间" : "日期", value: precise ? NativeDate.format(date, "yyyy-MM-dd HH:mm XXXXX") : day)
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
                    LabeledContent(precise ? "生效时间" : "日期", value: precise ? NativeDate.format(date, "yyyy-MM-dd HH:mm XXXXX") : day)
                    LabeledContent(isReplacement ? "换下" : "装备", value: store.displayName(preview["gearId"].text))
                    if isReplacement {
                        LabeledContent("换上", value: store.gear(preview["replacementId"].text).id.isEmpty ? preview["newName"].text : store.displayName(preview["replacementId"].text))
                        LabeledContent("旧件去向", value: destination == "stock" ? "库存" : "退役")
                    }
                    if !preview["parentName"].isNull && (isReplacement || kind == "install") { LabeledContent("装到", value: store.displayName(preview["parentId"].text)) }
                    ForEach(preview["transferred"].array) { row in
                        LabeledContent(store.displayName(row.id), value: "转装到新件")
                            .accessibilityIdentifier("inventory-preview-transfer-" + row.id)
                    }
                }
                if preview["sameDayActivities"].integer > 0 {
                    Section { Text(precise ? "当天有 \(preview["sameDayActivities"].integer) 条已有活动。已有记录保持原样；新导入的活动按开始时刻匹配装配。" : "当天有 \(preview["sameDayActivities"].integer) 条已有活动。已有记录保持原样，之后导入的当天活动按修改后的装配计算。") }
                }
                if preview["affectedActivities"].integer > 0 {
                    Section { Text("本次修改涉及 \(preview["affectedActivities"].integer) 条已有活动，保存后可预览重算。") }
                }
                if preview["timeUnknownActivities"].integer > 0 {
                    Section { Text("有 \(preview["timeUnknownActivities"].integer) 条活动缺少可靠开始时刻，暂无法判断组件归属；已有记录保持原样。") }
                }
            } else {
                editSections
            }
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) } }
        }
        .labeledContentStyle(NativeReadableValueStyle())
        .disabled(saving || store.readOnly)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(saved ? "已保存" : reviewing ? "确认" + title : title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving || hasChanges)
        .alert("放弃未保存的更改？", isPresented: $discarding) {
            Button("放弃更改", role: .destructive) { dismiss() }
                .accessibilityIdentifier("inventory-discard")
            Button("继续编辑", role: .cancel) {}
                .accessibilityIdentifier("inventory-continue-editing")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(saved ? "完成" : reviewing ? "返回" : "取消", action: requestCancel)
                    .disabled(saving).accessibilityIdentifier("inventory-cancel")
            }
            if !saved {
                ToolbarItem(placement: .confirmationAction) {
                    Button(reviewing ? submitTitle : "下一步") { reviewing ? saveOperation() : loadPreview() }
                        .disabled(saving || store.readOnly || !canPreview).accessibilityIdentifier("inventory-next")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if editingName { Spacer(); Button("完成") { editingName = false }.accessibilityIdentifier("inventory-keyboard-done") }
            }
        }
        .task {
            guard !loaded else { return }; loaded = true
            if !operation.id.isEmpty {
                date = NativeDate.parseInstant(operation["instant"].text) ?? NativeDate.parse(operation["at"].text); precise = !operation["instant"].isNull; replacementID = operation["replacementId"].text
                parentID = operation["parentId"].text; destination = operation["destination"].text
                childIDs = Set(operation["childIds"].array.map(\.text)); transferChildren = !childIDs.isEmpty
            }
            newName = store.name(gearID) + " 新件"
            loadOptions()
            initialDraft = input
        }
        .onChange(of: optionKey) { _, _ in
            if purchased > date { purchased = date }
            loadOptions()
            if kind == "install" { oldID = targets.isEmpty ? "" : "choose" }
        }
        .onChange(of: parentID) { _, _ in
            guard kind == "install" else { return }
            oldID = targets.isEmpty ? "" : "choose"
        }
        .onChange(of: oldID) { _, _ in
            guard kind == "install" else { return }
            childIDs = []; transferChildren = false
        }
        .onChange(of: store.revision) { _, _ in if !saved { reviewing = false; loadOptions() } }
        .confirmationDialog("删除这条记录？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                guard !saving, !store.readOnly else { return }
                saving = true
                defer { saving = false }
                do { try store.commit("inventory-delete", ["id": operation["id"], "confirmed": true, "revision": preview["revision"]]); dismiss() }
                catch { self.error = error.userFacingMessage }
            }
        } message: { Text("这次装配和库存变更将一起撤回，已有活动记录保留。") }
    }
    @ViewBuilder private var editSections: some View {
        Section { LabeledContent(kind == "replace" ? "换下" : "装备", value: store.displayName(gearID))
            DatePicker(kind == "replace" ? "更换日期" : "生效日期", selection: $date, in: ...Date(), displayedComponents: .date)
                .accessibilityIdentifier("inventory-date")
            Toggle("记录具体时间", isOn: $precise).accessibilityIdentifier("inventory-precise")
            if precise {
                DatePicker("生效时间", selection: $date, in: ...Date(), displayedComponents: .hourAndMinute).accessibilityIdentifier("inventory-time")
                LabeledContent("时区", value: "上海时间 " + NativeDate.format(date, "XXXXX"))
            }
        }
        if kind == "replace" {
            Section("换上") {
                NavigationLink {
                    NativeReplacementPicker(candidates: options["candidates"].array, selection: $replacementID)
                } label: {
                    LabeledContent("装备", value: replacementID == "new" ? "新建装备" : replacementID.isEmpty ? "请选择" : store.displayName(replacementID))
                }.accessibilityIdentifier("replacement-choice")
                if replacementID == "new" {
                    TextField("名称", text: $newName).focused($editingName).submitLabel(.done)
                        .onSubmit { editingName = false }.accessibilityIdentifier("replacement-name")
                    LabeledContent("类别", value: store.categoryName(for: gear))
                    Picker("装备状况", selection: $condition) { Text("未使用").tag("unused"); Text("已使用").tag("used"); Text("未填写").tag("") }
                        .accessibilityIdentifier("replacement-condition")
                    Toggle("购买日期", isOn: $hasPurchase).accessibilityIdentifier("replacement-has-purchase")
                    if hasPurchase { DatePicker("日期", selection: $purchased, in: ...date, displayedComponents: .date).accessibilityIdentifier("replacement-purchase-date") }
                }
            }
        }
        if kind == "install" {
            Section {
                Picker("所属装备", selection: $parentID) { Text("请选择").tag(""); ForEach(options["parents"].array) { row in Text(store.displayName(row.id)).tag(row.id) } }.accessibilityIdentifier("inventory-parent")
                if !targets.isEmpty {
                    Picker("装配方式", selection: $oldID) {
                        Text("请选择").tag("choose")
                        Text("作为新增组件").tag("")
                        ForEach(targets) { row in Text("替换 " + store.displayName(row.id)).tag(row.id) }
                    }.accessibilityIdentifier("inventory-install-mode")
                }
            }
        }
        if isReplacement {
            Section { Picker("旧件去向", selection: $destination) { Text("放入库存").tag("stock"); Text("退役").tag("retired") }.accessibilityIdentifier("inventory-destination") }
            if !children.isEmpty {
                Section("子组件") {
                    Toggle("转装到新件", isOn: $transferChildren).accessibilityIdentifier("inventory-transfer-children")
                    if transferChildren {
                        ForEach(children) { row in
                            Toggle(store.displayName(row.id), isOn: Binding(get: { childIDs.contains(row.id) }, set: { if $0 { childIDs.insert(row.id) } else { childIDs.remove(row.id) } }))
                                .accessibilityIdentifier("inventory-transfer-" + row.id)
                        }
                    } else { ForEach(children) { row in LabeledContent(store.displayName(row.id), value: "随旧件保留") } }
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
            if precise { request["instant"] = .string(savedInstant) }
            if !operation.id.isEmpty { request["operationId"] = operation["id"] }
            options = try store.query("inventory-options", request)
            if replacementID != "new" && !replacementID.isEmpty && !options["candidates"].array.contains(where: { $0.id == replacementID }) { replacementID = "" }
            childIDs.formIntersection(Set(children.map(\.id)))
            error = nil
        } catch { options = [:]; self.error = error.userFacingMessage }
    }
    private func loadPreview() {
        guard !saving, !store.readOnly else { return }
        editingName = false
        do { preview = try store.query("inventory-preview", input); reviewing = true; error = nil }
        catch { self.error = error.userFacingMessage }
    }
    private func saveOperation() {
        guard !saving, !store.readOnly else { return }
        saving = true
        defer { saving = false }
        do {
            var request = input; request["revision"] = preview["revision"]
            preview = try store.commit("inventory-save", request)
            saved = true; error = nil
            if preview["affectedActivities"].integer == 0 { dismiss() }
        } catch { self.error = error.userFacingMessage; reviewing = false }
    }
    private func requestCancel() {
        guard !saving else { return }
        editingName = false
        if reviewing && !saved { reviewing = false; error = nil }
        else if hasChanges { discarding = true }
        else { dismiss() }
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
    private var visibleCandidates: [Value] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { search.isEmpty || store.displayName($0.id).localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section { Button("新建装备", systemImage: "plus") { selection = "new"; dismiss() } }
            Section("库存") {
                ForEach(visibleCandidates) { gear in
                    Button { selection = gear.id; dismiss() } label: {
                        HStack(spacing: 12) {
                            NativeGearThumbnail(gearID: gear.id, size: 44)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.displayName(gear.id)).fixedSize(horizontal: false, vertical: true)
                                Text(nativeDistance(store.view["statistics"][gear.id]["distance"])).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                            }
                            Spacer(minLength: 0)
                            if selection == gear.id { Image(systemName: "checkmark").foregroundStyle(NativeAppearance.accent) }
                        }.padding(.vertical, 4)
                    }.foregroundStyle(.primary).accessibilityIdentifier("replacement-" + gear.id)
                        .accessibilityAddTraits(selection == gear.id ? .isSelected : [])
                }
                if candidates.isEmpty { Text("暂无同类别库存").foregroundStyle(NativeAppearance.secondaryText) }
                else if visibleCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("没有匹配的库存装备").foregroundStyle(NativeAppearance.secondaryText)
                        Button("清除搜索") { query = "" }.accessibilityIdentifier("replacement-clear-search")
                    }.padding(.vertical, 8)
                }
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
    @State private var excludedIDs = Set<String>()
    @State private var initialDraft: Value?
    @State private var discarding = false
    @State private var saving = false
    private var hasChanges: Bool { !saved && (initialDraft.map { $0 != input } ?? false) }
    private var includedIDs: [String] { gearIDs.filter { !excludedIDs.contains($0) } }
    private var blockedIDs: [String] {
        let at = NativeDate.format(date, "yyyy-MM-dd") + "T00:00:00"
        let index = GearTreeIndex(gears: store.state["gears"].array, events: store.state["events"].array, at: at)
        let selected = Set(includedIDs)
        let roots = includedIDs.filter { id in
            var parent = index.parents[id] ?? "", seen = Set<String>()
            while !parent.isEmpty && seen.insert(parent).inserted {
                if selected.contains(parent) { return false }
                parent = index.parents[parent] ?? ""
            }
            return true
        }
        let retiredRoots = Set(roots.filter { id in
            guard let gear = index.byID[id], gear["deletedAt"].isNull else { return false }
            return GearInventory.readStatus(state: store.state, gearID: id, at: at) == "retired"
        })
        return includedIDs.filter { id in
            var current = id, seen = Set<String>()
            while !current.isEmpty && seen.insert(current).inserted {
                if retiredRoots.contains(current) { return true }
                current = index.parents[current] ?? ""
            }
            return false
        }
    }
    private var pendingIDs: [String] {
        let blocked = Set(blockedIDs)
        return includedIDs.filter { !blocked.contains($0) }
    }
    private var input: Value { ["gearIds": .array(includedIDs.map(Value.string)), "at": .string(NativeDate.format(date, "yyyy-MM-dd"))] }
    var body: some View {
        Form {
            if preview.isNull {
                Section {
                    DatePicker("入库日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("inventory-batch-date")
                }
                if includedIDs.isEmpty || !pendingIDs.isEmpty {
                    Section("待入库") {
                        if includedIDs.isEmpty {
                            Text("暂无待入库的装备").foregroundStyle(NativeAppearance.secondaryText).accessibilityIdentifier("inventory-batch-empty")
                        } else {
                            ForEach(pendingIDs, id: \.self) { id in
                                Text(store.displayName(id)).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("inventory-batch-item-" + id)
                            }
                        }
                    }
                }
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
            if !saved && !blockedIDs.isEmpty {
                Section {
                    ForEach(blockedIDs, id: \.self) { id in
                        Text(store.displayName(id)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inventory-batch-retired-" + id)
                    }
                    Button("移除已退役装备", systemImage: "minus.circle") {
                        let removingIDs = blockedIDs
                        excludedIDs.formUnion(removingIDs); preview = .null; error = nil
                    }.accessibilityIdentifier("inventory-batch-remove-retired")
                } header: { Text("所选日期已退役的装备") }
                  footer: { Text("仅从本次入库中移除。") }
            }
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) } }
        }
        .labeledContentStyle(NativeReadableValueStyle())
        .disabled(saving || store.readOnly)
        .navigationTitle(preview.isNull ? "放入库存" : "确认入库").navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving || hasChanges)
        .alert("放弃未保存的更改？", isPresented: $discarding) {
            Button("放弃更改", role: .destructive) { dismiss() }
                .accessibilityIdentifier("inventory-batch-discard")
            Button("继续编辑", role: .cancel) {}
                .accessibilityIdentifier("inventory-batch-continue-editing")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(saved ? "完成" : preview.isNull ? "取消" : "返回", action: requestCancel)
                    .disabled(saving).accessibilityIdentifier("inventory-batch-cancel")
            }
            if !saved { ToolbarItem(placement: .confirmationAction) {
                Button(preview.isNull ? "下一步" : "放入库存", action: advanceOperation)
                    .disabled(saving || store.readOnly || includedIDs.isEmpty || !blockedIDs.isEmpty).accessibilityIdentifier("inventory-batch-save")
            } }
        }
        .task { if initialDraft == nil { initialDraft = input } }
    }
    private func requestCancel() {
        guard !saving else { return }
        if !saved && !preview.isNull { preview = .null; error = nil }
        else if hasChanges { discarding = true }
        else { dismiss() }
    }
    private func advanceOperation() {
        guard !saving, !store.readOnly else { return }
        guard includedIDs.count < 500 else {
            error = "每次最多调整 499 件装备，请减少选择后重试。"
            return
        }
        saving = true
        defer { saving = false }
        do {
            if preview.isNull { preview = try store.query("inventory-batch-preview", input) }
            else {
                var request = input; request["revision"] = preview["revision"]
                preview = try store.commit("inventory-batch", request)
                saved = true
                if preview["affectedActivities"].integer == 0 { dismiss() }
            }
            error = nil
        } catch { self.error = error.userFacingMessage; preview = .null }
    }
}
