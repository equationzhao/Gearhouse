import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct EditorButtons: ToolbarContent {
    @Environment(\.dismiss) private var dismiss
    var disabled = false
    let save: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(disabled) }
    }
}
