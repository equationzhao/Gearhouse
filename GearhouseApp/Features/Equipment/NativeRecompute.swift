import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeRecompute: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    var categoryID = ""
    @State private var from = NativeDate.parse("2024-01-01")
    @State private var to = Date()
    @State private var scope = "self"
    @State private var manual = "preserve"
    @State private var preview: Value = .null
    @State private var confirmed = false
    @State private var error: String?
    init(gearID: String, categoryID: String = "", from: String = "2024-01-01", scope: String = "self") {
        self.gearID = gearID
        self.categoryID = categoryID
        _from = State(initialValue: NativeDate.parse(String(from.prefix(10))))
        _scope = State(initialValue: scope)
    }
    private var options: Value {
        var input: Value = ["from": .string(NativeDate.format(from,"yyyy-MM-dd")), "to": .string(NativeDate.format(to,"yyyy-MM-dd")), "scope": .string(categoryID.isEmpty ? scope : "self"), "manual": .string(manual)]
        if categoryID.isEmpty { input["gearId"] = .string(gearID) } else { input["categoryId"] = .string(categoryID) }
        return input
    }
    var body: some View {
        Form {
            Section {
                DatePicker("开始日期", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("结束日期", selection: $to, in: from...Date(), displayedComponents: .date)
                if categoryID.isEmpty { Picker("范围", selection: $scope) { Text("仅此装备").tag("self"); Text("包含组件").tag("subtree") } }
                DisclosureGroup("高级选项") {
                    Picker("手动修改", selection: $manual) { Text("保留").tag("preserve"); Text("重新计算").tag("recalculate") }
                }
                Button("预览") { do { preview = try store.query("recompute-preview", options); confirmed = false; error = nil } catch let failure { error = failure.userFacingMessage } }
            }
            if !preview.isNull {
                Section("预览") {
                    ForEach(preview["totals"].array) { row in
                        VStack(alignment: .leading) {
                            Text(row["name"].text)
                            Text(nativeDistance(row["before"]["distance"]) + " → " + nativeDistance(row["after"]["distance"]))
                            Text("\(row["before"]["count"].integer) → \(row["after"]["count"].integer) 次").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(preview["changed"].integer) 次活动将更新")
                    if preview["totals"].array.contains(where: { $0["baselineDisabled"].flag }) { Toggle("不再计入导入的历史累计值", isOn: $confirmed) }
                    if preview["skipped"].object.values.contains(where: { $0.integer > 0 }) {
                        DisclosureGroup("未重算的活动") {
                            ForEach([("manual","已保留手动修改"),("unavailable","活动信息不完整"),("undatedUnavailable","缺少活动日期"),("missingMain","未指定主装备"),("incompleteMetrics","缺少距离或时长")], id: \.0) { key, title in
                                if preview["skipped"][key].integer > 0 { LabeledContent(title, value: preview["skipped"][key].text) }
                            }
                        }
                    }
                    Button("应用重算") {
                        do { var input = options; input["revision"] = preview["revision"]; input["baselineConfirmed"] = .bool(confirmed); try store.commit("recompute", input); dismiss() }
                        catch let failure { error = failure.userFacingMessage }
                    }.disabled(preview["revision"] != store.revision || (preview["totals"].array.contains { $0["baselineDisabled"].flag } && !confirmed))
                }
                Section("活动变化") {
                    ForEach(preview["rows"].array.filter { ["changed","assembly","distance"].contains($0["status"].text) }) { row in
                        VStack(alignment: .leading) { Text(row["name"].text); Text(row["at"].text.replacingOccurrences(of:"T",with:" ")).font(.caption); if !row["added"].array.isEmpty { Text("＋ " + row["added"].array.map { store.name($0.text) }.joined(separator:"、")) }; if !row["removed"].array.isEmpty { Text("− " + row["removed"].array.map { store.name($0.text) }.joined(separator:"、")) } }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("重算 · " + (categoryID.isEmpty ? store.name(gearID) : store.categoryName(categoryID))).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .onChange(of: options) { _, _ in preview = .null; confirmed = false }
    }
}
