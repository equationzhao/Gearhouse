import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeTree: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var destination: MoveDestination?
    @State private var dateSheet = false
    @State private var date = Date()
    @State private var editor: NativeEditorRoute?
    @State private var drag = NativeTreeDragState()
    @State private var rows: [GearTreeIndex.Row] = []
    @State private var guideContinuations: [String: Set<Int>] = [:]
    @State private var scrollTarget: String?
    @State private var scrollingUp = false
    @State private var scrolling: Task<Void, Never>?
    private struct MoveDestination: Identifiable {
        let id = UUID()
        let gearIDs: [String]
    }
    private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasFilters: Bool { !categoryID.isEmpty || (!trash && (showHidden || (showRetired && placement == "active"))) }
    private var visibleIDs: Set<String> { Set(rows.map(\.id)) }
    private var hasSelectedVisibleRows: Bool { !visibleIDs.isEmpty && visibleIDs.isSubset(of: selection) }
    private func refreshRows() {
        #if DEBUG
        drag.treeBuilds += 1
        #endif
        rows = store.treeIndex.rows(pending: pending, collapsed: collapsed, query: searchQuery,
                                    showRetired: showRetired, showHidden: showHidden, trash: trash, placement: trash ? nil : placement, statuses: store.view["gearStatuses"], categoryID: categoryID)
        var nextDepths: [Int: Int] = [:]
        var continuations: [String: Set<Int>] = [:]
        for entry in rows.reversed() {
            continuations[entry.id] = Set((0..<min(entry.depth, 6)).filter { nextDepths[$0] == $0 + 1 })
            for level in 0..<6 where entry.depth <= level + 1 { nextDepths[level] = entry.depth }
        }
        guideContinuations = continuations
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
    private func chooseDestination(for ids: [String]) {
        guard destination == nil, !ids.isEmpty, !store.readOnly && !trash else { return }
        guard ids.count < 500 else {
            store.error = "每次最多调整 499 件装备，请减少选择后重试。"
            return
        }
        destination = MoveDestination(gearIDs: ids)
    }
    private func beginBatchStorage() {
        guard !store.readOnly, !selection.isEmpty else { return }
        guard selection.count < 500 else {
            store.error = "每次最多调整 499 件装备，请减少选择后重试。"
            return
        }
        editor = .init(kind: "inventory-batch", item: ["gearIds": .array(selection.sorted().map(Value.string))])
    }
    private func target(at point: CGPoint) -> String? {
        drag.frames.first { $0.value.contains(point) }?.key
    }
    private func dragChanged(_ ids: [String], _ point: CGPoint) {
        guard scenePhase == .active && !store.readOnly && !trash else { return }
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

        defer { cancelDrag() }
        guard scenePhase == .active && !store.readOnly && !trash else { return }
        // GestureState can reset before the final onEnded callback.
        guard let payload = drag.payload ?? (try? GearTreeDrag(gearIDs: ids)), let target = target(at: point) else { return }
        stage(payload, onto: target)
    }
    private func cancelDrag() {
        scrolling?.cancel(); scrolling = nil
        drag.payload = nil; drag.point = nil; drag.target = nil; scrollTarget = nil
    }
    @ViewBuilder private func gearLabel(_ entry: GearTreeIndex.Row) -> some View {
        let row = entry.gear
        if entry.depth == 0 && row["type"].text == "Bike" && placement == "active" && !trash {
            NativeEquipmentSummary(gear: row, pending: pending[row.id] != nil, isEditing: selecting)
        } else if dynamicTypeSize >= .accessibility4 && !selecting {
            VStack(alignment: .leading, spacing: 8) {
                if entry.depth == 0 { NativeGearThumbnail(gearID: row.id, size: 40) }
                renderRowIdentity(entry)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        } else {
            HStack(spacing: 10) {
                if entry.depth == 0 { NativeGearThumbnail(gearID: row.id, size: 40) }
                renderRowIdentity(entry)
                Spacer(minLength: 6)
                if !dynamicTypeSize.isAccessibilitySize { renderRowDistance(row) }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
    }
    private func renderRowIdentity(_ entry: GearTreeIndex.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.displayName(entry.id))
                .font(.subheadline.weight(entry.depth == 0 ? .semibold : .regular))
                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize { renderRowDistance(entry.gear) }
        }
    }
    private func renderRowDistance(_ gear: Value) -> some View {
        Text(pending[gear.id] == nil ? nativeDistance(store.view["statistics"][gear.id]["distance"]) : "未保存")
            .font(.caption).monospacedDigit()
            .foregroundStyle(pending[gear.id] == nil ? NativeAppearance.secondaryText : NativeAppearance.warningText)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    private func clearFilters() {
        query = ""; categoryID = ""; showRetired = false; showHidden = false
    }
    private func toggleVisibleSelection() {
        if hasSelectedVisibleRows { selection.subtract(visibleIDs) }
        else { selection.formUnion(visibleIDs) }
    }
    private func reconcileSelection() {
        let available = Set(store.gears.filter { gear in
            guard gear["deletedAt"].isNull else { return false }
            let status = store.status(gear.id)
            return status == placement || (placement == "active" && showRetired && status == "retired")
        }.map(\.id))
        selection.formIntersection(available)
    }
    var body: some View {
        ScrollViewReader { proxy in
            treeList.onChange(of: scrollTarget) { _, target in
                if let target { withAnimation(.linear(duration: 0.15)) { proxy.scrollTo(target, anchor: scrollingUp ? .top : .bottom) } }
            }
        }
        .onAppear { refreshRows() }
        .onChange(of: store.viewGeneration) { _, _ in reconcileSelection(); refreshRows() }
        .onChange(of: pending) { _, _ in refreshRows() }
        .onChange(of: collapsed) { _, _ in refreshRows() }
        .onChange(of: query) { _, _ in refreshRows() }
        .onChange(of: trash) { _, _ in selecting = false; selection = []; refreshRows() }
        .onChange(of: placement) { _, _ in selecting = false; selection = []; refreshRows() }
        .onChange(of: categoryID) { _, _ in refreshRows() }
        .onChange(of: showRetired) { _, _ in refreshRows() }
        .onChange(of: showHidden) { _, _ in refreshRows() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelDrag() } }
        .onDisappear { cancelDrag() }
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
    private struct EquipmentGroup: Identifiable {
        let id: String
        var rows: [GearTreeIndex.Row]
    }
    private var equipmentGroups: [EquipmentGroup] {
        var groups: [EquipmentGroup] = []
        for entry in rows {
            if entry.depth == 0 || groups.isEmpty { groups.append(EquipmentGroup(id: entry.id, rows: [entry])) }
            else { groups[groups.count - 1].rows.append(entry) }
        }
        return groups
    }
    @ViewBuilder private func renderExpandButton(_ entry: GearTreeIndex.Row) -> some View {
        if entry.hasChildren && !trash && searchQuery.isEmpty && categoryID.isEmpty {
            Button { if !collapsed.insert(entry.id).inserted { collapsed.remove(entry.id) } } label: {
                Image(systemName: collapsed.contains(entry.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(NativeAppearance.secondaryText)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel((collapsed.contains(entry.id) ? "展开" : "收起") + store.displayName(entry.id))
                .accessibilityIdentifier("gear-toggle-" + entry.id)
        } else { Color.clear.frame(width: 44, height: 1) }
    }
    private func renderSelectButton(_ id: String) -> some View {
        Button { if !selection.insert(id).inserted { selection.remove(id) } } label: {
            Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle")
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selection.contains(id) ? NativeAppearance.accent : NativeAppearance.secondaryText)
            .accessibilityLabel((selection.contains(id) ? "取消选择" : "选择") + store.displayName(id))
            .accessibilityIdentifier("gear-select-" + id)
    }
    @ViewBuilder private func renderDragHandle(_ id: String, selectedIDs: [String]) -> some View {
        if !trash && !store.readOnly {
            NativeGearDragHandle(ids: selection.contains(id) ? selectedIDs : [id], name: store.displayName(id), changed: dragChanged, ended: dragEnded, cancelled: cancelDrag) {
                chooseDestination(for: selection.contains(id) ? selectedIDs : [id])
            }.accessibilityIdentifier("gear-drag-" + id)
        }
    }
    private func renderSelectableLabel(_ entry: GearTreeIndex.Row) -> some View {
        Button { if !selection.insert(entry.id).inserted { selection.remove(entry.id) } } label: { gearLabel(entry) }
            .buttonStyle(.plain).accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
    }
    private func renderGearRow(_ entry: GearTreeIndex.Row, selectedIDs: [String]) -> some View {
        let row = entry.gear
        let level = entry.depth
        return Group {
            if !selecting && dynamicTypeSize >= .accessibility4 {
                VStack(alignment: .leading, spacing: 4) {
                    if entry.hasChildren && !trash && searchQuery.isEmpty && categoryID.isEmpty {
                        HStack { renderExpandButton(entry); Spacer(minLength: 0) }
                    }
                    NavigationLink { NativeGearDetail(id: row.id) } label: { gearLabel(entry) }
                        .buttonStyle(.plain).disabled(!pending.isEmpty)
                }
            } else if selecting && dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        renderExpandButton(entry)
                        renderSelectButton(row.id)
                        Spacer(minLength: 0)
                        renderDragHandle(row.id, selectedIDs: selectedIDs)
                    }
                    renderSelectableLabel(entry).padding(.horizontal, 6)
                }
            } else {
                HStack(spacing: 6) {
                    renderExpandButton(entry)
                    if selecting {
                        renderSelectButton(row.id)
                        renderSelectableLabel(entry)
                        renderDragHandle(row.id, selectedIDs: selectedIDs)
                    } else {
                        NavigationLink { NativeGearDetail(id: row.id) } label: {
                            HStack(spacing: 8) {
                                gearLabel(entry)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(NativeAppearance.secondaryText)
                            }
                        }.buttonStyle(.plain).disabled(!pending.isEmpty)
                    }
                }
            }
        }
        .contextMenu {
            if !trash && !store.readOnly && pending.isEmpty {
                NativeInventoryActions(gearID: row.id) { editor = .init(kind: "inventory", item: ["kind": .string($0)], parent: row.id) }
            }
        }
        .padding(.leading, CGFloat(min(level, 6)) * 18)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, level == 0 ? 6 : 2)
        .background(alignment: .leading) {
            if level > 0 { NativeHierarchyGuide(depth: level, continuingLevels: guideContinuations[row.id] ?? []) }
        }
        .contentShape(Rectangle())
        .gearDropFrame(row.id)
        .id(row.id)
        .padding(.horizontal, 12)
        .background(drag.target == row.id ? NativeAppearance.accent.opacity(0.12) : Color.clear)
    }
    @ViewBuilder private func renderStockRows(_ entries: [GearTreeIndex.Row], selectedIDs: [String]) -> some View {
        if !pending.isEmpty { ForEach(entries) { renderGearRow($0, selectedIDs: selectedIDs) } }
        else {
            ForEach(GearInventory.groupStockRows(entries, parents: store.treeIndex.parents)) { group in
                if group.isGrouped {
                    Button {
                        if !expandedStockGroups.insert(group.id).inserted { expandedStockGroups.remove(group.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Text(group.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text("×\(group.rows.count)").font(.subheadline).monospacedDigit().foregroundStyle(NativeAppearance.secondaryText)
                            Image(systemName: expandedStockGroups.contains(group.id) || selecting ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(NativeAppearance.secondaryText).frame(width: 24)
                        }.frame(minHeight: 52).padding(.horizontal, 16).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("stock-group-" + group.name)
                    if expandedStockGroups.contains(group.id) || selecting {
                        ForEach(group.rows) { renderGearRow($0, selectedIDs: selectedIDs).padding(.leading, 18) }
                    }
                } else { ForEach(group.rows) { renderGearRow($0, selectedIDs: selectedIDs) } }
            }
        }
    }
    private var treeList: some View {
        let selectedIDs = selection.sorted()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let day = store.snapshotDate {
                    Button("返回当前 · \(day)") { store.snapshotDate = nil }.font(.subheadline)
                }
                if !trash {
                    Picker("装备位置", selection: $placement) { Text("使用中").tag("active"); Text("库存").tag("stock") }
                        .pickerStyle(.segmented).disabled(!pending.isEmpty).accessibilityIdentifier("gear-placement")
                }
                if hasFilters { renderActiveFilters() }
                if selecting && !trash && !store.readOnly {
                    Label(placement == "stock" ? "库存" : "顶层装备", systemImage: "shippingbox")
                        .font(.subheadline.weight(.medium)).foregroundStyle(NativeAppearance.accent)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 16)
                        .background(drag.target == "" ? NativeAppearance.accent.opacity(0.12) : NativeAppearance.surface, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle()).gearDropFrame("")
                }
                if placement != "stock" || trash {
                    ForEach(equipmentGroups) { group in
                        VStack(spacing: 0) {
                            ForEach(group.rows) { entry in
                                if entry.depth > 0 {
                                    Divider().padding(.leading, 42 + CGFloat(min(entry.depth, 6)) * 18).padding(.trailing, 16)
                                }
                                renderGearRow(entry, selectedIDs: selectedIDs)
                            }
                        }
                        .background(NativeAppearance.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                if rows.isEmpty {
                    renderEmptyState()
                }
                if placement == "stock" && !trash {
                    ForEach(inventoryGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(NativeAppearance.secondaryText).padding(.horizontal, 4)
                            VStack(spacing: 0) { renderStockRows(group.rows, selectedIDs: selectedIDs) }
                                .background(NativeAppearance.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .background(NativeAppearance.canvas)
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
                        Button("放入库存", systemImage: "shippingbox", action: beginBatchStorage)
                    }
                    if !trash {
                        if placement == "active" { Toggle("显示已退役", isOn: $showRetired) }
                        Toggle("显示已隐藏", isOn: $showHidden)
                    }
                    Picker("类别", selection: $categoryID) {
                        Text("全部类别").tag("")
                        ForEach(store.state["gearCategories"].array) { row in Text(row["name"].text).tag(row.id) }
                    }
                    Button(trash ? "返回装备" : "回收站", systemImage: "trash") { trash.toggle(); selection.removeAll() }
                    if !store.readOnly { Button("装备类别", systemImage: "square.grid.2x2") { editor = .init(kind: "categories") } }
                    Button("历史快照", systemImage: "calendar") { dateSheet = true }
                    if store.readOnly { Button("返回当前") { store.snapshotDate = nil } }
                } label: {
                    Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }.disabled(!pending.isEmpty).accessibilityLabel("筛选与更多操作").accessibilityIdentifier("gear-filters")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !trash && !store.readOnly {
                    if !selecting {
                        NavigationLink { NativeReminderOverview() } label: { Image(systemName: "bell") }
                            .disabled(!pending.isEmpty).accessibilityLabel("提醒").accessibilityIdentifier("gear-reminders")
                    }
                    Button(selecting ? "完成" : "编辑") {
                        if selecting && !pending.isEmpty { review = true }
                        else { selecting.toggle(); selection.removeAll() }
                    }.accessibilityIdentifier("gear-multiselect")
                    Button { editor = .init(kind: placement == "stock" ? "stock-new" : "gear") } label: { Image(systemName: "plus") }.disabled(!pending.isEmpty).accessibilityLabel(placement == "stock" ? "添加库存" : "添加装备").accessibilityIdentifier("gear-add")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !pending.isEmpty || !undo.isEmpty {
                renderMoveActions()
                    .padding(16).modifier(NativeActionSurface()).padding(.horizontal, 16).padding(.bottom, 8)
            } else if selecting && !trash && !store.readOnly {
                renderSelectionActions()
                    .padding(16).modifier(NativeActionSurface()).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .sheet(item: $editor) { NativeEditor(route: $0) }
        .sheet(isPresented: $review) {
            NativeMoveReview(changes: pending.map { ["gearId": .string($0.key), "parentId": .optional($0.value), "fromParentId": .optional(store.parent($0.key))] }) { pending = [:]; undo = []; selection = []; selecting = false }
        }
        .sheet(item: $destination) { route in
            NativeMoveDestinationPicker(gearIDs: route.gearIDs, pending: pending) { target in
                if let payload = try? GearTreeDrag(gearIDs: route.gearIDs) { stage(payload, onto: target) }
            }
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
    private func renderActiveFilters() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !categoryID.isEmpty {
                    renderFilterChip(store.categoryName(categoryID), identifier: "gear-filter-category") { categoryID = "" }
                }
                if !trash {
                    if showRetired && placement == "active" { renderFilterChip("含已退役", identifier: "gear-filter-retired") { showRetired = false } }
                    if showHidden { renderFilterChip("含已隐藏", identifier: "gear-filter-hidden") { showHidden = false } }
                }
            }
        }.disabled(!pending.isEmpty)
    }
    private func renderFilterChip(_ title: String, identifier: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.medium))
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .foregroundStyle(NativeAppearance.accent)
            .background(NativeAppearance.accent.opacity(0.09), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel("清除筛选：" + title).accessibilityIdentifier(identifier)
    }
    private func renderEmptyState() -> some View {
        let filtered = !searchQuery.isEmpty || !categoryID.isEmpty
        return VStack(spacing: 16) {
            Image(systemName: filtered ? "magnifyingglass" : trash ? "trash" : placement == "stock" ? "shippingbox" : "bicycle")
                .font(.system(size: 30, weight: .light)).foregroundStyle(NativeAppearance.secondaryText)
                .frame(width: 72, height: 72)
                .background(NativeAppearance.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text(filtered ? "没有匹配的装备" : trash ? "回收站为空" : placement == "stock" ? "暂无库存" : "暂无使用中的装备")
                .font(.headline).multilineTextAlignment(.center)
            if filtered {
                Button("清除筛选", action: clearFilters).buttonStyle(.bordered)
                    .accessibilityIdentifier("gear-clear-filters")
            } else if !trash && !store.readOnly {
                Button {
                    editor = .init(kind: placement == "stock" ? "stock-new" : "gear")
                } label: {
                    Label(placement == "stock" ? "添加库存" : "添加装备", systemImage: "plus")
                        .foregroundStyle(NativeAppearance.prominentText)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("gear-empty-add")
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 44)
    }
    @ViewBuilder private func renderSelectionActions() -> some View {
        if dynamicTypeSize >= .accessibility4 && !selection.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    renderSelectionCount()
                    renderSelectionMenu()
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) {
                    renderSelectionCount()
                    renderSelectionMenu()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    renderSelectionCount()
                    Spacer(minLength: 0)
                    if !selection.isEmpty {
                        Button { selection.removeAll() } label: { Text("清除选择").frame(minHeight: 44) }.font(.subheadline)
                            .accessibilityIdentifier("gear-clear-selection")
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { renderSelectionButtons() }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 12) { renderSelectionButtons() }
                }
            }
        }
    }
    private func renderSelectionCount() -> some View {
        Text("已选 \(selection.count) 件").font(.subheadline.weight(.semibold)).monospacedDigit()
            .accessibilityIdentifier("gear-selection-count")
    }
    private func renderSelectionMenu() -> some View {
        Menu {
            renderSelectionButtons()
            Button("清除选择") { selection.removeAll() }.accessibilityIdentifier("gear-clear-selection")
        } label: {
            Text("操作").font(.subheadline).frame(minHeight: 44)
        }.accessibilityLabel("所选装备操作").accessibilityIdentifier("gear-selection-actions")
    }
    @ViewBuilder private func renderSelectionButtons() -> some View {
        Button(action: toggleVisibleSelection) {
            Text(hasSelectedVisibleRows ? "取消当前选择" : "全选当前").frame(minHeight: 44)
        }
            .font(.subheadline).disabled(rows.isEmpty).accessibilityIdentifier("gear-select-visible")
        if !selection.isEmpty {
            Button { chooseDestination(for: selection.sorted()) } label: {
                Label("调整所属装备", systemImage: "arrow.turn.down.right").frame(minHeight: 44)
            }
                .font(.subheadline).accessibilityIdentifier("gear-select-destination")
        }
        if placement == "active" && !selection.isEmpty {
            Button(action: beginBatchStorage) {
                Label("放入库存", systemImage: "shippingbox").foregroundStyle(NativeAppearance.prominentText).frame(minHeight: 44)
            }
                .font(.subheadline).buttonStyle(.borderedProminent).accessibilityIdentifier("gear-selection-store")
        }
    }
    @ViewBuilder private func renderMoveActions() -> some View {
        if dynamicTypeSize >= .accessibility4 {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    renderMoveCount()
                    renderMoveMenu()
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) {
                    renderMoveCount()
                    renderMoveMenu()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                renderMoveCount()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { renderMoveButtons() }
                    VStack(alignment: .leading, spacing: 14) { renderMoveButtons() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func renderMoveCount() -> some View {
        Text("\(pending.count) 项修改").font(.subheadline.weight(.semibold)).monospacedDigit()
    }
    private func renderMoveMenu() -> some View {
        Menu { renderMoveButtons() } label: {
            Text("修改操作").font(.subheadline).frame(minHeight: 44)
        }.accessibilityLabel("修改操作").accessibilityIdentifier("gear-move-actions")
    }
    @ViewBuilder private func renderMoveButtons() -> some View {
        if !selection.isEmpty {
            Button("调整所属装备") { chooseDestination(for: selection.sorted()) }
                .accessibilityIdentifier("gear-select-destination")
        }
        Button("撤销") { if let last = undo.popLast() { pending = last } }.disabled(undo.isEmpty)
        Button("取消修改") { pending = [:]; undo = [] }
        Button { review = true } label: {
            Text("保存").foregroundStyle(pending.isEmpty ? NativeAppearance.secondaryText : NativeAppearance.prominentText)
        }.accessibilityIdentifier("gear-moves-review").buttonStyle(.borderedProminent).disabled(pending.isEmpty)
    }
}

private struct NativeMoveDestinationPicker: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearIDs: [String]
    let pending: [String: String]
    let select: (String) -> Void
    @State private var search = ""
    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var parents: [String: String] {
        Dictionary(uniqueKeysWithValues: store.gears.filter { $0["deletedAt"].isNull }.map { ($0.id, store.parent($0.id)) })
    }
    private func canSelect(_ id: String, payload: GearTreeDrag, parents: [String: String]) -> Bool {
        guard let next = try? payload.staging(onto: id, originalParents: parents, pending: pending) else { return false }
        return next != pending
    }
    var body: some View {
        let originalParents = parents
        let payload = try? GearTreeDrag(gearIDs: gearIDs)
        let candidates = store.gears.filter { gear in
            guard !gear.id.isEmpty, gear["deletedAt"].isNull, let payload,
                  canSelect(gear.id, payload: payload, parents: originalParents) else { return false }
            return searchTerm.isEmpty || store.displayName(gear.id).localizedStandardContains(searchTerm)
        }.sorted { store.displayName($0.id).localizedStandardCompare(store.displayName($1.id)) == .orderedAscending }
        return NavigationStack {
            List {
                if let payload, searchTerm.isEmpty, canSelect("", payload: payload, parents: originalParents) {
                    Section {
                        Button("设为顶层装备", systemImage: "square.stack.3d.up") { select(""); dismiss() }
                            .accessibilityIdentifier("gear-destination-root")
                    }.listRowBackground(NativeAppearance.surface)
                }
                Section {
                    ForEach(candidates) { gear in
                        Button { select(gear.id); dismiss() } label: {
                            HStack(spacing: 12) {
                                NativeGearThumbnail(gearID: gear.id)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.displayName(gear.id)).foregroundStyle(.primary)
                                    Text(store.categoryName(for: gear)).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                                }.fixedSize(horizontal: false, vertical: true)
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("gear-destination-" + gear.id)
                    }
                    if candidates.isEmpty && !searchTerm.isEmpty {
                        ContentUnavailableView {
                            Label("没有匹配的装备", systemImage: "magnifyingglass")
                        } actions: { Button("清除搜索") { search = "" } }
                            .listRowBackground(Color.clear)
                    } else if candidates.isEmpty, payload.map({ !canSelect("", payload: $0, parents: originalParents) }) ?? true {
                        ContentUnavailableView("没有可选的所属装备", systemImage: "square.stack.3d.up")
                            .listRowBackground(Color.clear)
                    }
                }.listRowBackground(NativeAppearance.surface)
            }
            .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
            .navigationTitle("选择所属装备").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "查找所属装备")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
