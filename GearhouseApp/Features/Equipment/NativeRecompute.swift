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
    private var stalePreview: Bool { !preview.isNull && preview["revision"] != store.revision }
    private var changesBaseline: Bool { preview["totals"].array.contains { $0["baselineDisabled"].flag } }
    private var changedActivities: [Value] { preview["rows"].array.filter { ["changed", "assembly", "distance"].contains($0["status"].text) } }
    private var canApply: Bool {
        !store.readOnly && !preview.isNull && !stalePreview
            && (preview["changed"].integer > 0 || changesBaseline) && (!changesBaseline || confirmed)
    }
    var body: some View {
        Form {
            Section {
                DatePicker("开始日期", selection: $from, in: ...to, displayedComponents: .date).accessibilityIdentifier("recompute-from")
                DatePicker("结束日期", selection: $to, in: from...Date(), displayedComponents: .date).accessibilityIdentifier("recompute-to")
                if categoryID.isEmpty {
                    Picker("范围", selection: $scope) { Text("仅此装备").tag("self"); Text("包含组件").tag("subtree") }.accessibilityIdentifier("recompute-scope")
                }
                DisclosureGroup("高级选项") {
                    Picker("手动修改", selection: $manual) { Text("保留").tag("preserve"); Text("重新计算").tag("recalculate") }.accessibilityIdentifier("recompute-manual")
                }
                if preview.isNull { previewButton("预览重算") }
            } header: { Text("重算范围") } footer: { Text("含具体装配时间的活动按上海时间筛选，其他活动沿用活动本地日期。") }.listRowBackground(NativeAppearance.surface)
            if stalePreview {
                Section {
                    Label("数据已更新，请重新预览。", systemImage: "arrow.triangle.2.circlepath")
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recompute-stale")
                    previewButton("重新预览")
                }.listRowBackground(NativeAppearance.surface)
            } else if !preview.isNull { previewSections }
            if let error { Section { Text(error).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
        }
        .labeledContentStyle(NativeReadableValueStyle())
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .navigationTitle("重算 · " + (categoryID.isEmpty ? store.displayName(gearID) : store.categoryName(categoryID))).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .onChange(of: options) { _, _ in preview = .null; confirmed = false; error = nil }
        .onChange(of: store.revision) { _, _ in confirmed = false }
    }
    @ViewBuilder private var previewSections: some View {
        Section("预览结果") {
            if preview["changed"].integer == 0 && !changesBaseline {
                Label("无需更新", systemImage: "checkmark.circle").accessibilityIdentifier("recompute-no-changes")
            } else {
                LabeledContent("将更新的活动", value: "\(preview["changed"].integer) 次").accessibilityIdentifier("recompute-change-count")
            }
            ForEach(preview["totals"].array) { renderTotals($0) }
        }.listRowBackground(NativeAppearance.surface)
        if !preview["gaps"].array.isEmpty {
            Section {
                DisclosureGroup("未完成同步的日期") {
                    ForEach(Array(preview["gaps"].array.enumerated()), id: \.offset) { _, gap in
                        Text(gap["from"].text + " – " + gap["to"].text).font(.subheadline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink("同步活动") { NativeSync() }
                }.accessibilityIdentifier("recompute-gaps")
            }.listRowBackground(NativeAppearance.surface)
        }
        if changesBaseline {
            Section {
                Toggle("不再计入导入的历史累计值", isOn: $confirmed).accessibilityIdentifier("recompute-confirm-baseline")
            } footer: { Text("累计数据将只计入本机已有的活动。") }.listRowBackground(NativeAppearance.surface)
        }
        if ["manual", "unavailable", "undatedUnavailable", "timeUnknown"].contains(where: { preview["skipped"][$0].integer > 0 }) {
            Section {
                DisclosureGroup("未重算的活动") {
                    renderCount("已保留手动修改", key: "manual")
                    renderCount("活动信息不完整", key: "unavailable")
                    renderCount("缺少活动日期", key: "undatedUnavailable")
                    renderCount("缺少可靠开始时刻", key: "timeUnknown")
                }.accessibilityIdentifier("recompute-skipped")
            }.listRowBackground(NativeAppearance.surface)
        }
        if ["missingMain", "incompleteMetrics"].contains(where: { preview["skipped"][$0].integer > 0 }) {
            Section {
                DisclosureGroup("活动数据不完整") {
                    renderCount("未指定主装备", key: "missingMain")
                    renderCount("缺少距离或时长", key: "incompleteMetrics")
                }.accessibilityIdentifier("recompute-incomplete")
            }.listRowBackground(NativeAppearance.surface)
        }
        if !changedActivities.isEmpty {
            Section("活动变化") { ForEach(changedActivities) { renderActivity($0) } }.listRowBackground(NativeAppearance.surface)
        } else if preview["rows"].array.isEmpty {
            Section { Text("所选日期内没有可重算的活动。").foregroundStyle(NativeAppearance.secondaryText).accessibilityIdentifier("recompute-no-activities") }.listRowBackground(NativeAppearance.surface)
        }
        if preview["changed"].integer > 0 || changesBaseline {
            Section { Button("应用重算", action: applyPreview).disabled(!canApply).accessibilityIdentifier("recompute-apply") }.listRowBackground(NativeAppearance.surface)
        }
    }
    private func previewButton(_ title: String) -> some View {
        Button(title, action: loadPreview).disabled(store.readOnly).accessibilityIdentifier("recompute-preview")
    }
    private func renderTotals(_ row: Value) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.displayName(row.id).isEmpty ? row["name"].text : store.displayName(row.id)).font(.headline).fixedSize(horizontal: false, vertical: true)
            LabeledContent("累计距离") {
                Text(nativeDistance(row["before"]["distance"]) + " → " + nativeDistance(row["after"]["distance"]))
                    .monospacedDigit().multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("累计时长") {
                Text(nativeDuration(row["before"]["seconds"]) + " → " + nativeDuration(row["after"]["seconds"]))
                    .monospacedDigit().multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("活动次数", value: "\(row["before"]["count"].integer) → \(row["after"]["count"].integer) 次")
            if row["baselineDisabled"].flag { Text("将停用历史累计值").font(.caption).foregroundStyle(NativeAppearance.secondaryText) }
        }.padding(.vertical, 5).accessibilityElement(children: .combine).accessibilityIdentifier("recompute-total-" + row.id)
    }
    @ViewBuilder private func renderCount(_ title: String, key: String) -> some View {
        if preview["skipped"][key].integer > 0 { LabeledContent(title, value: "\(preview["skipped"][key].integer) 次") }
    }
    private func renderActivity(_ row: Value) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(row["name"].text.isEmpty ? "未命名活动" : row["name"].text).font(.body.weight(.medium))
            Text(row["at"].text.replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
            if !row["added"].array.isEmpty {
                Label("加入：" + row["added"].array.map { readGearName($0.text) }.joined(separator: "、"), systemImage: "plus").font(.subheadline)
            }
            if !row["removed"].array.isEmpty {
                Label("移除：" + row["removed"].array.map { readGearName($0.text) }.joined(separator: "、"), systemImage: "minus").font(.subheadline)
            }
            if row["status"].text == "distance" {
                Text("更新距离计入方式").font(.subheadline)
            } else if row["status"].text == "assembly" { Text("更新装配层级").font(.subheadline) }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4).accessibilityElement(children: .combine).accessibilityIdentifier("recompute-activity-" + row.id)
    }
    private func readGearName(_ id: String) -> String {
        let name = store.displayName(id)
        return name.isEmpty ? "已删除的装备" : name
    }
    private func loadPreview() {
        confirmed = false
        do { preview = try store.query("recompute-preview", options); error = nil }
        catch { preview = .null; self.error = error.userFacingMessage }
    }
    private func applyPreview() {
        guard canApply else { return }
        do {
            var input = options; input["revision"] = preview["revision"]; input["baselineConfirmed"] = .bool(confirmed)
            try store.commit("recompute", input); dismiss()
        } catch { self.error = error.userFacingMessage }
    }
}
