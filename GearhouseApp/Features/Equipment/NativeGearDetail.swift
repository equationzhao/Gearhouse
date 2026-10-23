import SwiftUI
import UniformTypeIdentifiers
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeGearDetail: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    var focusedHistoryID: String? = nil
    @State private var tab = "history"
    @State private var editor: NativeEditorRoute?
    @State private var replacementParent: String?
    @State private var attachmentPreview: Value?
    @State private var importingAttachments = false
    @State private var loadingAttachments = false
    @State private var confirmation: String?
    @State private var pendingHistory: Value = [:]
    @State private var purge: Value = [:]
    @State private var rangeOpen = false
    @State private var from = ""
    @State private var to = ""
    @State private var usage: Value = [:]
    @State private var usageKey: Value = .null
    private var gear: Value { store.gear(id) }
    private var deleted: Bool { !gear["deletedAt"].isNull }
    @State private var timeline: [Value] = []
    @State private var timelineGeneration = -1
    var body: some View {
        ScrollViewReader { proxy in
        List {
            NativePhotoSection(owner: "gear", ownerID: id, gearID: id, readOnly: deleted || store.readOnly)
            Section {
                Text(store.categoryName(for: gear)).foregroundStyle(.secondary)
                LabeledContent("状态", value: GearInventory.describeStatus(store.status(id)))
                if !store.conditionName(gear).isEmpty { LabeledContent("装备状况", value: store.conditionName(gear)) }
                let metrics = store.view["statistics"][id]
                LabeledContent("累计距离", value: nativeDistance(metrics["distance"]))
                LabeledContent("累计时长", value: nativeDuration(metrics["seconds"]))
                Button { tab = "activities" } label: { LabeledContent("活动", value: metrics["count"].isNull ? "—" : "\(metrics["count"].integer) 次") }
                if !gear["notes"].text.isEmpty { Text(gear["notes"].text) }
            }
            if !deleted && !store.readOnly {
                Section { NativeInventoryActions(gearID: id) { if $0 == "replace" { replacementParent = store.parent(id) }; editor = .init(kind: "inventory", item: ["kind": .string($0)], parent: id) } }
            }
            NativeAttachmentSection(gearID: id, readOnly: deleted || store.readOnly, importing: $importingAttachments, loading: $loadingAttachments, preview: $attachmentPreview)
            NativeReminderSection(gearID: id)
            Section { Picker("内容", selection: $tab) { Text("历史").tag("history"); Text("活动").tag("activities") }.pickerStyle(.segmented) }
            if tab == "history" {
                Section {
                    NavigationLink {
                        NativeGearTimeline(gearID: id)
                    } label: {
                        Label("时间线", systemImage: "clock.arrow.circlepath")
                    }.accessibilityIdentifier("gear-timeline-open")
                    if !deleted && !store.readOnly {
                        HStack {
                            Button("添加装配") { editor = .init(kind: "history", parent: id) }.buttonStyle(.borderless)
                            Spacer()
                            Button("添加记录") { editor = .init(kind: "event", parent: id) }.buttonStyle(.borderless)
                        }
                    }
                    ForEach(timeline, id: \.timelineID) { row in
                        let subject = row["subjectGearId"].text
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    if subject != id { NavigationLink { NativeGearDetail(id: subject) } label: { Text(row["subjectName"].text).font(.caption).foregroundStyle(.secondary) } }
                                Text(describeGearRecord(row, name: store.name))
                                }
                                Spacer()
                                if !deleted && !store.readOnly && store.gear(subject)["deletedAt"].isNull && !["purchase", "status"].contains(row["entryType"].text) {
                                    Menu {
                                        if row["entryType"].text == "event" {
                                            Button("添加提醒", systemImage: "bell.badge") { editor = .init(kind: "reminder", item: ["eventID": row["id"]], parent: subject) }
                                        }
                                        Button("编辑") { editor = .init(kind: row["entryType"].text == "operation" ? "inventory" : row["entryType"].text == "event" ? "event" : "history", item: row, parent: row["entryType"].text == "operation" ? row["gearId"].text : subject) }
                                        Button("删除", role: .destructive) {
                                            pendingHistory = row
                                            if row["entryType"].text == "operation" {
                                                do { purge = try store.query("inventory-delete-preview", ["id": row["id"]]); confirmation = "inventory-delete" }
                                                catch { store.error = error.userFacingMessage }
                                            } else { confirmation = row["entryType"].text == "event" ? "event-delete" : "history-delete" }
                                        }
                                    } label: { Image(systemName: "ellipsis") }.accessibilityIdentifier("gear-history-menu-" + row.timelineID)
                                }
                            }
                            Text(row["entryType"].text == "event" && !row["occurredTime"].isNull ? row["occurredDate"].text + " " + row["occurredTime"].text : String(row["at"].text.prefix(10))).font(.caption).foregroundStyle(.secondary)
                            if row["entryType"].text == "event" {
                                if !row["notes"].text.isEmpty { Text(row["notes"].text).font(.callout) }
                                let metrics = store.view["eventStatistics"][row.id]
                                Text("距今 \(metrics["days"].integer) 天 · \(nativeDistance(metrics["distance"]))").font(.caption).foregroundStyle(.secondary)
                                NativePhotoStrip(owner: "event", ownerID: row.id)
                            }
                        }.padding(.vertical, 4).id(row.timelineID)
                    }
                    if timeline.isEmpty { Text("暂无历史").foregroundStyle(.secondary) }
                }
            } else {
                Section {
                    Button { rangeOpen = true } label: { Label(from.isEmpty && to.isEmpty ? "全部日期" : "\(from.isEmpty ? "最早" : from) – \(to.isEmpty ? "至今" : to)", systemImage: "calendar") }
                    LabeledContent("期间距离", value: nativeDistance(usage["summary"]["distance"]))
                    LabeledContent("期间时长", value: nativeDuration(usage["summary"]["seconds"]))
                    LabeledContent("活动", value: "\(usage["summary"]["count"].integer) 次")
                }
                Section("活动记录") {
                    ForEach(usage["rows"].array, id: \.activityID) { row in
                        NavigationLink { NativeActivityDetail(id: row["activity"].id, usedGear: id) } label: { NativeActivityRow(activity: row["activity"], distance: row["distance"]) }
                    }
                    if usage["rows"].array.isEmpty { Text(from.isEmpty && to.isEmpty ? "暂无使用记录" : "这段时间没有使用记录").foregroundStyle(.secondary) }
                }
            }
        }
        .task(id: timelineGeneration) {
            guard timelineGeneration >= 0, let focusedHistoryID,
                  timeline.contains(where: { $0.timelineID == focusedHistoryID }) else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            proxy.scrollTo(focusedHistoryID, anchor: .center)
        }
        }
        .navigationTitle(store.displayName(id)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.readOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if deleted {
                            Button("恢复") { store.perform("restore", ["id": .string(id)]) }
                            Button("永久删除", role: .destructive) { do { purge = try store.query("purge-preview", ["id": .string(id)]); confirmation = "purge" } catch let failure { store.error = failure.userFacingMessage } }
                        } else {
                            Button("编辑", systemImage: "pencil") { editor = .init(kind: "gear", item: gear) }
                            Button("复制装备", systemImage: "doc.on.doc") { editor = .init(kind: "gear-copy", item: gear) }.accessibilityIdentifier("gear-copy")
                            Button("添加提醒", systemImage: "bell.badge") { editor = .init(kind: "reminder", parent: id) }
                            Button("添加组件", systemImage: "plus") { editor = .init(kind: "component", parent: id) }.accessibilityIdentifier("gear-add-component")
                            Button(gear["hidden"].flag ? "取消隐藏" : "隐藏", systemImage: "eye.slash") { store.perform("hidden", ["id": .string(id), "hidden": .bool(!gear["hidden"].flag)]) }
                            Button("重算", systemImage: "arrow.clockwise") { editor = .init(kind: "recompute", parent: id) }
                            Button("删除", role: .destructive) { confirmation = "delete" }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("装备操作").accessibilityIdentifier("gear-detail-menu")
                }
            }
        }
        .sheet(item: $editor, onDismiss: { if let parent = replacementParent, store.parent(id) != parent { dismiss() }; replacementParent = nil }) { NativeEditor(route: $0) }
        .fileImporter(isPresented: $importingAttachments, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                loadingAttachments = true
                Task {
                    defer { loadingAttachments = false }
                    do { for url in urls { try await store.addAttachment(from: url, gearID: id) } }
                    catch { store.error = error.userFacingMessage }
                }
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { store.error = error.userFacingMessage }
            }
        }
        .sheet(item: $attachmentPreview) { record in
            if let url = try? store.attachmentURL(record) { NativeAttachmentPreview(url: url, name: record["name"].text) }
        }
        .sheet(isPresented: $rangeOpen) { NativeRangeSheet(from: from, to: to, maximum: store.snapshotDate ?? NativeDate.today) { from = $0; to = $1; loadUsage() } }
        .confirmationDialog(deletionTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible, presenting: confirmation) { action in
            Button(action == "purge" ? "永久删除" : "删除", role: .destructive) {
                do {
                    switch action {
                    case "purge": try store.commit("purge", ["id": .string(id), "confirmed": true]); dismiss()
                    case "inventory-delete": try store.commit("inventory-delete", ["id": pendingHistory["id"], "confirmed": true, "revision": purge["revision"]])
                    case "history-delete": try store.commit("history-delete", ["gearId": pendingHistory["subjectGearId"], "id": pendingHistory["id"]])
                    case "event-delete": try store.commit("event-delete", ["id": pendingHistory["id"], "confirmed": true, "requestId": .string(UUID().uuidString)])
                    default: try store.commit("delete", ["id": .string(id)]); dismiss()
                    }
                } catch let failure { store.error = failure.userFacingMessage }
                confirmation = nil
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { action in Text(action == "purge" ? "将永久删除该装备、\(purge["installations"].integer) 条装配记录、\(purge["gearEvents"].integer) 条记录和 \(purge["photos"].integer) 张图片、\(purge["attachments"].integer) 个附件，无法恢复。活动和 Intervals.icu 中的装备保留。" : action == "inventory-delete" ? "这次装配和库存变更将一起撤回，已有活动记录保留。" : action == "delete" ? "装备将移入回收站，活动记录保留。" : action == "event-delete" ? "附带图片也会删除，无法恢复。" : "已有活动的装备记录保留。") }
        .task { loadTimeline(); loadUsage() }
        .onChange(of: tab) { _, _ in loadTimeline(); loadUsage() }
        .onChange(of: store.viewGeneration) { _, _ in loadTimeline(); loadUsage() }
    }
    private var deletionTitle: String {
        switch confirmation {
        case "purge": return "永久删除「\(gear["name"].text)」？"
        case "delete": return "删除「\(gear["name"].text)」？"
        case "inventory-delete": return "删除这条更换或库存记录？"
        case "event-delete": return "删除 \(pendingHistory["occurredDate"].text) 的\(eventTitle(pendingHistory))记录？"
        default: return "删除 \(pendingHistory["at"].text.prefix(10)) 的装配记录？"
        }
    }
    private func loadTimeline() {
        guard tab == "history", timelineGeneration != store.viewGeneration else { return }
        timeline = GearTimeline.buildRows(state: store.view, gearID: id).filter { $0["subjectGearId"].text == id }
        timelineGeneration = store.viewGeneration
    }
    private func loadUsage() {
        guard tab == "activities" else { return }
        let key: Value = ["generation": .number(Double(store.viewGeneration)), "id": .string(id), "from": .string(from), "to": .string(to)]
        guard key != usageKey else { return }
        do {
            var input: Value = ["id": .string(id), "from": .string(from), "to": .string(to)]
            if let day = store.snapshotDate { input["date"] = .string(day) }
            usage = try store.query("usage", input)
            usageKey = key
        }
        catch let failure { store.error = failure.userFacingMessage }
    }
}
func eventTitle(_ row: Value) -> String { row["kind"].text == "custom" ? row["customName"].text : nativeEventKinds.first { $0.0 == row["kind"].text }?.1 ?? "记录" }
extension Value {
    var timelineID: String { self["timelineID"].text }
    var activityID: String { self["activity"].id }
    var gearID: String { self["gearId"].text }
}

struct NativeRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var first: Date
    @State private var last: Date
    @State private var hasFirst: Bool
    @State private var hasLast: Bool
    let maximum: String
    let apply: (String, String) -> Void
    init(from: String, to: String, maximum: String = NativeDate.today, apply: @escaping (String, String) -> Void) {
        _first = State(initialValue: NativeDate.parse(from.isEmpty ? NativeDate.shift(maximum, -30) : from))
        _last = State(initialValue: NativeDate.parse(to.isEmpty ? maximum : to))
        _hasFirst = State(initialValue: !from.isEmpty); _hasLast = State(initialValue: !to.isEmpty)
        self.maximum = maximum; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Toggle("开始日期", isOn: $hasFirst)
                if hasFirst { DatePicker("从", selection: $first, in: ...min(hasLast ? last : NativeDate.parse(maximum), NativeDate.parse(maximum)), displayedComponents: .date) }
                Toggle("结束日期", isOn: $hasLast)
                if hasLast { DatePicker("至", selection: $last, in: (hasFirst ? first : NativeDate.parse("2000-01-01"))...NativeDate.parse(maximum), displayedComponents: .date) }
                Button("全部日期") { apply("", ""); dismiss() }
            }
            .navigationTitle("日期范围").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { apply(hasFirst ? NativeDate.format(first,"yyyy-MM-dd") : "", hasLast ? NativeDate.format(last,"yyyy-MM-dd") : ""); dismiss() }.disabled(hasFirst && hasLast && first > last) }
            }
        }.presentationDetents([.medium, .large])
    }
}
