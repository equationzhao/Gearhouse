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
    @State private var at = Date()
    @State private var error: String?
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
        candidates.filter { categoryID.isEmpty || $0["categoryId"].text == categoryID }
    }
    var body: some View {
        Form {
            Section { NavigationLink("新建组件") { NativeGearForm(parent: parent) } }
            Section("已有装备") {
                Picker("类别", selection: $categoryID) {
                    Text("全部类别").tag("")
                    ForEach(categories) { Text($0["name"].text).tag($0.id) }
                }.accessibilityIdentifier("component-category")
                if !chosen.isEmpty { LabeledContent("已选", value: "\(chosen.count) 件").accessibilityIdentifier("component-selection-count") }
                ForEach(filteredCandidates) { gear in
                    Button { if !chosen.insert(gear.id).inserted { chosen.remove(gear.id) } } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(store.displayName(gear.id))
                                Text(GearInventory.describeStatus(store.status(gear.id)) + " · " + nativeDistance(store.view["statistics"][gear.id]["distance"])).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); if chosen.contains(gear.id) { Image(systemName: "checkmark") }
                        }
                    }.foregroundStyle(.primary).accessibilityIdentifier("component-choice-" + gear.id)
                }
                if filteredCandidates.isEmpty { Text("暂无可添加的装备").foregroundStyle(.secondary) }
            }
            Section { DatePicker("装配日期", selection: $at, in: ...Date(), displayedComponents: .date) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("添加组件").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorButtons(disabled: chosen.isEmpty) {
            do {
                try store.commit("moves", ["changes": .array(chosen.map { ["gearId": .string($0), "parentId": .string(parent)] }), "at": .string(NativeDate.format(at,"yyyy-MM-dd"))]); dismiss()
            } catch let failure { error = failure.userFacingMessage }
        } }
    }
}
