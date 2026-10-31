import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeGearTimeline: View {
    @EnvironmentObject private var store: NativeStore
    let gearID: String
    @State private var rows: [Value] = []
    @State private var generation = -1
    @State private var search = ""

    private struct TimelineMonth: Identifiable {
        let id: String
        var rows: [Value]
    }
    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var months: [TimelineMonth] {
        let terms = searchTerm.split(whereSeparator: \.isWhitespace)
        var groups: [TimelineMonth] = []
        for row in rows {
            if !terms.isEmpty {
                let content = [row["subjectName"].text, describeRecord(row), row["notes"].text, row["at"].text]
                guard terms.allSatisfy({ term in content.contains { $0.localizedStandardContains(String(term)) } }) else { continue }
            }
            let month = String(row["at"].text.prefix(7))
            if groups.last?.id == month { groups[groups.count - 1].rows.append(row) }
            else { groups.append(TimelineMonth(id: month, rows: [row])) }
        }
        return groups
    }

    var body: some View {
        List {
            ForEach(months) { month in
                Section(formatMonth(month.id)) {
                ForEach(month.rows, id: \.timelineID) { row in
                    NavigationLink {
                        NativeGearDetail(id: row["subjectGearId"].text, focusedHistoryID: row.timelineID)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row["entryType"].text == "event" && !row["occurredTime"].isNull
                                 ? row["occurredDate"].text + " " + row["occurredTime"].text
                                 : NativeDate.parseInstant(row["instant"].text).map { NativeDate.format($0, "yyyy-MM-dd HH:mm XXXXX") }
                                   ?? (String(row["at"].text.prefix(10)) + (["installation", "operation"].contains(row["entryType"].text) ? " · 全天" : "")))
                                .font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                            Text(describeRecord(row)).font(.body.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(row["subjectName"].text).font(.subheadline).foregroundStyle(NativeAppearance.accent)
                                .fixedSize(horizontal: false, vertical: true)
                            if row["entryType"].text == "event", !row["notes"].text.isEmpty {
                                Text(row["notes"].text).font(.subheadline).foregroundStyle(NativeAppearance.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("timeline-record-" + row.timelineID)
                        .listRowBackground(NativeAppearance.surface)
                }
                }
            }
        }
        .overlay {
            if months.isEmpty {
                ContentUnavailableView {
                    Label(searchTerm.isEmpty ? "暂无记录" : "没有匹配的记录", systemImage: searchTerm.isEmpty ? "clock" : "magnifyingglass")
                } actions: {
                    if !searchTerm.isEmpty { Button("清除搜索") { search = "" }.accessibilityIdentifier("timeline-clear-search") }
                }
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas).listSectionSpacing(14)
        .searchable(text: $search, prompt: "装备、记录或日期").scrollDismissesKeyboard(.interactively)
        .navigationTitle("时间线").navigationBarTitleDisplayMode(.inline)
        .task { loadRows() }
        .onChange(of: store.viewGeneration) { _, _ in loadRows() }
    }

    private func describeRecord(_ row: Value) -> String {
        describeGearRecord(row, name: store.name)
    }

    private func formatMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let number = Int(parts[1]), (1...12).contains(number) else { return "日期未知" }
        return String(parts[0]) + "年\(number)月"
    }

    private func loadRows() {
        guard generation != store.viewGeneration else { return }
        rows = GearTimeline.buildRows(state: store.view, gearID: gearID)
        generation = store.viewGeneration
    }
}

func describeGearRecord(_ row: Value, name: (String) -> String) -> String {
    switch row["entryType"].text {
    case "event": return eventTitle(row)
    case "purchase": return "购买"
    case "status": return row["status"].text == "stock" ? "放入库存" : row["status"].text == "retired" ? "退役" : "取出使用"
    case "operation":
        switch row["kind"].text {
        case "replace": return "更换：" + name(row["gearId"].text) + " → " + name(row["replacementId"].text)
        case "store": return row["parentId"].isNull ? "放入库存" : "拆下并入库"
        case "activate": return "取出使用"
        default: return "装到 " + name(row["parentId"].text)
        }
    default: return row["parentId"].isNull ? "拆下" : "装到 " + name(row["parentId"].text)
    }
}
