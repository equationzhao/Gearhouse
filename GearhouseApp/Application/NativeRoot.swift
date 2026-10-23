import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeRoot: View {
    @EnvironmentObject var store: NativeStore
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { NativeTree() }.tabItem { Label("装备", systemImage: "bicycle") }.tag(0)
            NavigationStack { NativeActivities() }.tabItem { Label("活动", systemImage: "waveform.path.ecg") }.tag(1)
            NavigationStack { NativeSync() }.tabItem { Label("同步", systemImage: "arrow.triangle.2.circlepath") }.tag(2)
        }
        .task(id: tab) {
            guard !Task.isCancelled, tab != 0, store.snapshotDate != nil else { return }
            store.snapshotDate = nil
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好", role: .cancel) {} } message: { Text(store.error ?? "") }
    }
}
struct NativeEditorRoute: Identifiable {
    let kind: String
    var item: Value = [:]
    var parent = ""
    var id: String { kind + item.id + parent }
}
struct NativeEditor: View {
    let route: NativeEditorRoute
    var body: some View {
        NavigationStack {
            switch route.kind {
            case "categories": NativeCategories()
            case "gear": NativeGearForm(existing: route.item, parent: route.parent)
            case "stock-new": NativeGearForm(placement: "stock")
            case "inventory-batch": NativeInventoryBatchForm(gearIDs: route.item["gearIds"].array.map(\.text))
            case "inventory": NativeInventoryForm(gearID: route.parent, kind: route.item["kind"].text, operation: route.item["id"].isNull ? [:] : route.item)
            case "gear-copy": NativeGearForm(existing: route.item, copying: true)
            case "component": NativeComponentForm(parent: route.parent)
            case "history": NativeHistoryForm(gearID: route.parent, existing: route.item)
            case "event": NativeEventForm(gearID: route.parent, existing: route.item)
            case "reminder": NativeReminderForm(gearID: route.parent, existingID: route.item.id, eventID: route.item["eventID"].text)
            case "recompute": NativeRecompute(gearID: route.parent)
            default: EmptyView()
            }
        }
    }
}
