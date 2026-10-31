import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeMoveReview: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let changes: [Value]
    let complete: () -> Void
    @State private var mode = "move"
    @State private var at = Date()
    @State private var precise = false
    @State private var preview: Value = .null
    @State private var message: String?
    private var stalePreview: Bool { !preview.isNull && preview["revision"] != store.revision }
    private var canSave: Bool {
        !store.readOnly && !changes.isEmpty
            && (mode == "move" || (!preview.isNull && !stalePreview && preview["changed"].integer > 0))
    }
    var body: some View {
        NavigationStack {
            Form {
                if changes.isEmpty {
                    ContentUnavailableView("没有待保存的修改", systemImage: "checkmark.circle")
                        .listRowBackground(Color.clear).accessibilityIdentifier("gear-moves-empty")
                } else {
                    Section {
                        Picker("操作", selection: $mode) { Text("变更装配").tag("move"); Text("整理层级").tag("organize") }
                            .accessibilityIdentifier("gear-moves-mode")
                        ForEach(changes, id: \.gearID) { change in renderChange(change) }
                    }.listRowBackground(NativeAppearance.surface)
                    if mode == "move" {
                        Section {
                            DatePicker("生效日期", selection: $at, in: ...Date(), displayedComponents: .date).accessibilityIdentifier("gear-moves-date")
                            Toggle("记录具体时间", isOn: $precise).accessibilityIdentifier("gear-moves-precise")
                            if precise {
                                DatePicker("生效时间", selection: $at, in: ...Date(), displayedComponents: .hourAndMinute).accessibilityIdentifier("gear-moves-time")
                                LabeledContent("时区", value: "上海时间 " + NativeDate.format(at, "XXXXX"))
                            }
                        }
                            .listRowBackground(NativeAppearance.surface)
                    } else if stalePreview {
                        Section {
                            Label("数据已更新，请重新预览。", systemImage: "arrow.triangle.2.circlepath")
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("gear-moves-stale")
                            Button("重新预览", action: loadPreview).accessibilityIdentifier("gear-moves-preview")
                        }.listRowBackground(NativeAppearance.surface)
                    } else if preview.isNull {
                        Section { Button("预览影响时段", action: loadPreview).accessibilityIdentifier("gear-moves-preview") }
                            .listRowBackground(NativeAppearance.surface)
                    } else {
                        Section("影响时段") {
                            if preview["changed"].integer == 0 {
                                Label("没有可整理的共同装配时段", systemImage: "minus.circle")
                                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("gear-moves-no-changes")
                            } else {
                                LabeledContent("将整理的装备", value: "\(preview["changed"].integer) 件")
                                    .accessibilityIdentifier("gear-moves-change-count")
                            }
                            ForEach(preview["rows"].array, id: \.gearID) { renderRanges($0) }
                        }
                        .listRowBackground(NativeAppearance.surface)
                    }
                }
                if let message { Section { Text(message).foregroundStyle(NativeAppearance.dangerText) }.listRowBackground(NativeAppearance.surface) }
            }
            .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
            .labeledContentStyle(NativeReadableValueStyle())
            .navigationTitle("保存修改").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == "move" ? "保存装配" : "应用整理", action: saveChanges)
                        .accessibilityIdentifier("gear-moves-save").disabled(!canSave)
                }
            }
            .onChange(of: mode) { _, _ in preview = .null; message = nil }
        }
    }
    private func renderChange(_ change: Value) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.displayName(change["gearId"].text)).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            LabeledContent("原所属装备", value: readParentName(change["fromParentId"].text))
            LabeledContent("新所属装备", value: readParentName(change["parentId"].text))
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
            .accessibilityIdentifier("gear-moves-change-" + change["gearId"].text)
    }
    private func renderRanges(_ row: Value) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.displayName(row["gearId"].text)).font(.body.weight(.semibold))
            if !row["ranges"].array.isEmpty {
                Text("将调整的时段").font(.subheadline.weight(.medium))
                ForEach(Array(row["ranges"].array.enumerated()), id: \.offset) { _, range in
                    Text(describeRange(range)).font(.subheadline).monospacedDigit()
                }
            } else { Text("装配关系保持不变").font(.subheadline).foregroundStyle(NativeAppearance.secondaryText) }
            if !row["unchangedRanges"].array.isEmpty {
                DisclosureGroup("保持原装配的时段") {
                    ForEach(Array(row["unchangedRanges"].array.enumerated()), id: \.offset) { _, range in
                        Text(describeRange(range)).font(.subheadline).monospacedDigit()
                    }
                }.accessibilityIdentifier("gear-moves-unchanged-" + row["gearId"].text)
            }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 5)
            .accessibilityIdentifier("gear-moves-ranges-" + row["gearId"].text)
    }
    private func readParentName(_ id: String) -> String {
        id.isEmpty ? "顶层装备" : store.displayName(id)
    }
    private func describeRange(_ range: Value) -> String {
        let from = range["fromInstant"].isNull ? NativeDate.format(NativeDate.parse(range["from"].text), "yyyy/M/d") + " 全天" : NativeDate.format(NativeDate.parseInstant(range["fromInstant"].text) ?? NativeDate.parse(range["from"].text), "yyyy/M/d HH:mm XXXXX")
        guard !range["to"].isNull else { return from + " 起 · 持续中" }
        let to = range["toInstant"].isNull ? NativeDate.format(NativeDate.parse(range["to"].text), "yyyy/M/d") + " 全天" : NativeDate.format(NativeDate.parseInstant(range["toInstant"].text) ?? NativeDate.parse(range["to"].text), "yyyy/M/d HH:mm XXXXX")
        return from + " 起，至 " + to + " 前"
    }
    private func loadPreview() {
        do { preview = try store.query("organize-preview", ["changes": .array(changes)]); message = nil }
        catch { preview = .null; message = error.userFacingMessage }
    }
    private func saveChanges() {
        guard canSave else { return }
        do {
            if mode == "move" {
                var input: Value = ["changes": .array(changes), "at": .string(NativeDate.format(at, "yyyy-MM-dd"))]
                if precise { input["instant"] = .string(NativeDate.instant(at)) }
                try store.commit("moves", input)
            }
            else { try store.commit("organize", ["changes": .array(changes), "revision": preview["revision"]]) }
            complete(); dismiss()
        } catch { message = error.userFacingMessage }
    }
}
