import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeActivityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let activity: Value
    var distance: Value? = nil
    var gearNames: [String] = []
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: readActivitySymbol(activity["type"].text))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NativeAppearance.accent)
                    .frame(width: 38, height: 38)
                    .background(NativeAppearance.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(activity["name"].text).font(.body.weight(.semibold))
                    .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text(formatActivityDate(activity["at"].text) + " · " + readActivityType(activity["type"].text))
                    .font(.caption).foregroundStyle(NativeAppearance.secondaryText).fixedSize(horizontal: false, vertical: true)
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nativeDistance(distance ?? activity["distance"]))
                            Text(nativeDuration(activity["seconds"]))
                        }
                    } else {
                        Text(nativeDistance(distance ?? activity["distance"]) + " · " + nativeDuration(activity["seconds"]))
                    }
                }.font(.subheadline).monospacedDigit().foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                if !gearNames.isEmpty {
                    Text(gearNames.joined(separator: " · ")).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if activity["pending"].flag {
                    Label(activity["source"].text.uppercased() == "STRAVA" ? "主装备仅保存在本机" : activity["mainConflict"].flag ? "主装备待确认" : "ICU 待同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(NativeActivityPalette.attention)
                } else if activity["main"].text.isEmpty && !activity["remoteId"].text.isEmpty {
                    Label("主装备未关联", systemImage: "link").font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                }
            }
        }.padding(.vertical, 8)
    }
}

private enum NativeActivityPalette {
    static let attention = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.68, blue: 0.33, alpha: 1)
        : UIColor(red: 0.69, green: 0.34, blue: 0.04, alpha: 1) })
}

private func readActivitySymbol(_ type: String) -> String {
    switch type {
    case "VirtualRide": "figure.indoor.cycle"
    case "Ride", "MountainBikeRide", "GravelRide", "EBikeRide": "figure.outdoor.cycle"
    case "Run", "VirtualRun", "TrailRun": "figure.run"
    case "Walk", "Hike": "figure.walk"
    case "Swim": "figure.pool.swim"
    case "WeightTraining": "dumbbell"
    default: "figure.mixed.cardio"
    }
}

private func readActivityType(_ type: String) -> String {
    switch type {
    case "Ride": "骑行"
    case "VirtualRide": "室内骑行"
    case "MountainBikeRide": "山地骑行"
    case "GravelRide": "砾石骑行"
    case "EBikeRide": "电助力骑行"
    case "Run": "跑步"
    case "VirtualRun": "室内跑步"
    case "TrailRun": "越野跑"
    case "Walk": "步行"
    case "Hike": "徒步"
    case "Swim": "游泳"
    case "WeightTraining": "力量训练"
    default: type.isEmpty ? "其他运动" : type
    }
}

private func formatActivityDate(_ text: String, full: Bool = false) -> String {
    guard let date = GearReminderEngine.parse(text) else { return text.isEmpty ? "日期未知" : text.replacingOccurrences(of: "T", with: " ") }
    return NativeDate.format(date, full ? "yyyy年M月d日 HH:mm" : "M月d日 HH:mm")
}

private struct NativeActivitySearchRow: Identifiable, Sendable {
    let activity: Value
    let month: String
    let gearNames: [String]
    let searchable: [String]
    var id: String { activity.id }
}

private func buildActivitySearchRows(_ activities: [Value], gears: [String: Value]) throws -> [NativeActivitySearchRow] {
    try activities.enumerated().map { offset, activity in
        if offset.isMultiple(of: 64) { try Task.checkCancellation() }
        let snapshot = activity["snapshot"].array
        func readNames(_ ids: [Value]) -> [String] {
            var seen = Set<String>()
            return ids.compactMap { id in
                guard !id.text.isEmpty, seen.insert(id.text).inserted else { return nil }
                let savedName = gears[id.text]?["name"].text ?? ""
                if !savedName.isEmpty { return savedName }
                let snapshotName = snapshot.first { $0.id == id.text }?["name"].text ?? ""
                return snapshotName.isEmpty ? nil : snapshotName
            }
        }
        let roots = [activity["main"], activity["shoe"], activity["trainer"]] + activity["extras"].array
        let at = activity["at"].text, date = GearReminderEngine.parse(at)
        let month = date.map { NativeDate.format($0, "yyyy年M月") } ?? "日期未知"
        let fullDate = date.map { NativeDate.format($0, "yyyy年M月d日 HH:mm") }
            ?? (at.isEmpty ? "日期未知" : at.replacingOccurrences(of: "T", with: " "))
        let searchable = [activity["name"].text, readActivityType(activity["type"].text), at, fullDate]
            + readNames(roots + snapshot.map { $0["id"] })
        return NativeActivitySearchRow(activity: activity, month: month, gearNames: readNames(roots), searchable: searchable)
    }
}

private func filterActivitySearchRows(_ rows: [NativeActivitySearchRow], terms: [String], filter: GearActivityFilter) throws -> [NativeActivitySearchRow] {
    guard !terms.isEmpty || filter.isActive else { return rows }
    return try rows.enumerated().compactMap { offset, row in
        if offset.isMultiple(of: 64) { try Task.checkCancellation() }
        return filter.matchesActivity(row.activity) && terms.allSatisfy { term in row.searchable.contains { $0.localizedCaseInsensitiveContains(term) } } ? row : nil
    }
}

struct NativeActivities: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var filter = GearActivityFilter()
    @State private var limit = 60
    @State private var rows: [NativeActivitySearchRow] = []
    @State private var searchIndex: [NativeActivitySearchRow] = []
    @State private var indexGeneration = -1
    @State private var displayedQuery: ActivityQuery?
    private struct ActivityQuery: Equatable {
        let generation: Int
        let search: String
        let filter: GearActivityFilter
    }
    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var loading: Bool {
        indexGeneration != store.viewGeneration || displayedQuery != currentQuery
    }
    private var currentQuery: ActivityQuery { ActivityQuery(generation: indexGeneration, search: searchTerm, filter: filter) }
    private var activityTypes: [String] {
        Set(searchIndex.map { $0.activity["type"].text }).filter { !$0.isEmpty }.sorted {
            readActivityType($0).localizedStandardCompare(readActivityType($1)) == .orderedAscending
        }
    }
    private var months: [(key: String, activities: [NativeActivitySearchRow], count: Int)] {
        let grouped = Dictionary(grouping: rows.prefix(limit), by: \.month)
        let counts = rows.reduce(into: [String: Int]()) { $0[$1.month, default: 0] += 1 }
        var seen = Set<String>()
        return rows.prefix(limit).compactMap { row in
            let key = row.month
            guard seen.insert(key).inserted else { return nil }
            return (key, grouped[key] ?? [], counts[key] ?? 0)
        }
    }
    private func rebuildSearchIndex() async {
        let generation = store.viewGeneration
        guard !Task.isCancelled, indexGeneration != generation else { return }
        let activities = store.activities
        var gears = Dictionary(store.state["gears"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        gears.merge(store.treeIndex.byID) { _, displayed in displayed }
        let capturedGears = gears
        if rows.isEmpty, searchTerm.isEmpty, !filter.isActive,
           let first = try? buildActivitySearchRows(Array(activities.prefix(60)), gears: capturedGears),
           !Task.isCancelled, store.viewGeneration == generation, searchTerm.isEmpty {
            rows = first
        }
        let task = Task.detached(priority: .userInitiated) { try buildActivitySearchRows(activities, gears: capturedGears) }
        do {
            let next = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, store.viewGeneration == generation else { return }
            searchIndex = next
            indexGeneration = generation
        } catch { }
    }
    private func refreshRows() async {
        let query = currentQuery
        guard query.generation >= 0, query.generation == store.viewGeneration else { return }
        let indexed = searchIndex, terms = query.search.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.isEmpty && !query.filter.isActive {
            rows = indexed; displayedQuery = query; return
        }
        let task = Task.detached(priority: .userInitiated) { try filterActivitySearchRows(indexed, terms: terms, filter: query.filter) }
        do {
            let next = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, store.viewGeneration == query.generation,
                  currentQuery == query else { return }
            rows = next
            displayedQuery = query
        } catch { }
    }
    var body: some View {
        List {
            if filter.isActive { renderActiveFilters() }
            if store.refreshingGears && !store.busy && !rows.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取装备").fixedSize(horizontal: false, vertical: true)
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier("activities-gear-refresh-progress")
                }.listRowBackground(NativeAppearance.surface)
            }
            ForEach(months, id: \.key) { month in
                Section {
                    ForEach(month.activities) { row in
                        NavigationLink { NativeActivityDetail(id: row.id) } label: {
                            NativeActivityRow(activity: row.activity, gearNames: row.gearNames)
                        }
                        .accessibilityIdentifier("activity-row-" + row.id)
                        .listRowBackground(NativeAppearance.surface)
                    }
                } header: {
                    renderMonthHeader(month.key, count: month.count)
                }
            }
            if rows.count > limit {
                Section {
                    Button { limit += 60 } label: {
                        Text("显示更多活动").frame(maxWidth: .infinity, minHeight: 32)
                    }.accessibilityIdentifier("activities-load-more")
                }.listRowBackground(NativeAppearance.surface)
            }
        }
        .overlay {
            if rows.isEmpty && loading {
                ProgressView("正在读取活动").accessibilityIdentifier("activities-loading")
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label(searchTerm.isEmpty && !filter.isActive ? "暂无活动" : "没有匹配的活动", systemImage: searchTerm.isEmpty && !filter.isActive ? "figure.outdoor.cycle" : "magnifyingglass")
                } actions: {
                    if filter.isActive {
                        Button("清除筛选") { filter = GearActivityFilter() }.accessibilityIdentifier("activities-clear-filters")
                    } else if !searchTerm.isEmpty {
                        Button("清除搜索") { search = "" }.accessibilityIdentifier("activities-clear-search")
                    } else if store.connected {
                        Button { Task { await store.sync() } } label: {
                            Text(store.refreshingGears ? "正在读取装备" : store.busy ? "同步中…" : "同步活动")
                                .foregroundStyle(store.busy || store.refreshingGears ? NativeAppearance.secondaryText : NativeAppearance.accent)
                        }
                            .disabled(store.busy || store.refreshingGears).accessibilityIdentifier("activities-sync")
                    } else {
                        NavigationLink("连接 Intervals.icu") { NativeSync() }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("活动").searchable(text: $search, prompt: "活动、装备或日期")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("运动类型", selection: $filter.type) {
                        Text("全部运动").tag("")
                        ForEach(activityTypes, id: \.self) { type in Text(readActivityType(type)).tag(type) }
                    }
                    Picker("装备关联", selection: $filter.assignment) {
                        ForEach(GearActivityFilter.Assignment.allCases, id: \.self) { assignment in
                            Text(readAssignmentTitle(assignment)).tag(assignment)
                        }
                    }
                    if filter.isActive { Button("清除筛选") { filter = GearActivityFilter() } }
                } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }.accessibilityLabel("筛选活动").accessibilityIdentifier("activities-filters")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            guard !store.refreshingGears else { return }
            await store.sync()
        }
        .onChange(of: search) { _, _ in limit = 60 }
        .onChange(of: filter) { _, _ in limit = 60 }
        .task(id: store.viewGeneration) { await rebuildSearchIndex() }
        .task(id: currentQuery) { await refreshRows() }
    }
    @ViewBuilder private func renderMonthHeader(_ title: String, count: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Text("\(count) 次活动").font(.caption).monospacedDigit()
            }.accessibilityElement(children: .combine)
        } else {
            HStack {
                Text(title)
                Spacer()
                Text("\(count) 次活动").monospacedDigit()
            }.accessibilityElement(children: .combine)
        }
    }
    private func readAssignmentTitle(_ assignment: GearActivityFilter.Assignment) -> String {
        switch assignment {
        case .all: "全部关联状态"
        case .unlinked: "主装备未关联"
        case .pending: "待确认或同步"
        }
    }
    private func renderActiveFilters() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !filter.type.isEmpty {
                    renderFilterChip(readActivityType(filter.type), identifier: "activities-filter-type") { filter.type = "" }
                }
                if filter.assignment != .all {
                    renderFilterChip(readAssignmentTitle(filter.assignment), identifier: "activities-filter-assignment") { filter.assignment = .all }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear).listRowSeparator(.hidden)
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
}
struct NativeActivityDetail: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    var usedGear: String? = nil
    @State private var main = ""
    @State private var shoe = ""
    @State private var trainer = ""
    @State private var baseline: Value = [:]
    @State private var changedFields = Set<String>()
    @State private var rebuild = false
    @State private var saving = false
    @State private var error: String?
    @State private var preview: Value = [:]
    @State private var activityStatus: Value = ["uncertain": true]
    @State private var editor: NativeEditorRoute?
    @State private var confirmingDiscard = false
    @State private var dismissAfterDiscard = false
    private var activity: Value { store.state["activities"].array.first { $0.id == id } ?? [:] }
    private var editable: Bool { !store.readOnly && !activity["unavailable"].flag && !activity["summary"].flag && !activity["deleted"].flag }
    private var dirty: Bool { !changedFields.isEmpty || rebuild }
    private var assignment: Value {
        var patch: Value = [:]
        for (field, value) in [("main", main), ("shoe", shoe), ("trainer", trainer)] where changedFields.contains(field) { patch[field] = .optional(value) }
        if rebuild { patch["rebuild"] = true }
        return patch
    }
    private var snapshot: [Value] { (dirty ? preview : activity)["snapshot"].array }
    private var usesLocalMain: Bool { activity["assignmentOverrides"].isNull ? activity["manual"].flag : !activity["assignmentOverrides"]["main"].isNull }
    private var remoteName: String {
        let remoteID = activity["remoteId"].text
        if remoteID.isEmpty { return "无" }
        if let row = store.state["remoteGears"].array.first(where: { $0.id == remoteID }) { return row["name"].text }
        if !activity["remoteGearName"].text.isEmpty { return activity["remoteGearName"].text }
        return "未关联装备"
    }
    private var cannotUpload: Bool { activity["source"].text.uppercased() == "STRAVA" }
    private func choice(_ field: String, _ value: Binding<String>) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { next in
            value.wrappedValue = next
            let hasOverride = !activity["assignmentOverrides"][field].isNull || (field == "main" && usesLocalMain)
            if next == baseline[field].text && hasOverride { changedFields.remove(field); refreshDraft() }
            else { changedFields.insert(field) }
            updatePreview()
        })
    }
    private func candidates(_ types: [String], _ selected: String) -> [Value] {
        store.state["gears"].array.filter { types.contains($0["type"].text) && (($0["deletedAt"].isNull && !activityStatus["uncertain"].flag && activityStatus["statuses"][$0.id] == "active") || $0.id == selected) }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Label(readActivityType(activity["type"].text), systemImage: readActivitySymbol(activity["type"].text))
                        .font(.subheadline).foregroundStyle(NativeAppearance.accent)
                    Text(activity["name"].text).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(formatActivityDate(activity["at"].text, full: true)).font(.subheadline).foregroundStyle(NativeAppearance.secondaryText)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            NativeMetric(title: "活动距离", value: nativeDistance(activity["distance"]))
                            NativeMetric(title: "运动时间", value: nativeDuration(activity["seconds"]))
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            NativeMetric(title: "活动距离", value: nativeDistance(activity["distance"]))
                            NativeMetric(title: "运动时间", value: nativeDuration(activity["seconds"]))
                        }
                    }
                }.padding(.vertical, 8)
                if let usedGear, let row = activity["snapshot"].array.first(where: { $0.id == usedGear }) {
                    LabeledContent(store.name(usedGear), value: nativeDistance(row["distanceIncluded"] == false ? 0 : activity["distance"]))
                }
            }.listRowBackground(NativeAppearance.surface)
            if activity["assemblyTimeUnknown"].flag || activityStatus["uncertain"].flag {
                Section {
                    Label(activity["startInstant"].isNull ? "活动缺少可靠的开始时刻，组件归属尚未确定。请同步完整活动后预览重算。" : "活动已获得开始时刻，组件归属仍需预览重算。", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(NativeActivityPalette.attention)
                        .accessibilityIdentifier("activity-time-uncertain")
                }.listRowBackground(NativeAppearance.surface)
            }
            if store.view["inventoryConflicts"].array.contains(.string(id)) {
                Section {
                    Label("活动使用了当时在库存或已退役的装备，请核对装备的使用日期。", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(NativeActivityPalette.attention)
                }.listRowBackground(NativeAppearance.surface)
            }
            Section("装备") {
                Picker("主装备", selection: choice("main", $main)) { Text("无").tag(""); ForEach(candidates(["Bike", "Shoes"], main)) { Text(store.displayName($0.id)).tag($0.id) } }.accessibilityIdentifier("activity-main")
                Picker("锁鞋", selection: choice("shoe", $shoe)) { Text("无").tag(""); ForEach(candidates(["CyclingShoes"], shoe)) { Text(store.displayName($0.id)).tag($0.id) } }.accessibilityIdentifier("activity-shoe")
                Picker("骑行台", selection: choice("trainer", $trainer)) { Text("无").tag(""); ForEach(candidates(["Trainer"], trainer)) { Text(store.displayName($0.id)).tag($0.id) } }.accessibilityIdentifier("activity-trainer")
            }.disabled(!editable || saving).listRowBackground(NativeAppearance.surface)
            if editable { syncSection }
            if !snapshot.isEmpty {
                Section("装配") {
                    ForEach(snapshotRows(snapshot), id: \.0.id) { row, depth in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.name(row.id)).fixedSize(horizontal: false, vertical: true)
                            if row["distanceIncluded"] == false { Text("不计距离").font(.caption).foregroundStyle(NativeAppearance.secondaryText) }
                        }
                        .padding(.leading, CGFloat(min(depth, 5)) * 16)
                        .accessibilityElement(children: .combine)
                    }
                }.listRowBackground(NativeAppearance.surface)
            }
            if editable {
                Section {
                    Button("重算装备") { rebuild = true; updatePreview() }.disabled(saving)
                    if dirty {
                        Button("取消修改") { requestDiscard(dismissAfterward: false) }
                            .disabled(saving).accessibilityIdentifier("activity-cancel")
                    }
                }.listRowBackground(NativeAppearance.surface)
            } else if activity["unavailable"].flag || activity["summary"].flag { Section { Text("活动信息不完整，暂时无法修改装备。") }.listRowBackground(NativeAppearance.surface) }
            if let error, error != UserFacingError.text(activity["error"].text) { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
            if !activity["error"].text.isEmpty && !activity["mainConflict"].flag && !cannotUpload { Section { Text(UserFacingError.text(activity["error"].text)).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
            NativePhotoSection(owner: "activity", ownerID: id, readOnly: !editable)
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("活动详情").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(dirty || saving)
        .interactiveDismissDisabled(dirty || saving)
        .toolbar {
            if dirty || saving {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { requestDiscard(dismissAfterward: true) }
                        .disabled(saving).accessibilityIdentifier("activity-back")
                }
            }
            if editable { ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中…" : "保存", action: save).disabled(!dirty || saving).accessibilityIdentifier("activity-save") } }
        }
        .alert("放弃未保存的更改？", isPresented: $confirmingDiscard) {
            Button("放弃更改", role: .destructive) {
                load()
                if dismissAfterDiscard { dismiss() }
            }
            Button("继续编辑", role: .cancel) {}
        }
        .task { load() }
        .onChange(of: store.revision) { _, _ in if !saving { refreshDraft(); if dirty { updatePreview() } } }
        .sheet(item: $editor) { NativeEditor(route: $0) }
    }
    @ViewBuilder private var syncSection: some View {
        if activity["pending"].flag {
            Section("ICU 主装备") {
                Text(cannotUpload ? "本机已保存" : "本机已保存 · ICU 待同步").foregroundStyle(NativeAppearance.secondaryText).accessibilityIdentifier("activity-pending")
                if cannotUpload { Text("Strava 来源的活动无法上传装备修改。") }
                if activity["mainConflict"].flag {
                    LabeledContent("本机", value: main.isEmpty ? "无" : store.name(main))
                    LabeledContent("ICU", value: remoteName)
                    Button("采用 ICU", action: followRemote).accessibilityIdentifier("activity-use-remote")
                    if !main.isEmpty && store.gear(main)["remoteId"].isNull {
                        Button("关联 ICU 装备") { editor = .init(kind: "gear", item: store.gear(main)) }
                    } else if !cannotUpload { Button("采用本机") { upload(adoptingRemote: activity["remoteId"]) }.accessibilityIdentifier("activity-use-local") }
                } else if !main.isEmpty && store.gear(main)["remoteId"].isNull {
                    Button("关联 ICU 装备") { editor = .init(kind: "gear", item: store.gear(main)) }
                } else if !cannotUpload {
                    Button("上传到 ICU") { upload() }.accessibilityIdentifier("activity-upload")
                }
                if !activity["mainConflict"].flag { Button("恢复跟随 ICU", action: followRemote).accessibilityIdentifier("activity-follow-remote") }
            }.disabled(saving || dirty).listRowBackground(NativeAppearance.surface)
        } else if usesLocalMain {
            Section("ICU 主装备") {
                LabeledContent("状态", value: activity["assignmentOverrides"]["main"].text == "legacy" || activity["assignmentOverrides"].isNull ? "旧版手动指定" : "本机指定")
                Button("恢复跟随 ICU", action: followRemote).accessibilityIdentifier("activity-follow-remote")
            }.disabled(saving || dirty).listRowBackground(NativeAppearance.surface)
        } else if activity["main"].text.isEmpty && !activity["remoteId"].text.isEmpty {
            Section("ICU 主装备") {
                LabeledContent("未关联", value: remoteName)
                NavigationLink("关联装备") { NativeActivityGearLink(remoteID: activity["remoteId"].text) }
            }.disabled(saving || dirty).listRowBackground(NativeAppearance.surface)
        }
    }
    private func readChoices() -> Value {
        ["main": activity["main"],
         "shoe": activity["extras"].array.first { store.gear($0.text)["type"].text == "CyclingShoes" } ?? .null,
         "trainer": activity["extras"].array.first { store.gear($0.text)["type"].text == "Trainer" } ?? .null]
    }
    private func requestDiscard(dismissAfterward: Bool) {
        dismissAfterDiscard = dismissAfterward
        confirmingDiscard = true
    }
    private func refreshDraft() {
        activityStatus = (try? store.query("activity-statuses", ["id": .string(id)])) ?? ["uncertain": true]
        let saved = readChoices()
        if !changedFields.contains("main") { main = saved["main"].text; baseline["main"] = saved["main"] }
        if !changedFields.contains("shoe") { shoe = saved["shoe"].text; baseline["shoe"] = saved["shoe"] }
        if !changedFields.contains("trainer") { trainer = saved["trainer"].text; baseline["trainer"] = saved["trainer"] }
        if !dirty { preview = activity }
    }
    private func load() { changedFields = []; rebuild = false; error = nil; refreshDraft() }
    private func updatePreview() {
        do { preview = try store.query("assignment-preview", ["id": .string(id), "assignment": assignment]); error = nil }
        catch let failure { error = failure.userFacingMessage }
    }
    private func save() {
        do {
            let needsUpload = try store.saveAssignment(id: id, assignment: assignment)
            load() // Clear saved drafts before any network request can fail.
            if needsUpload { upload() }
        } catch let failure { error = failure.userFacingMessage }
    }
    private func followRemote() {
        do { try store.saveAssignment(id: id, assignment: ["followRemote": true]); load() }
        catch let failure { error = failure.userFacingMessage }
    }
    private func upload(adoptingRemote expectedRemote: Value? = nil) {
        saving = true
        Task {
            defer { saving = false; refreshDraft() }
            do { try await store.sendGear(id, adoptingRemote: expectedRemote); error = nil }
            catch let failure { error = failure.userFacingMessage }
        }
    }
}

struct NativeActivityGearLink: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let remoteID: String
    @State private var error: String?
    private var remote: Value { store.state["remoteGears"].array.first { $0.id == remoteID } ?? [:] }
    var body: some View {
        List {
            if !remote.id.isEmpty && !remote["component"].flag && ["Bike", "Shoes"].contains(remote["type"].text) {
                Section(remote["name"].text) {
                    ForEach(store.gears.filter { $0["type"] == remote["type"] && $0["remoteId"].isNull && $0["deletedAt"].isNull }) { gear in
                        Button(store.displayName(gear.id)) {
                            do {
                                var input = gear; input["remoteId"] = .string(remoteID)
                                try store.commit("gear", input); dismiss()
                            } catch let failure { error = failure.userFacingMessage }
                        }
                    }
                    NavigationLink("新建装备") { NativeGearForm(existing: ["name": remote["name"], "type": remote["type"], "categoryId": remote["type"], "remoteId": .string(remoteID)]) }
                }
            }
            Section {
                Button(store.refreshingGears ? "刷新中…" : "刷新 ICU 装备") {
                    Task { do { try await store.refreshRemoteGears(); error = nil } catch let failure { error = failure.userFacingMessage } }
                }.disabled(!store.connected || store.refreshingGears || store.busy)
            }
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) } }
        }
        .navigationTitle("关联装备").navigationBarTitleDisplayMode(.inline)
        .onAppear { if store.gears.contains(where: { $0["remoteId"].text == remoteID }) { dismiss() } }
    }
}
func snapshotRows(_ rows: [Value]) -> [(Value, Int)] {
    var result: [(Value, Int)] = [], seen = Set<String>(); let known = Set(rows.map(\.id))
    func walk(_ row: Value, _ depth: Int) { guard seen.insert(row.id).inserted else { return }; result.append((row, depth)); for child in rows where child["parentId"].text == row.id { walk(child, depth + 1) } }
    for row in rows where !known.contains(row["parentId"].text) { walk(row, 0) }
    return result
}
