import SwiftUI
import Observation
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeGearFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func gearDropFrame(_ id: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: NativeGearFrames.self, value: [id: geometry.frame(in: .global)])
        })
    }
}

struct NativeGearDragHandle: View {
    let ids: [String]
    let name: String
    let changed: ([String], CGPoint) -> Void
    let ended: ([String], CGPoint) -> Void
    let cancelled: () -> Void
    let activate: () -> Void
    @GestureState private var dragging = false
    var body: some View {
        Button(action: activate) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(dragging ? Color.accentColor : NativeAppearance.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("调整" + name + "的所属装备")
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged {
                        changed(ids, $0.location)
                    }
                    .onEnded {
                        ended(ids, $0.location)
                    }
            )
            .onChange(of: dragging) { wasDragging, isDragging in
                if wasDragging && !isDragging { cancelled() }
            }
    }
}

@Observable
final class NativeTreeDragState {
    var point: CGPoint?
    var payload: GearTreeDrag?
    var target: String?
    var label = ""
    var viewport: CGRect = .zero
    #if DEBUG
    @ObservationIgnored var treeBuilds = 0
    @ObservationIgnored var startBuilds = 0
    @ObservationIgnored var inputEvents = 0
    #endif
    @ObservationIgnored var frames: [String: CGRect] = [:]
}

struct NativeTreeDragPreview: View {
    let drag: NativeTreeDragState
    var body: some View {
        if drag.payload != nil, let point = drag.point {
            Text(drag.label)
                .font(.headline).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .position(x: min(max(point.x - drag.viewport.minX - 65, 90), max(90, drag.viewport.width - 90)),
                          y: max(30, point.y - drag.viewport.minY - 38))
                .allowsHitTesting(false)
        }
    }
}
