import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeEventForm: View {
    private enum Field: Hashable { case name, notes }
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let gearID: String
    let existing: Value
    @State private var kind: String
    @State private var custom: String
    @State private var date: Date
    @State private var time: Date
    @State private var hasTime: Bool
    @State private var notes: String
    @State private var draft = UUID().uuidString.lowercased()
    @State private var selectedPhotos: [String]
    @State private var photoPreview: NativePhotoPreviewRoute?
    @State private var uploading = false
    @State private var error: String?
    @State private var loadedPhotos = false
    @State private var initialDraft: Value?
    @State private var confirmingDiscard = false
    @State private var editedName = false
    @FocusState private var focusedField: Field?
    init(gearID: String, existing: Value) {
        self.gearID = gearID; self.existing = existing
        _kind = State(initialValue: existing["kind"].text.isEmpty ? "maintenance" : existing["kind"].text)
        _custom = State(initialValue: existing["customName"].text)
        _date = State(initialValue: NativeDate.parse(existing["occurredDate"].text))
        _time = State(initialValue: NativeDate.parse(existing["occurredDate"].text + "T" + existing["occurredTime"].text))
        _hasTime = State(initialValue: !existing["occurredTime"].isNull)
        _notes = State(initialValue: existing["notes"].text)
        _selectedPhotos = State(initialValue: [])
    }
    private var missingName: Bool { kind == "custom" && custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasChanges: Bool { initialDraft.map { $0 != buildDraft() } ?? false }
    var body: some View {
        Form {
            Section("记录信息") {
                Picker("类型", selection: $kind) { ForEach(nativeEventKinds, id: \.0) { Text($0.1).tag($0.0) } }
                    .accessibilityIdentifier("event-kind")
                if kind == "custom" {
                    TextField("名称", text: $custom)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next).onSubmit { focusedField = .notes }
                        .accessibilityIdentifier("event-name")
                    if editedName && missingName {
                        Text("请输入记录名称").font(.footnote).foregroundStyle(NativeAppearance.dangerText)
                            .accessibilityIdentifier("event-name-error")
                    }
                }
                DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("event-date")
                Toggle("记录时间", isOn: $hasTime).accessibilityIdentifier("event-has-time")
                if hasTime { DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute) }
            }
            Section("备注") {
                TextField("备注", text: $notes, axis: .vertical).lineLimit(4...10)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("event-notes")
            }
            NativeEventPhotos(draft: draft, gearID: gearID, selected: $selectedPhotos, loading: $uploading, preview: $photoPreview)
            if let error { Text(error).foregroundStyle(NativeAppearance.dangerText) }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(existing.id.isEmpty ? "添加记录" : "编辑记录").navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loadedPhotos else { return }
            loadedPhotos = true
            selectedPhotos = store.state["photos"].array.filter { $0["ownerType"].text == "event" && $0["ownerId"].text == existing.id }.map(\.id)
            initialDraft = buildDraft()
        }
        .onChange(of: custom) { _, _ in editedName = true }
        .onChange(of: focusedField) { previous, _ in if previous == .name { editedName = true } }
        .interactiveDismissDisabled(hasChanges || uploading)
        .alert("放弃未保存的更改？", isPresented: $confirmingDiscard) {
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .sheet(item: $photoPreview) { route in NativePhotoGallery(ids: selectedPhotos, initialID: route.id) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: requestCancel).disabled(uploading) }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: saveEvent).disabled(uploading || missingName) }
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil { Spacer(); Button("完成") { focusedField = nil }.accessibilityIdentifier("event-keyboard-done") }
            }
        }
    }
    private func buildEventInput() -> Value {
        var event: Value = ["gearId": .string(gearID), "kind": .string(kind), "customName": .string(custom), "occurredDate": .string(NativeDate.format(date,"yyyy-MM-dd")), "occurredTime": hasTime ? .string(NativeDate.format(time,"HH:mm")) : .null, "notes": .string(notes), "photoIds": .array(selectedPhotos.map(Value.string)), "photoDraftId": .string(draft)]
        if !existing.id.isEmpty { event["id"] = existing["id"] }
        return event
    }
    private func buildDraft() -> Value {
        var event = buildEventInput()
        if kind != "custom" { event["customName"] = .null }
        return event
    }
    private func requestCancel() {
        focusedField = nil
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }
    private func saveEvent() {
        focusedField = nil
        do {
            try store.commit("event-save", ["requestId": .string(UUID().uuidString), "event": buildEventInput()]); dismiss()
        } catch let failure { error = failure.userFacingMessage }
    }
}
