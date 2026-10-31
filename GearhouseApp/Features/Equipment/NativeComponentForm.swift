import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeComponentForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let parent: String
    @State private var chosen = Set<String>()
    @State private var categoryID = ""
    @State private var searchText = ""
    @State private var at = Date()
    @State private var error: String?
    @State private var initialDraft: Value?
    @State private var confirmingDiscard = false
    @FocusState private var searching: Bool
    private var candidates: [Value] {
        store.gears.filter { g in
            guard g["deletedAt"].isNull, store.status(g.id) != "retired", g.id != parent, store.parent(g.id) != parent else { return false }
            var ancestor = parent, seen = Set<String>()
            while !ancestor.isEmpty && seen.insert(ancestor).inserted { if ancestor == g.id { return false }; ancestor = store.parent(ancestor) }
            return true
        }
    }
    private var categories: [Value] {
        let available = Set(candidates.map { $0["categoryId"].text })
        return store.categories.filter { available.contains($0.id) }
    }
    private var filteredCandidates: [Value] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter {
            (categoryID.isEmpty || $0["categoryId"].text == categoryID)
                && (query.isEmpty || store.displayName($0.id).localizedStandardContains(query))
        }
    }
    private var hasChanges: Bool { initialDraft.map { $0 != buildDraft() } ?? false }
    var body: some View {
        Form {
            Section { NavigationLink("新建组件") { NativeGearForm(parent: parent) } }
            Section("已有装备") {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NativeAppearance.secondaryText).accessibilityHidden(true)
                    TextField("搜索装备", text: $searchText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($searching).submitLabel(.done).onSubmit { searching = false }
                        .accessibilityIdentifier("component-search")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(NativeAppearance.secondaryText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                            .buttonStyle(.borderless).accessibilityLabel("清除搜索")
                            .accessibilityIdentifier("component-clear-search")
                    }
                }
                Picker("类别", selection: $categoryID) {
                    Text("全部类别").tag("")
                    ForEach(categories) { Text($0["name"].text).tag($0.id) }
                }.accessibilityIdentifier("component-category")
                if !chosen.isEmpty {
                    LabeledContent("已选", value: "\(chosen.count) 件").accessibilityIdentifier("component-selection-count")
                    Button("清除选择") { chosen.removeAll() }.accessibilityIdentifier("component-clear-selection")
                }
                ForEach(filteredCandidates) { gear in
                    Button { toggleSelection(gear.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: chosen.contains(gear.id) ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large)
                                .foregroundStyle(chosen.contains(gear.id) ? Color.accentColor : NativeAppearance.secondaryText)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.displayName(gear.id))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(GearInventory.describeStatus(store.status(gear.id)) + " · " + nativeDistance(store.view["statistics"][gear.id]["distance"])).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(chosen.contains(gear.id) ? .isSelected : [])
                        .accessibilityIdentifier("component-choice-" + gear.id)
                }
                if filteredCandidates.isEmpty {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无可添加的装备" : "未找到匹配的装备")
                        .foregroundStyle(NativeAppearance.secondaryText).accessibilityIdentifier("component-empty")
                }
            }
            Section { DatePicker("装配日期", selection: $at, in: ...Date(), displayedComponents: .date) }
            if let error { Text(error).foregroundStyle(NativeAppearance.dangerText) }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("添加组件").navigationBarTitleDisplayMode(.inline)
        .task { if initialDraft == nil { initialDraft = buildDraft() } }
        .interactiveDismissDisabled(hasChanges)
        .alert("放弃未保存的更改？", isPresented: $confirmingDiscard) {
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: requestCancel) }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: saveComponents).disabled(chosen.isEmpty) }
            ToolbarItemGroup(placement: .keyboard) {
                if searching { Spacer(); Button("完成") { searching = false }.accessibilityIdentifier("component-keyboard-done") }
            }
        }
    }
    private func toggleSelection(_ id: String) {
        searching = false
        if !chosen.insert(id).inserted { chosen.remove(id) }
    }
    private func buildDraft() -> Value {
        ["ids": .array(chosen.sorted().map(Value.string)), "at": .string(NativeDate.format(at, "yyyy-MM-dd"))]
    }
    private func requestCancel() {
        searching = false
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }
    private func saveComponents() {
        searching = false
        guard chosen.count < 500 else {
            error = "每次最多调整 499 件装备，请减少选择后重试。"
            return
        }
        do {
            try store.commit("moves", ["changes": .array(chosen.sorted().map { ["gearId": .string($0), "parentId": .string(parent)] }), "at": .string(NativeDate.format(at,"yyyy-MM-dd"))]); dismiss()
        } catch let failure { error = failure.userFacingMessage }
    }
}
