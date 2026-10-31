import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeReminderOverview: View {
    @EnvironmentObject private var store: NativeStore
    @State private var search = ""
    @State private var choosingGear = false
    @State private var selectedGear: String?
    @State private var editor: NativeEditorRoute?
    @State private var now = Date()

    private struct Entry: Identifiable {
        let reminder: GearReminder
        let occurrence: ReminderOccurrence
        let group: ReminderOccurrence.Group
        var id: String { reminder.id }
    }
    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var entries: [Entry] {
        let terms = searchTerm.split(whereSeparator: \.isWhitespace).map(String.init)
        return store.reminders.compactMap { reminder in
            let content = [reminder.title, store.displayName(reminder.gearID)]
            guard terms.allSatisfy({ term in content.contains { $0.localizedStandardContains(term) } }) else { return nil }
            let occurrence = store.reminderOccurrence(reminder, now: now)
            return Entry(reminder: reminder, occurrence: occurrence, group: occurrence.readGroup(for: reminder, now: now))
        }.sorted { lhs, rhs in
            let leftDate = lhs.occurrence.fireDate ?? .distantFuture
            let rightDate = rhs.occurrence.fireDate ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            let comparison = lhs.reminder.title.localizedStandardCompare(rhs.reminder.title)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    var body: some View {
        let rows = entries
        List {
            ForEach(ReminderOccurrence.Group.allCases, id: \.rawValue) { group in
                let members = rows.filter { $0.group == group }
                if !members.isEmpty {
                    Section {
                        ForEach(members) { entry in
                            NavigationLink { NativeReminderDetail(id: entry.id) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(store.displayName(entry.reminder.gearID))
                                        .font(.caption).foregroundStyle(NativeAppearance.accent)
                                        .fixedSize(horizontal: false, vertical: true)
                                    NativeReminderSummary(reminder: entry.reminder, occurrence: entry.occurrence, showsDueStatus: false)
                                }.padding(.top, 8)
                            }
                            .accessibilityIdentifier("reminder-overview-" + entry.id)
                            .listRowBackground(NativeAppearance.surface)
                        }
                    } header: {
                        HStack {
                            Text(readTitle(group))
                            Spacer()
                            Text("\(members.count)").monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(searchTerm.isEmpty ? "暂无提醒" : "没有匹配的提醒", systemImage: searchTerm.isEmpty ? "bell" : "magnifyingglass")
                } actions: {
                    if !searchTerm.isEmpty {
                        Button("清除搜索") { search = "" }.accessibilityIdentifier("reminders-clear-search")
                    } else if !store.readOnly {
                        Button("添加提醒") { choosingGear = true }.accessibilityIdentifier("reminders-empty-add")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .listSectionSpacing(18)
        .navigationTitle("提醒").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "提醒或装备").scrollDismissesKeyboard(.interactively)
        .toolbar {
            if !store.readOnly {
                Button { choosingGear = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加提醒").accessibilityIdentifier("reminders-add")
            }
        }
        .sheet(isPresented: $choosingGear, onDismiss: {
            if let selectedGear { editor = .init(kind: "reminder", parent: selectedGear); self.selectedGear = nil }
        }) {
            NavigationStack {
                NativeReminderGearPicker { id in selectedGear = id; choosingGear = false }
            }
        }
        .sheet(item: $editor) { NativeEditor(route: $0) }
        .onChange(of: store.viewGeneration) { _, _ in now = Date() }
        .task {
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    private func readTitle(_ group: ReminderOccurrence.Group) -> String {
        switch group {
        case .due: "待处理"
        case .needsReview: "需要检查"
        case .upcoming: "未到期"
        case .snoozed: "稍后提醒"
        case .inactive: "已暂停或完成"
        }
    }
}

private struct NativeReminderGearPicker: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let select: (String) -> Void
    private var gears: [Value] {
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return store.gears.filter { gear in
            gear["deletedAt"].isNull && store.status(gear.id) != "retired"
                && terms.allSatisfy { store.displayName(gear.id).localizedStandardContains($0) }
        }.sorted { store.displayName($0.id).localizedStandardCompare(store.displayName($1.id)) == .orderedAscending }
    }
    var body: some View {
        List(gears) { gear in
            Button { select(gear.id) } label: {
                HStack(spacing: 12) {
                    NativeGearThumbnail(gearID: gear.id, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayName(gear.id)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        Text(store.categoryName(gear["categoryId"].text)).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                    }
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("reminder-choose-gear-" + gear.id)
                .listRowBackground(NativeAppearance.surface)
        }
        .overlay {
            if gears.isEmpty {
                ContentUnavailableView(search.isEmpty ? "暂无可选装备" : "没有匹配的装备", systemImage: search.isEmpty ? "bicycle" : "magnifyingglass")
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("选择装备").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "查找装备").scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}
