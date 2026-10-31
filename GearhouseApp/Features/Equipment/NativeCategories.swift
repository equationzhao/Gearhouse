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
                    NativeCategorySummary(category: category, count: store.categoryGearCount(category.id))
                }.accessibilityIdentifier("category-row-" + category.id)
                    .listRowBackground(NativeAppearance.surface)
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("装备类别").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            if !store.readOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新增类别", systemImage: "plus") { adding = true }.accessibilityIdentifier("category-add")
                }
            }
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
                    NativeCategorySummary(category: category, selected: selection == category.id)
                }
                .accessibilityAddTraits(selection == category.id ? .isSelected : [])
                .accessibilityIdentifier("category-choice-" + category.id)
                .listRowBackground(NativeAppearance.surface)
                .disabled(store.readOnly)
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("类别").navigationBarTitleDisplayMode(.inline)
        .toolbar { if !store.readOnly { Button("新增类别", systemImage: "plus") { created = false; adding = true }.accessibilityIdentifier("category-add") } }
        .sheet(isPresented: $adding, onDismiss: { if created { dismiss() } }) {
            NavigationStack { NativeCategoryForm { selection = $0; created = true } }
        }
    }
}

private struct NativeCategorySummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let category: Value
    var count: Int? = nil
    var selected = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: nativeIcon(category["baseType"].text))
                .font(.system(size: 17, weight: .medium)).foregroundStyle(NativeAppearance.accent)
                .frame(width: 36, height: 36)
                .background(NativeAppearance.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(category["name"].text).font(.body).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let count, dynamicTypeSize.isAccessibilitySize { renderCount(count) }
            }
            Spacer(minLength: 8)
            if let count, !dynamicTypeSize.isAccessibilitySize { renderCount(count) }
            if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(NativeAppearance.accent).accessibilityHidden(true) }
        }.frame(minHeight: 44).padding(.vertical, 4)
    }
    private func renderCount(_ count: Int) -> some View {
        Text("\(count) 件").font(.subheadline).monospacedDigit().foregroundStyle(NativeAppearance.secondaryText)
            .fixedSize(horizontal: true, vertical: false).accessibilityLabel("\(count) 件装备")
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
    @State private var discarding = false
    @State private var baseline: Draft
    @FocusState private var editingName: Bool
    private struct Draft: Equatable {
        let name: String
        let baseType: String
        let indoor: Bool
    }
    private var hasChanges: Bool { readDraft() != baseline }
    init(existing: Value = [:], onSave: @escaping (String) -> Void = { _ in }) {
        self.existing = existing; self.onSave = onSave
        _name = State(initialValue: existing["name"].text)
        let initialType = existing["baseType"].text.isEmpty ? "Equipment" : existing["baseType"].text
        _baseType = State(initialValue: initialType)
        _indoor = State(initialValue: existing["indoorDistance"].flag)
        _baseline = State(initialValue: Draft(name: existing["name"].text.trimmingCharacters(in: .whitespacesAndNewlines), baseType: initialType, indoor: existing["indoorDistance"].flag))
    }
    var body: some View {
        Form {
            Section {
                TextField("名称", text: $name, axis: .vertical).focused($editingName).submitLabel(.done)
                    .accessibilityIdentifier("category-name")
                if existing["builtin"].flag || (!existing.id.isEmpty && store.categoryGearCount(existing.id) > 0) {
                    LabeledContent("基础类型", value: nativeType(baseType)).accessibilityIdentifier("category-base-type")
                } else {
                    Picker("基础类型", selection: $baseType) {
                        ForEach(nativeTypes, id: \.0) { Text($0.1).tag($0.0) }
                    }.accessibilityIdentifier("category-base-type")
                }
                Toggle("计入室内骑行距离", isOn: $indoor).accessibilityIdentifier("category-indoor-distance")
            }.disabled(store.readOnly).listRowBackground(NativeAppearance.surface)
            if !existing.id.isEmpty && !store.readOnly {
                if store.categoryGearCount(existing.id, includingDeleted: false) > 0 {
                    Section {
                        Button(hasChanges ? "保存并重算" : "重算") {
                            editingName = false
                            do {
                                if hasChanges { _ = try save() }
                                recalculating = true
                            } catch let failure { error = failure.userFacingMessage }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("category-recompute")
                    }.listRowBackground(NativeAppearance.surface)
                }
                if !existing["builtin"].flag {
                    Section { Button("删除类别", role: .destructive) { editingName = false; deleting = true }.accessibilityIdentifier("category-delete") }
                        .listRowBackground(NativeAppearance.surface)
                }
            }
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas).scrollDismissesKeyboard(.interactively)
        .navigationTitle(existing.id.isEmpty ? "新增类别" : "编辑类别").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: baseType) { _, value in indoor = store.category(value)["indoorDistance"].flag }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { editingName = false; if hasChanges { discarding = true } else { dismiss() } }
                    .accessibilityIdentifier("category-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    editingName = false
                    do {
                        let saved = try save()
                        onSave(saved.id); dismiss()
                    } catch let failure { error = failure.userFacingMessage }
                }.disabled(store.readOnly || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("category-save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { editingName = false }.accessibilityIdentifier("category-keyboard-done")
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .alert("放弃未保存的更改？", isPresented: $discarding) {
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss() } }) {
            NavigationStack { NativeCategoryDeletion(categoryID: existing.id) { deleted = true } }
        }
        .sheet(isPresented: $recalculating) { NavigationStack { NativeRecompute(gearID: "", categoryID: existing.id) } }
    }
    private func readDraft() -> Draft {
        Draft(name: name.trimmingCharacters(in: .whitespacesAndNewlines), baseType: baseType, indoor: indoor)
    }
    private func save() throws -> Value {
        guard !store.readOnly else { throw DomainError("请返回当前后再修改") }
        var input: Value = ["name": .string(readDraft().name), "baseType": .string(baseType), "indoorDistance": .bool(indoor)]
        if !existing.id.isEmpty { input["id"] = existing["id"] }
        let saved = try store.commit("category-save", input)
        baseline = readDraft()
        error = nil
        return saved
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
    private var canDelete: Bool {
        let category = store.category(categoryID)
        return !store.readOnly && !category.id.isEmpty && !category["builtin"].flag
            && (count == 0 || choices.contains { $0.id == replacement })
    }
    var body: some View {
        Form {
            Section {
                LabeledContent("类别", value: store.categoryName(categoryID))
                if count > 0 {
                    LabeledContent("关联装备", value: "\(count) 件")
                    if choices.isEmpty {
                        LabeledContent("装备改为", value: "暂无可选类别")
                    } else {
                        Picker("装备改为", selection: $replacement) {
                            Text("请选择类别").tag("")
                            ForEach(choices) { Text($0["name"].text).tag($0.id) }
                        }.disabled(store.readOnly).accessibilityIdentifier("category-replacement")
                    }
                }
            }.listRowBackground(NativeAppearance.surface)
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("删除类别").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("删除", role: .destructive) { confirming = true }.disabled(!canDelete).accessibilityIdentifier("category-confirm-delete") }
        }
        .confirmationDialog("删除「\(store.categoryName(categoryID))」类别？", isPresented: $confirming, titleVisibility: .visible) {
            Button("删除类别", role: .destructive) {
                guard canDelete else { return }
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
