import SwiftUI
import UserNotifications
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeReminderSection: View {
    @EnvironmentObject var store: NativeStore
    let gearID: String
    var body: some View {
        let rows = store.reminders.filter { $0.gearID == gearID }
        if !rows.isEmpty && !store.readOnly {
            Section("提醒") {
                ForEach(rows) { r in
                    NavigationLink { NativeReminderDetail(id: r.id) } label: {
                        let occurrence = store.reminderOccurrence(r)
                        HStack {
                            Image(systemName: r.enabled ? "bell" : "bell.slash").foregroundStyle(occurrence.due ? Color.orange : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) { Text(r.title); Text(reminderSubtitle(r, occurrence)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

struct NativeReminderDetail: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notifications = NativeNotifications.shared
    let id: String
    @State private var editor: NativeEditorRoute?
    @State private var deleting = false
    var body: some View {
        Group {
            if let r = store.reminders.first(where: { $0.id == id }) {
                let occurrence = store.reminderOccurrence(r)
                Form {
                    Section {
                        NavigationLink(store.name(r.gearID)) { NativeGearDetail(id: r.gearID) }
                        Text(reminderSubtitle(r, occurrence)).foregroundStyle(occurrence.due ? .orange : .secondary)
                        if r.mode == .total { LabeledContent("累计里程达到", value: String(format: "%.0f km", r.kilometers)) }
                        if r.mode == .usage {
                            if r.kilometers > 0 { LabeledContent("使用距离", value: String(format: "%.0f / %.0f km", occurrence.distance / 1000, r.kilometers)) }
                            if r.days > 0 { LabeledContent("时间间隔", value: "\(r.days) 天") }
                        }
                        Toggle("启用", isOn: Binding(get: { r.enabled }, set: { value in var next = r; next.enabled = value; if value { next.completedCycle = nil; next.generation = UUID().uuidString }; do { try store.saveReminder(next) } catch { store.error = error.userFacingMessage } }))
                    }
                    if r.enabled && occurrence.issue == nil {
                        Section {
                            if r.repeats && (r.anchor == .event || r.eventKind != nil) && r.mode == .usage {
                                Button("记录" + (nativeEventKinds.first { $0.0 == occurrence.eventKind }?.1 ?? r.title)) { editor = .init(kind: "event", item: ["kind": .string(occurrence.eventKind ?? "inspection"), "customName": .string(occurrence.eventCustomName ?? "")], parent: r.gearID) }
                            } else { Button("完成") { do { try store.completeReminder(r) } catch { store.error = error.userFacingMessage } } }
                            if occurrence.due { Button("明天提醒") { do { try store.snoozeReminder(r) } catch { store.error = error.userFacingMessage } } }
                        }
                    }
                    if notifications.permissionRequired { Section { Button(notifications.permissionDenied ? "前往设置开启通知" : "允许通知") { if notifications.permissionDenied { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } else { Task { await notifications.authorize(); store.refreshNotifications() } } } } }
                    if let error = notifications.schedulingError { Section { Text(error).foregroundStyle(.red) } }
                    Section { Button("删除提醒", role: .destructive) { deleting = true }.confirmationDialog("删除这条提醒？", isPresented: $deleting, titleVisibility: .visible) { Button("删除", role: .destructive) { do { try store.removeReminder(id); dismiss() } catch { store.error = error.userFacingMessage } } } }
                }
                .navigationTitle(r.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("编辑") { editor = .init(kind: "reminder", item: ["id": .string(id)], parent: r.gearID) } }
                .sheet(item: $editor) { NativeEditor(route: $0) }
            } else { ContentUnavailableView("提醒已删除", systemImage: "bell.slash") }
        }.task { await notifications.refreshPermission() }
    }
}

struct NativeReminderForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    var existingID = ""
    var eventID = ""
    @State private var reminder: GearReminder
    @State private var extra = false
    @State private var error: String?
    @State private var saving = false
    init(gearID: String, existingID: String = "", eventID: String = "") {
        self.gearID = gearID; self.existingID = existingID; self.eventID = eventID
        var initial = GearReminder(gearID: gearID)
        initial.date = GearReminderEngine.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
        _reminder = State(initialValue: initial)
    }
    private var events: [Value] { store.state["gearEvents"].array.filter { $0["gearId"].text == gearID }.sorted { $0["occurredDate"].text > $1["occurredDate"].text } }
    private var installations: [Value] { store.state["events"].array.filter { $0["gearId"].text == gearID && !$0["parentId"].isNull }.sorted { $0["at"].text > $1["at"].text } }
    var body: some View {
        Form {
            Section {
                TextField("提醒事项", text: $reminder.title).accessibilityIdentifier("reminder-title")
                Picker("条件", selection: $reminder.mode) { Text("累计里程达到").tag(GearReminder.Mode.total); Text("再使用").tag(GearReminder.Mode.usage); Text("到指定日期").tag(GearReminder.Mode.date) }
                if reminder.mode != .date {
                    HStack { Text("距离"); Spacer(); TextField(reminder.mode == .usage ? "可不填" : "公里", value: Binding<Double?>(get: { reminder.kilometers == 0 ? nil : reminder.kilometers }, set: { reminder.kilometers = $0 ?? 0 }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("km").foregroundStyle(.secondary) }
                } else { DatePicker("提醒时间", selection: $reminder.date) }
            }
            Section {
                DisclosureGroup("更多选项", isExpanded: $extra) {
                    if reminder.mode == .usage {
                        HStack { Text("天数"); Spacer(); TextField("可不填", text: Binding(get: { reminder.days == 0 ? "" : String(reminder.days) }, set: { reminder.days = Int($0) ?? 0 })).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        Picker("起点", selection: $reminder.anchor) {
                            Text("现在").tag(GearReminder.Anchor.now)
                            if !events.isEmpty { Text("保养记录").tag(GearReminder.Anchor.event) }
                            if !installations.isEmpty { Text("装配记录").tag(GearReminder.Anchor.installation) }
                        }
                        if reminder.anchor == .event {
                            Picker("记录", selection: $reminder.anchorID) { Text("请选择").tag(""); ForEach(events) { e in Text(eventTitle(e) + " · " + e["occurredDate"].text).tag(e.id) } }
                        }
                        if reminder.anchor == .installation {
                            Picker("装配", selection: $reminder.anchorID) { Text("请选择").tag(""); ForEach(installations) { e in Text(store.name(e["parentId"].text) + " · " + String(e["at"].text.prefix(10))).tag(e.id) } }
                        }
                    }
                    Toggle("重复", isOn: $reminder.repeats)
                    if reminder.repeats {
                        if reminder.mode == .date { HStack { Text("每隔"); TextField("天数", value: $reminder.days, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing); Text("天") } }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(existingID.isEmpty ? "添加提醒" : "编辑提醒").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                do {
                    reminder.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    reminder.generation = UUID().uuidString; reminder.completedCycle = nil; reminder.snoozedCycle = nil; reminder.snoozedUntil = nil
                    let old = store.reminders.first { $0.id == existingID }
                    if existingID.isEmpty || old?.mode != reminder.mode || (reminder.anchor == .now && old?.anchor != .now) { reminder.startedAt = Date() }
                    if reminder.mode == .total && (old?.kilometers != reminder.kilometers || old?.repeatKilometers == nil) { reminder.repeatKilometers = reminder.kilometers }
                    try store.saveReminder(reminder)
                    saving = true
                    Task { await NativeNotifications.shared.authorize(); store.refreshNotifications(); dismiss() }
                } catch let failure { error = failure.userFacingMessage }
            }.disabled(saving || reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .onChange(of: reminder.repeats) { _, value in if value && reminder.mode == .date && reminder.days == 0 { reminder.days = 30 } }
        .task {
            if let saved = store.reminders.first(where: { $0.id == existingID }) { reminder = saved; extra = saved.anchor != .now || saved.repeats || saved.days > 0 }
            else if let event = events.first(where: { $0.id == eventID }) { reminder.anchor = .event; reminder.anchorID = event.id; reminder.title = eventTitle(event); reminder.repeats = true; extra = true }
        }

    }
}
