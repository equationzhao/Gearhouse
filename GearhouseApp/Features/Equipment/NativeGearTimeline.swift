import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeGearTimeline: View {
    @EnvironmentObject private var store: NativeStore
    let gearID: String
    @State private var rows: [Value] = []
    @State private var generation = -1

    var body: some View {
        List {
            Section(store.name(gearID)) {
                ForEach(rows, id: \.timelineID) { row in
                    NavigationLink {
                        NativeGearDetail(id: row["subjectGearId"].text, focusedHistoryID: row.timelineID)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(row["subjectName"].text).font(.caption).foregroundStyle(.secondary)
                            Text(describeRecord(row))
                            Text(row["entryType"].text == "event" && !row["occurredTime"].isNull
                                 ? row["occurredDate"].text + " " + row["occurredTime"].text
                                 : String(row["at"].text.prefix(10)))
                                .font(.caption).foregroundStyle(.secondary)
                            if row["entryType"].text == "event", !row["notes"].text.isEmpty {
                                Text(row["notes"].text).font(.callout).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("timeline-record-" + row.timelineID)
                }
                if rows.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("时间线").navigationBarTitleDisplayMode(.inline)
        .task { loadRows() }
        .onChange(of: store.viewGeneration) { _, _ in loadRows() }
    }

    private func describeRecord(_ row: Value) -> String {
        describeGearRecord(row, name: store.name)
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
