import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeTree: View {
    @EnvironmentObject var store: NativeStore
    @AppStorage("showRetired") private var showRetired = false
    @AppStorage("showHidden") private var showHidden = false
    @State private var trash = false
    @State private var placement = "active"
    @State private var categoryID = ""
    @State private var query = ""
    @State private var collapsed = Set<String>()
    @State private var expandedStockGroups = Set<String>()
    @State private var selection = Set<String>()
    @State private var selecting = false
    @State private var pending: [String: String] = [:]
    @State private var undo: [[String: String]] = []
    @State private var review = false
    @State private var dateSheet = false
    @State private var date = Date()
    @State private var editor: NativeEditorRoute?
    @State private var drag = NativeTreeDragState()
    @State private var rows: [GearTreeIndex.Row] = []
    @State private var scrollTarget: String?
    @State private var scrollingUp = false
    @State private var scrolling: Task<Void, Never>?
    private func refreshRows() {
        #if DEBUG
        drag.treeBuilds += 1
        #endif
        rows = store.treeIndex.rows(pending: pending, collapsed: collapsed, query: query,
                                    showRetired: showRetired, showHidden: showHidden, trash: trash, placement: trash ? nil : placement, statuses: store.view["gearStatuses"], categoryID: categoryID)
    }
    private func stage(_ payload: GearTreeDrag, onto target: String) {
        guard !store.readOnly && !trash else { return }
        let parents = Dictionary(uniqueKeysWithValues: store.gears.filter { $0["deletedAt"].isNull }.map { ($0.id, store.parent($0.id)) })
        do {
            let next = try payload.staging(onto: target, originalParents: parents, pending: pending)
            guard next != pending else { return }
            undo.append(pending); pending = next
            collapsed.remove(target)
        } catch { store.error = error.userFacingMessage }
    }
    private func target(at point: CGPoint) -> String? {
        drag.frames.first { $0.value.contains(point) }?.key
    }
    private func dragChanged(_ ids: [String], _ point: CGPoint) {
        guard !store.readOnly && !trash else { return }
        #if DEBUG
        if drag.payload == nil { drag.startBuilds = drag.treeBuilds; drag.inputEvents = 0 }
        drag.inputEvents += 1
        #endif
        if drag.payload == nil {
            drag.payload = try? GearTreeDrag(gearIDs: ids)
            drag.label = ids.count > 1 ? "\(ids.count) 件装备" : store.name(ids[0])
        }
        drag.point = point
        let target = target(at: point)
        if drag.target != target { drag.target = target }
        if scrolling == nil {
            scrolling = Task { @MainActor in
                while !Task.isCancelled && drag.payload != nil {
                    if let point = drag.point, drag.viewport.height > 0 {
                        let up = point.y < drag.viewport.minY + 65, down = point.y > drag.viewport.maxY - 65
                        if up || down {
                            let visible = drag.frames.filter { !$0.key.isEmpty && $0.value.maxY > drag.viewport.minY && $0.value.minY < drag.viewport.maxY }.sorted { $0.value.minY < $1.value.minY }
                            let outline = rows
                            if let edge = up ? visible.first : visible.last, let index = outline.firstIndex(where: { $0.id == edge.key }) {
                                let next = up ? max(0, index - 1) : min(outline.count - 1, index + 1)
                                scrollingUp = up; scrollTarget = outline[next].id
                            }
                        }
                    }
                    do { try await Task.sleep(for: .milliseconds(180)) } catch { break }
                }
            }
        }
    }
    private func dragEnded(_ ids: [String], _ point: CGPoint) {
        #if DEBUG
        store.recordDragPerformance(updates: drag.inputEvents, treeBuilds: drag.treeBuilds - drag.startBuilds)
        #endif

        defer { scrolling?.cancel(); scrolling = nil; drag.payload = nil; drag.point = nil; drag.target = nil; scrollTarget = nil }
        guard let payload = drag.payload, let target = target(at: point) else { return }
        stage(payload, onto: target)
    }
    private func gearLabel(_ row: Value) -> some View {
        HStack {
            Image(systemName: nativeIcon(row["type"].text)).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(store.displayName(row.id))
                if pending[row.id] == nil { Text(nativeDistance(store.view["statistics"][row.id]["distance"]) + (store.conditionName(row).isEmpty ? "" : " · " + store.conditionName(row))).font(.caption).foregroundStyle(.secondary) }
                else { Text("未保存").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
        }.contentShape(Rectangle())
    }
    var body: some View {
        ScrollViewReader { proxy in
            treeList.onChange(of: scrollTarget) { _, target in
                if let target { withAnimation(.linear(duration: 0.15)) { proxy.scrollTo(target, anchor: scrollingUp ? .top : .bottom) } }
            }
        }
        .onAppear { refreshRows() }
        .onChange(of: store.viewGeneration) { _, _ in refreshRows() }
        .onChange(of: pending) { _, _ in refreshRows() }
        .onChange(of: collapsed) { _, _ in refreshRows() }
        .onChange(of: query) { _, _ in refreshRows() }
        .onChange(of: trash) { _, _ in refreshRows() }
        .onChange(of: placement) { _, _ in selection = []; refreshRows() }
        .onChange(of: categoryID) { _, _ in refreshRows() }
        .onChange(of: showRetired) { _, _ in refreshRows() }
        .onChange(of: showHidden) { _, _ in refreshRows() }
        .onDisappear { scrolling?.cancel(); scrolling = nil; drag.payload = nil; drag.point = nil; drag.target = nil }
    }
    private struct InventoryGroup: Identifiable {
        let id: String
        let title: String
        var rows: [GearTreeIndex.Row]
    }
    private var inventoryGroups: [InventoryGroup] {
        var groups: [String: InventoryGroup] = [:]
        var category = ""
        for entry in rows {
            if entry.depth == 0 { category = entry.gear["categoryId"].text }
            if groups[category] == nil { groups[category] = InventoryGroup(id: category, title: store.categoryName(category), rows: []) }
            groups[category]?.rows.append(entry)
        }
        return groups.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private func renderGearRow(_ entry: GearTreeIndex.Row) -> some View {
        let selectedIDs = selection.sorted()
        let row = entry.gear
        let level = entry.depth
        return HStack(spacing: 8) {
            if entry.hasChildren && !trash {
                Button { if !collapsed.insert(row.id).inserted { collapsed.remove(row.id) } } label: { Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down").frame(width: 20, height: 36) }.buttonStyle(.borderless)
            } else { Color.clear.frame(width: 20, height: 1) }
            if selecting {
                Button { if !selection.insert(row.id).inserted { selection.remove(row.id) } } label: { Image(systemName: selection.contains(row.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.borderless)
            }
            if selecting {
                Button { if !selection.insert(row.id).inserted { selection.remove(row.id) } } label: { gearLabel(row) }.buttonStyle(.plain)
            } else {
                NavigationLink { NativeGearDetail(id: row.id) } label: { gearLabel(row) }
                    .buttonStyle(.plain).disabled(!pending.isEmpty)
            }
            if !trash && !store.readOnly {
                NativeGearDragHandle(ids: selection.contains(row.id) ? selectedIDs : [row.id], name: row["name"].text, changed: dragChanged, ended: dragEnded)
                    .accessibilityIdentifier("gear-drag-" + row.id)
            }
        }
        .contextMenu {
            if !trash && !store.readOnly && pending.isEmpty {
                NativeInventoryActions(gearID: row.id) { editor = .init(kind: "inventory", item: ["kind": .string($0)], parent: row.id) }
            }
        }
        .padding(.leading, CGFloat(min(level, 7)) * 18)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .gearDropFrame(row.id)
        .id(row.id)
        .listRowBackground(drag.target == row.id ? Color.accentColor.opacity(0.14) : nil)
    }
    @ViewBuilder private func renderStockRows(_ entries: [GearTreeIndex.Row]) -> some View {
        if !pending.isEmpty { ForEach(entries) { renderGearRow($0) } }
        else {
            ForEach(GearInventory.groupStockRows(entries, parents: store.treeIndex.parents)) { group in
                if group.isGrouped {
                    Button {
                        if !expandedStockGroups.insert(group.id).inserted { expandedStockGroups.remove(group.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: expandedStockGroups.contains(group.id) || selecting ? "chevron.down" : "chevron.right").frame(width: 20)
                            Image(systemName: nativeIcon(group.rows[0].gear["type"].text)).foregroundStyle(.secondary)
                            Text(group.name)
                            Spacer()
                            Text("×\(group.rows.count)").foregroundStyle(.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("stock-group-" + group.name)
                    if expandedStockGroups.contains(group.id) || selecting {
                        ForEach(group.rows) { renderGearRow($0).padding(.leading, 18) }
                    }
                } else { ForEach(group.rows) { renderGearRow($0) } }
            }
        }
    }
    private var treeList: some View {
        return List {
            if let day = store.snapshotDate {
                Section { Button("返回当前 · \(day)") { store.snapshotDate = nil } }
            }
            if !trash {
                Section {
                    Picker("装备位置", selection: $placement) { Text("使用中").tag("active"); Text("库存").tag("stock") }
                        .pickerStyle(.segmented).disabled(!pending.isEmpty).accessibilityIdentifier("gear-placement")
                }
            }
            Section {
                Label(trash ? "回收站" : placement == "stock" ? "库存" : "顶层装备", systemImage: trash ? "trash" : "shippingbox")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .gearDropFrame("")
                    .listRowBackground(drag.target == "" ? Color.accentColor.opacity(0.14) : nil)
                if placement != "stock" || trash { ForEach(rows) { renderGearRow($0) } }
                if rows.isEmpty { Text(query.isEmpty ? "暂无装备" : "没有匹配的装备").foregroundStyle(.secondary) }
            }
            if placement == "stock" && !trash {
                ForEach(inventoryGroups) { group in
                    Section(group.title) { renderStockRows(group.rows) }
                }
            }
        }
        .background(GeometryReader { geometry in Color.clear.preference(key: NativeGearFrames.self, value: ["__viewport": geometry.frame(in: .global)]) })
        .onPreferenceChange(NativeGearFrames.self) { frames in
            drag.frames = frames.filter { $0.key != "__viewport" }
            drag.viewport = frames["__viewport"] ?? .zero
            if let point = drag.point { drag.target = target(at: point) }
        }
        .overlay(alignment: .topLeading) { NativeTreeDragPreview(drag: drag) }
        .navigationTitle(trash ? "回收站" : store.readOnly ? "装备快照" : "装备")
        .searchable(text: $query, prompt: "查找装备")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if !store.readOnly && placement == "active" && !selection.isEmpty {
                        Button("放入库存", systemImage: "shippingbox") { editor = .init(kind: "inventory-batch", item: ["gearIds": .array(selection.sorted().map(Value.string))]) }
                    }
                    Toggle("显示已退役", isOn: $showRetired)
                    Toggle("显示已隐藏", isOn: $showHidden)
                    Picker("类别", selection: $categoryID) {
                        Text("全部类别").tag("")
                        ForEach(store.state["gearCategories"].array) { row in Text(row["name"].text).tag(row.id) }
                    }
                    Button(trash ? "返回装备" : "回收站", systemImage: "trash") { trash.toggle(); selection.removeAll() }
                    if !store.readOnly { Button("装备类别", systemImage: "square.grid.2x2") { editor = .init(kind: "categories") } }
                    Button("历史快照", systemImage: "calendar") { dateSheet = true }
                    if store.readOnly { Button("返回当前") { store.snapshotDate = nil } }
                } label: { Image(systemName: "line.3.horizontal.decrease") }.disabled(!pending.isEmpty)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !trash && !store.readOnly {
                    Button { selecting.toggle(); if !selecting { selection.removeAll() } } label: { Image(systemName: "checkmark.circle") }.accessibilityLabel("多选装备").accessibilityIdentifier("gear-multiselect")
                    Button { editor = .init(kind: placement == "stock" ? "stock-new" : "gear") } label: { Image(systemName: "plus") }.disabled(!pending.isEmpty).accessibilityIdentifier("gear-add")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !pending.isEmpty || !undo.isEmpty {
                HStack {
                    Text("\(pending.count) 项修改").font(.subheadline)
                    Spacer()
                    Button("撤销") { if let last = undo.popLast() { pending = last } }
                    Button("取消") { pending = [:]; undo = [] }
                    Button("保存") { review = true }.accessibilityIdentifier("gear-moves-review").buttonStyle(.borderedProminent).disabled(pending.isEmpty)
                }.padding().background(.regularMaterial)
            }
        }
        .sheet(item: $editor) { NativeEditor(route: $0) }
        .sheet(isPresented: $review) {
            NativeMoveReview(changes: pending.map { ["gearId": .string($0.key), "parentId": .optional($0.value), "fromParentId": .optional(store.parent($0.key))] }) { pending = [:]; undo = []; selection = [] }
        }
        .sheet(isPresented: $dateSheet) {
            NavigationStack {
                Form { DatePicker("快照日期", selection: $date, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical) }
                    .navigationTitle("历史快照").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { dateSheet = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("查看") { store.snapshotDate = NativeDate.format(date, "yyyy-MM-dd"); dateSheet = false } }
                    }
            }.presentationDetents([.large])
        }
    }
}
