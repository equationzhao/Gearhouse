import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

extension NativeStore {
    var categories: [Value] { state["gearCategories"].array }
    func category(_ id: String) -> Value { categories.first { $0.id == id } ?? [:] }
    func categoryName(_ id: String) -> String { category(id)["name"].text }
    func categoryName(for gear: Value) -> String {
        let name = categoryName(gear["categoryId"].text)
        return name.isEmpty ? nativeType(gear["type"].text) : name
    }
    func categoryGearCount(_ id: String, includingDeleted: Bool = true) -> Int {
        state["gears"].array.filter { $0["categoryId"].text == id && (includingDeleted || $0["deletedAt"].isNull) }.count
    }
}

struct NativeCategories: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    var body: some View {
        List {
            ForEach(store.categories) { category in
                NavigationLink { NativeCategoryForm(existing: category) } label: {
                    HStack {
                        Label(category["name"].text, systemImage: nativeIcon(category["baseType"].text))
                        Spacer()
                        Text("\(store.categoryGearCount(category.id)) 件").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("装备类别").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button("新增类别", systemImage: "plus") { adding = true } }
        }
        .sheet(isPresented: $adding) { NavigationStack { NativeCategoryForm() } }
    }
}

struct NativeCategoryPicker: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var adding = false
    @State private var created = false
    var body: some View {
        List {
            ForEach(store.categories) { category in
                Button { selection = category.id; dismiss() } label: {
                    HStack {
                        Text(category["name"].text).foregroundStyle(.primary)
                        Spacer()
                        if selection == category.id { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .navigationTitle("类别").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("新增类别", systemImage: "plus") { created = false; adding = true } }
        .sheet(isPresented: $adding, onDismiss: { if created { dismiss() } }) {
            NavigationStack { NativeCategoryForm { selection = $0; created = true } }
        }
    }
}

struct NativeCategoryForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let existing: Value
    let onSave: (String) -> Void
    @State private var name: String
    @State private var baseType: String
    @State private var indoor: Bool
    @State private var error: String?
    @State private var deleting = false
    @State private var recalculating = false
    @State private var deleted = false
    private var hasChanges: Bool {
        let saved = store.category(existing.id)
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != saved["name"].text || baseType != saved["baseType"].text || indoor != saved["indoorDistance"].flag
    }
    init(existing: Value = [:], onSave: @escaping (String) -> Void = { _ in }) {
        self.existing = existing; self.onSave = onSave
        _name = State(initialValue: existing["name"].text)
        _baseType = State(initialValue: existing["baseType"].text.isEmpty ? "Equipment" : existing["baseType"].text)
        _indoor = State(initialValue: existing["indoorDistance"].flag)
    }
    var body: some View {
        Form {
            Section {
                TextField("名称", text: $name)
                if existing["builtin"].flag || (!existing.id.isEmpty && store.categoryGearCount(existing.id) > 0) {
                    LabeledContent("基础类型", value: nativeType(baseType))
                } else {
                    Picker("基础类型", selection: $baseType) {
                        ForEach(nativeTypes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Toggle("计入室内骑行距离", isOn: $indoor)
            }
            if !existing.id.isEmpty {
                if store.categoryGearCount(existing.id, includingDeleted: false) > 0 {
                    Section {
                        Button(hasChanges ? "保存并重算" : "重算") {
                            do {
                                if hasChanges { _ = try save() }
                                recalculating = true
                            } catch let failure { error = failure.userFacingMessage }
                        }
                    }
                }
                if !existing["builtin"].flag {
                    Section { Button("删除类别", role: .destructive) { deleting = true } }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(existing.id.isEmpty ? "新增类别" : "编辑类别").navigationBarTitleDisplayMode(.inline)
        .onChange(of: baseType) { _, value in indoor = store.category(value)["indoorDistance"].flag }
        .toolbar { EditorButtons(disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            do {
                let saved = try save()
                onSave(saved.id); dismiss()
            } catch let failure { error = failure.userFacingMessage }
        } }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss() } }) {
            NavigationStack { NativeCategoryDeletion(categoryID: existing.id) { deleted = true } }
        }
        .sheet(isPresented: $recalculating) { NavigationStack { NativeRecompute(gearID: "", categoryID: existing.id) } }
    }
    private func save() throws -> Value {
        var input: Value = ["name": .string(name), "baseType": .string(baseType), "indoorDistance": .bool(indoor)]
        if !existing.id.isEmpty { input["id"] = existing["id"] }
        return try store.commit("category-save", input)
    }
}

struct NativeCategoryDeletion: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let categoryID: String
    let onDelete: () -> Void
    @State private var replacement = ""
    @State private var confirming = false
    @State private var error: String?
    private var count: Int { store.categoryGearCount(categoryID) }
    private var choices: [Value] {
        store.categories.filter { $0.id != categoryID && $0["baseType"] == store.category(categoryID)["baseType"] }
    }
    var body: some View {
        Form {
            LabeledContent("类别", value: store.categoryName(categoryID))
            if count > 0 {
                LabeledContent("关联装备", value: "\(count) 件")
                Picker("装备改为", selection: $replacement) {
                    Text("请选择类别").tag("")
                    ForEach(choices) { Text($0["name"].text).tag($0.id) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("删除类别").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("删除", role: .destructive) { confirming = true }.disabled(count > 0 && replacement.isEmpty) }
        }
        .confirmationDialog("删除「\(store.categoryName(categoryID))」类别？", isPresented: $confirming, titleVisibility: .visible) {
            Button("删除类别", role: .destructive) {
                do {
                    try store.commit("category-delete", ["id": .string(categoryID), "replacementId": .string(replacement), "confirmed": true])
                    onDelete(); dismiss()
                } catch let failure { error = failure.userFacingMessage }
            }
        } message: {
            Text(count > 0 ? "\(count) 件装备将改为「\(store.categoryName(replacement))」，已有活动的统计结果保留。" : "删除后无法恢复。")
        }
    }
}
