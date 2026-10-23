import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeEventForm: View {
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
    @State private var uploading = false
    @State private var error: String?
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
    var body: some View {
        Form {
            Section {
                Picker("记录", selection: $kind) { ForEach(nativeEventKinds, id: \.0) { Text($0.1).tag($0.0) } }
                if kind == "custom" { TextField("名称", text: $custom) }
                DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                Toggle("时刻", isOn: $hasTime)
                if hasTime { DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute) }
                TextField("备注", text: $notes, axis: .vertical).lineLimit(4...10)
            }
            NativeEventPhotos(draft: draft, gearID: gearID, selected: $selectedPhotos, loading: $uploading)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(existing.id.isEmpty ? "添加记录" : "编辑记录").navigationBarTitleDisplayMode(.inline)
        .task { selectedPhotos = store.state["photos"].array.filter { $0["ownerType"].text == "event" && $0["ownerId"].text == existing.id }.map(\.id) }
        .toolbar { EditorButtons(disabled: uploading || (kind == "custom" && custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) {
            do {
                var event: Value = ["gearId": .string(gearID), "kind": .string(kind), "customName": .string(custom), "occurredDate": .string(NativeDate.format(date,"yyyy-MM-dd")), "occurredTime": hasTime ? .string(NativeDate.format(time,"HH:mm")) : .null, "notes": .string(notes), "photoIds": .array(selectedPhotos.map(Value.string)), "photoDraftId": .string(draft)]
                if !existing.id.isEmpty { event["id"] = existing["id"] }
                try store.commit("event-save", ["requestId": .string(UUID().uuidString), "event": event]); dismiss()
            } catch let failure { error = failure.userFacingMessage }
        } }
    }
}
