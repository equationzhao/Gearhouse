import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeHistoryForm: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    let existing: Value
    @State private var parent: String
    @State private var at: Date
    @State private var precise: Bool
    @State private var error: String?
    @State private var confirmingDiscard = false
    @State private var initialDate: String
    @State private var initialInstant: String?
    init(gearID: String, existing: Value) {
        self.gearID = gearID; self.existing = existing
        let date = NativeDate.parseInstant(existing["instant"].text) ?? NativeDate.parse(existing["at"].text)
        _parent = State(initialValue: existing["parentId"].text); _at = State(initialValue: date)
        _precise = State(initialValue: !existing["instant"].isNull)
        _initialDate = State(initialValue: NativeDate.format(date, "yyyy-MM-dd"))
        _initialInstant = State(initialValue: existing["instant"].isNull ? nil : NativeDate.instant(date))
    }
    private var hasChanges: Bool {
        parent != existing["parentId"].text || NativeDate.format(at, "yyyy-MM-dd") != initialDate || (precise ? NativeDate.instant(at) : nil) != initialInstant
    }
    private var savedInstant: String {
        if let original = NativeDate.parseInstant(existing["instant"].text), original == at { return existing["instant"].text }
        return NativeDate.instant(at)
    }
    var body: some View {
        Form {
            Section {
                LabeledContent("组件", value: store.displayName(gearID))
                Picker("所属装备", selection: $parent) {
                    Text("未装配").tag("")
                    ForEach(store.gears.filter { $0.id != gearID && $0["deletedAt"].isNull }) { Text(store.displayName($0.id)).tag($0.id) }
                }.pickerStyle(.navigationLink).accessibilityIdentifier("installation-parent")
                DatePicker("生效日期", selection: $at, in: ...Date(), displayedComponents: .date).accessibilityIdentifier("installation-date")
                Toggle("记录具体时间", isOn: $precise).accessibilityIdentifier("installation-precise")
                if precise {
                    DatePicker("生效时间", selection: $at, in: ...Date(), displayedComponents: .hourAndMinute).accessibilityIdentifier("installation-time")
                    LabeledContent("时区", value: "上海时间 " + NativeDate.format(at, "XXXXX"))
                }
            }
            if let error { Text(error).foregroundStyle(NativeAppearance.dangerText) }
        }
        .navigationTitle(existing.id.isEmpty ? "添加装配" : "编辑装配").navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasChanges)
        .alert("放弃未保存的更改？", isPresented: $confirmingDiscard) {
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: requestCancel) }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: saveHistory) }
        }
    }
    private func requestCancel() {
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }
    private func saveHistory() {
        do {
            var input: Value = ["gearId": .string(gearID), "parentId": .optional(parent), "at": .string(NativeDate.format(at,"yyyy-MM-dd"))]
            if precise { input["instant"] = .string(savedInstant) }
            if !existing.id.isEmpty { input["id"] = existing["id"] }
            try store.commit("history-save", input); dismiss()
        } catch let failure { error = failure.userFacingMessage }
    }
}
