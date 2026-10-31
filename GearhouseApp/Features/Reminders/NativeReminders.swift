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
                ForEach(rows) { reminder in
                    NavigationLink { NativeReminderDetail(id: reminder.id) } label: {
                        NativeReminderSummary(reminder: reminder, occurrence: store.reminderOccurrence(reminder))
                    }
                    .accessibilityIdentifier("reminder-row-" + reminder.id)
                    .listRowBackground(NativeAppearance.surface)
                }
            }
        }
    }
}

struct NativeReminderSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let reminder: GearReminder
    let occurrence: ReminderOccurrence
    var showsDueStatus = true
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            let group = occurrence.readGroup(for: reminder)
            let status = !showsDueStatus && group == .due ? nil : readReminderStatus(reminder, occurrence)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    renderTitle()
                    if let status { renderStatus(status) }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    renderTitle()
                    Spacer(minLength: 0)
                    if let status { renderStatus(status).layoutPriority(1) }
                }
            }
            if reminder.mode != .date || group != .snoozed {
                NativeReminderProgress(reminder: reminder, occurrence: occurrence)
            }
        }.padding(.vertical, 8)
    }
    private func renderTitle() -> some View {
        Text(reminder.title).font(.body.weight(.medium)).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func renderStatus(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(occurrence.due ? NativeReminderPalette.due : NativeAppearance.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum NativeReminderPalette {
    static let due = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.68, blue: 0.33, alpha: 1)
        : UIColor(red: 0.69, green: 0.34, blue: 0.04, alpha: 1) })
    static let track = Color.primary.opacity(0.075)
    static let actionLabel = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.06, alpha: 1) : .white })
}

private struct NativeReminderProgress: View {
    let reminder: GearReminder
    let occurrence: ReminderOccurrence
    var prominent = false
    var body: some View {
        if let progress = occurrence.progress {
            VStack(alignment: .leading, spacing: prominent ? 22 : 13) {
                if let distance = progress.distance {
                    NativeReminderProgressMeasure(metric: distance, unit: "km", scale: 1000,
                                                  due: occurrence.due, prominent: prominent)
                        .accessibilityLabel(reminder.mode == .total ? "累计距离" : "使用距离")
                        .accessibilityIdentifier("reminder-progress-" + reminder.id + "-distance")
                }
                if let days = progress.days {
                    NativeReminderProgressMeasure(metric: days, unit: "天", scale: 1,
                                                  due: occurrence.due, prominent: prominent && progress.distance == nil)
                        .accessibilityLabel("使用天数")
                        .accessibilityIdentifier("reminder-progress-" + reminder.id + "-days")
                }
                if reminder.mode == .date, let deadline = progress.deadline {
                    Text(NativeDate.format(deadline, prominent ? "yyyy年M月d日" : "M月d日 HH:mm"))
                        .font(prominent ? .title2.weight(.semibold) : .subheadline)
                        .foregroundStyle(prominent ? Color.primary : NativeAppearance.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if prominent {
                        Text(NativeDate.format(deadline, "HH:mm")).font(.subheadline).foregroundStyle(NativeAppearance.secondaryText)
                    }
                }
            }
        }
    }
}

private struct NativeReminderProgressMeasure: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: ReminderProgressMetric
    let unit: String
    let scale: Double
    let due: Bool
    var prominent = false
    private var current: Double { metric.current / scale }
    private var target: Double { metric.target / scale }
    private var tint: Color { due ? NativeReminderPalette.due : NativeAppearance.accent }
    private var precision: Int {
        guard unit != "天" else { return 0 }
        let smallest = [current, target, abs(target - current)].filter { $0 > 0 }.min() ?? 1
        return smallest < 1 ? min(6, max(1, Int(ceil(-log10(smallest))) + 1)) : 1
    }
    private var amount: String { formatAmount(current) + " / " + formatAmount(target) + " " + unit }
    private var remaining: String {
        if current > target { return "超出 " + formatAmount(current - target) + " " + unit }
        if current == target { return unit == "天" ? "已到提醒日期" : "已到提醒里程" }
        return "还剩 " + formatAmount(target - current) + " " + unit
    }
    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 12 : 7) {
            if prominent {
                (Text(formatAmount(current)).font(.largeTitle.weight(.semibold))
                 + Text(" / " + formatAmount(target) + " " + unit).font(.title3).foregroundColor(NativeAppearance.secondaryText))
                    .foregroundStyle(.primary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                Text(remaining).font(.subheadline).foregroundStyle(due ? tint : NativeAppearance.secondaryText)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { renderAmount(); renderRemaining() }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    renderAmount()
                    Spacer(minLength: 0)
                    renderRemaining().multilineTextAlignment(.trailing)
                }
            }
            GeometryReader { geometry in
                Capsule().fill(NativeReminderPalette.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: geometry.size.width * metric.fraction)
                    }
            }.frame(height: 5.5).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(amount + "，" + remaining)
    }
    private func renderAmount() -> some View {
        Text(amount).font(.caption).monospacedDigit().foregroundStyle(NativeAppearance.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func renderRemaining() -> some View {
        Text(remaining).font(.caption).foregroundStyle(due ? tint : NativeAppearance.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func formatAmount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...precision)))
    }
}

private func formatReminderNumber(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}

private func readReminderStatus(_ reminder: GearReminder, _ occurrence: ReminderOccurrence, now: Date = Date()) -> String? {
    if let issue = occurrence.issue { return issue }
    if reminder.snoozedCycle == occurrence.cycle, let until = reminder.snoozedUntil, until > now {
        return "稍后提醒 · " + NativeDate.format(until, "M月d日 HH:mm")
    }
    if occurrence.due { return "待处理" }
    if reminder.mode == .date, let deadline = occurrence.progress?.deadline {
        let calendar = GearReminderEngine.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline)).day ?? 0
        return days == 0 ? "今天" : days == 1 ? "明天" : "还有 \(days) 天"
    }
    return nil
}

struct NativeReminderDetail: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notifications = NativeNotifications.shared
    let id: String
    @State private var editor: NativeEditorRoute?
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        Group {
            if let reminder = store.reminders.first(where: { $0.id == id }) {
                let occurrence = store.reminderOccurrence(reminder)
                Form {
                    Section {
                        Text(reminder.title).font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reminder-detail-title")
                        NavigationLink(store.displayName(reminder.gearID)) { NativeGearDetail(id: reminder.gearID) }
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 14) {
                            if let status = readReminderStatus(reminder, occurrence) {
                                Text(status).font(.subheadline.weight(.medium))
                                    .foregroundStyle(occurrence.due ? NativeReminderPalette.due : NativeAppearance.secondaryText)
                            }
                            NativeReminderProgress(reminder: reminder, occurrence: occurrence, prominent: true)
                        }.padding(.vertical, 10)
                    }.listRowBackground(NativeAppearance.surface)
                    Section {
                        if let start = occurrence.progress?.startedAt {
                            LabeledContent(readStartTitle(reminder, occurrence), value: NativeDate.format(start, "yyyy年M月d日"))
                        }
                        LabeledContent("重复", value: readRepeatInterval(reminder))
                        Toggle("启用", isOn: Binding(get: { reminder.enabled }, set: { value in
                            var next = reminder
                            next.enabled = value
                            if value { next.completedCycle = nil; next.generation = UUID().uuidString }
                            performChange { try store.saveReminder(next) }
                        })).disabled(store.readOnly).accessibilityIdentifier("reminder-enabled")
                    }.listRowBackground(NativeAppearance.surface)
                    if !store.readOnly && reminder.enabled && occurrence.issue == nil {
                        Section {
                            Button {
                                if reminder.repeats && (reminder.anchor == .event || reminder.eventKind != nil) && reminder.mode == .usage {
                                    editor = .init(kind: "event", item: ["kind": .string(occurrence.eventKind ?? "inspection"), "customName": .string(occurrence.eventCustomName ?? "")], parent: reminder.gearID)
                                } else {
                                    performChange { try store.completeReminder(reminder) }
                                }
                            } label: {
                                Text(readRecordTitle(reminder, occurrence)).font(.body.weight(.semibold))
                                    .foregroundStyle(NativeReminderPalette.actionLabel)
                                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                            .accessibilityIdentifier("reminder-record")
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                            if occurrence.due {
                                Button("明天提醒") {
                                    performChange { try store.snoozeReminder(reminder) }
                                }.frame(maxWidth: .infinity, minHeight: 44).listRowBackground(Color.clear).listRowSeparator(.hidden)
                            }
                        }
                    }
                    if !store.readOnly && notifications.permissionRequired {
                        Section {
                            Button(notifications.permissionDenied ? "前往设置开启通知" : "允许通知") {
                                if notifications.permissionDenied {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                } else { Task { await notifications.authorize(); store.refreshNotifications() } }
                            }
                        }.listRowBackground(NativeAppearance.surface)
                    }
                    if let error = notifications.schedulingError { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) } }
                    if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
                    if !store.readOnly {
                        Section {
                            Button("删除提醒", role: .destructive) { deleting = true }
                                .confirmationDialog("删除这条提醒？", isPresented: $deleting, titleVisibility: .visible) {
                                    Button("删除", role: .destructive) {
                                        performChange { try store.removeReminder(id); dismiss() }
                                    }
                                }
                        }.listRowBackground(NativeAppearance.surface)
                    }
                }
                .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
                .navigationTitle("提醒").navigationBarTitleDisplayMode(.inline)
                .toolbar { if !store.readOnly { Button("编辑") { editor = .init(kind: "reminder", item: ["id": .string(id)], parent: reminder.gearID) } } }
                .sheet(item: $editor) { NativeEditor(route: $0) }
            } else { ContentUnavailableView("提醒已删除", systemImage: "bell.slash") }
        }.task { await notifications.refreshPermission() }
    }
    private func performChange(_ change: () throws -> Void) {
        guard !store.readOnly else { return }
        do { try change(); error = nil }
        catch { self.error = error.userFacingMessage }
    }
    private func readRecordTitle(_ reminder: GearReminder, _ occurrence: ReminderOccurrence) -> String {
        guard reminder.repeats && (reminder.anchor == .event || reminder.eventKind != nil) && reminder.mode == .usage else { return "完成" }
        let title = occurrence.eventKind == "custom" ? occurrence.eventCustomName : nativeEventKinds.first { $0.0 == occurrence.eventKind }?.1
        return "记录" + (title ?? reminder.title)
    }
    private func readStartTitle(_ reminder: GearReminder, _ occurrence: ReminderOccurrence) -> String {
        if let kind = occurrence.eventKind {
            let title = kind == "custom" ? occurrence.eventCustomName : nativeEventKinds.first { $0.0 == kind }?.1
            return reminder.repeats ? "最近" + (title ?? "保养") : "保养日期"
        }
        return reminder.anchor == .installation ? "装配日期" : "开始日期"
    }
    private func readRepeatInterval(_ reminder: GearReminder) -> String {
        guard reminder.repeats else { return "不重复" }
        var intervals: [String] = []
        if reminder.mode != .date && reminder.kilometers > 0 {
            let kilometers = reminder.mode == .total ? reminder.repeatKilometers ?? reminder.kilometers : reminder.kilometers
            intervals.append(formatReminderNumber(kilometers) + " km")
        }
        if reminder.mode != .total && reminder.days > 0 { intervals.append("\(reminder.days) 天") }
        return "每 " + intervals.joined(separator: " 或 ")
    }
}

struct NativeReminderForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    var existingID = ""
    var eventID = ""
    @State private var reminder: GearReminder
    @State private var baseline: GearReminder?
    @State private var error: String?
    @State private var saving = false
    @State private var discarding = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case title, distance, days, interval }
    private var hasChanges: Bool { baseline.map { $0 != reminder } ?? false }
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
                TextField("提醒事项", text: $reminder.title, axis: .vertical)
                    .focused($focusedField, equals: .title).submitLabel(.done)
                    .accessibilityIdentifier("reminder-title")
            }.listRowBackground(NativeAppearance.surface)
            Section {
                Picker("条件", selection: $reminder.mode) { Text("累计里程达到").tag(GearReminder.Mode.total); Text("再使用").tag(GearReminder.Mode.usage); Text("到指定日期").tag(GearReminder.Mode.date) }
                if reminder.mode != .date {
                    HStack {
                        Text("距离")
                        Spacer(minLength: 12)
                        TextField(reminder.mode == .usage ? "可不填" : "公里", value: Binding<Double?>(get: { reminder.kilometers == 0 ? nil : reminder.kilometers }, set: { reminder.kilometers = $0 ?? 0 }), format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                            .frame(minWidth: 60, maxWidth: 160).focused($focusedField, equals: .distance)
                            .accessibilityLabel("距离，公里").accessibilityIdentifier("reminder-distance")
                        Text("km").foregroundStyle(NativeAppearance.secondaryText)
                    }
                } else { DatePicker("提醒时间", selection: $reminder.date) }
                if reminder.mode == .usage {
                    HStack {
                        Text("天数")
                        Spacer(minLength: 12)
                        TextField("可不填", value: Binding<Int?>(get: { reminder.days == 0 ? nil : reminder.days }, set: { reminder.days = $0 ?? 0 }), format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                            .frame(minWidth: 60, maxWidth: 160).focused($focusedField, equals: .days)
                            .accessibilityLabel("使用天数").accessibilityIdentifier("reminder-days")
                        Text("天").foregroundStyle(NativeAppearance.secondaryText)
                    }
                }
            } header: {
                Text("提醒条件")
            } footer: {
                if reminder.mode == .usage && reminder.kilometers > 0 && reminder.days > 0 {
                    Text("距离或天数先达到时提醒。")
                }
            }.listRowBackground(NativeAppearance.surface)
            if reminder.mode == .usage {
                Section("开始计算") {
                    Picker("起点", selection: bindAnchor()) {
                        if reminder.anchor == .now, let kind = reminder.eventKind {
                            let title = kind == "custom" ? reminder.eventCustomName ?? "保养" : nativeEventKinds.first { $0.0 == kind }?.1 ?? "保养"
                            Text("跟随" + title + "记录").tag("follow-event")
                        }
                        Text("现在").tag("now")
                        if !events.isEmpty || reminder.anchor == .event { Text("保养记录").tag("event") }
                        if !installations.isEmpty || reminder.anchor == .installation { Text("装配记录").tag("installation") }
                    }.accessibilityIdentifier("reminder-anchor")
                    if reminder.anchor == .event {
                        let labels = readEventChoiceLabels()
                        Picker("记录", selection: $reminder.anchorID) { Text("请选择").tag(""); ForEach(events) { e in Text(labels[e.id] ?? eventTitle(e)).tag(e.id) } }
                            .accessibilityIdentifier("reminder-event")
                    }
                    if reminder.anchor == .installation {
                        let labels = readInstallationChoiceLabels()
                        Picker("装配", selection: $reminder.anchorID) { Text("请选择").tag(""); ForEach(installations) { e in Text(labels[e.id] ?? "").tag(e.id) } }
                            .accessibilityIdentifier("reminder-installation")
                    }
                }.listRowBackground(NativeAppearance.surface)
            }
            Section {
                Toggle("重复提醒", isOn: $reminder.repeats)
                if reminder.repeats && reminder.mode == .date {
                    HStack {
                        Text("每隔")
                        Spacer(minLength: 12)
                        TextField("天数", value: $reminder.days, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                            .frame(minWidth: 60, maxWidth: 160).focused($focusedField, equals: .interval)
                            .accessibilityLabel("重复间隔，天").accessibilityIdentifier("reminder-repeat-days")
                        Text("天").foregroundStyle(NativeAppearance.secondaryText)
                    }
                }
            }.listRowBackground(NativeAppearance.surface)
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
        }
        .disabled(saving || store.readOnly)
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(existingID.isEmpty ? "添加提醒" : "编辑提醒").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { focusedField = nil; if hasChanges { discarding = true } else { dismiss() } }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "保存中…" : "保存", action: saveReminder)
                    .disabled(saving || store.readOnly || reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }.accessibilityIdentifier("reminder-dismiss-keyboard")
            }
        }
        .interactiveDismissDisabled(saving || hasChanges)
        .alert("放弃未保存的更改？", isPresented: $discarding) {
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .onChange(of: reminder.repeats) { _, value in if value && reminder.mode == .date && reminder.days == 0 { reminder.days = 30 } }
        .task {
            guard baseline == nil else { return }
            if let saved = store.reminders.first(where: { $0.id == existingID }) { reminder = saved }
            else if let event = events.first(where: { $0.id == eventID }) { reminder.anchor = .event; reminder.anchorID = event.id; reminder.title = eventTitle(event); reminder.repeats = true }
            baseline = reminder
        }
    }
    private func readEventChoiceLabels() -> [String: String] {
        let choices = events.map { event in
            let time = event["occurredTime"].text
            let date = event["occurredDate"].text + (time.isEmpty ? "" : " " + time)
            return (event: event, title: eventTitle(event) + " · " + date)
        }
        let counts = Dictionary(grouping: choices, by: \.title).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: choices.map { choice in
            let notes = choice.event["notes"].text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let title = counts[choice.title, default: 0] > 1 && !notes.isEmpty ? choice.title + " · " + notes : choice.title
            return (choice.event.id, title)
        })
    }
    private func readInstallationChoiceLabels() -> [String: String] {
        let rows = installations
        let counts = Dictionary(grouping: rows, by: { String($0["at"].text.prefix(10)) }).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: rows.map { installation in
            let at = installation["at"].text
            let day = String(at.prefix(10))
            let date = counts[day, default: 0] > 1 ? String(at.prefix(19)).replacingOccurrences(of: "T", with: " ") : day
            return (installation.id, store.displayName(installation["parentId"].text) + " · " + date)
        })
    }
    private func bindAnchor() -> Binding<String> {
        Binding(get: { reminder.anchor == .now && reminder.eventKind != nil ? "follow-event" : reminder.anchor.rawValue }, set: { value in
            guard let next = GearReminder.Anchor(rawValue: value), next != reminder.anchor || (next == .now && reminder.eventKind != nil) else { return }
            reminder.anchor = next
            reminder.anchorID = ""
            reminder.eventKind = nil
            reminder.eventCustomName = nil
            if next == .now { reminder.startedAt = Date() }
        })
    }
    private func saveReminder() {
        guard !saving, !store.readOnly else { return }
        focusedField = nil
        do {
            let old = store.reminders.first { $0.id == existingID }
            let next = reminder.prepareEdit(replacing: old)
            try store.saveReminder(next)
            reminder = next
            saving = true
            Task { await NativeNotifications.shared.authorize(); store.refreshNotifications(); dismiss() }
        } catch let failure { error = failure.userFacingMessage }
    }
}
