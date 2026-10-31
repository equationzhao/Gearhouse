import SwiftUI
import PhotosUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

final class NativePhotoDataRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Error>?
    private var pendingResult: Result<Data?, Error>?
    private var progress: Progress?
    private var completed = false
    private var cancelled = false

    func installContinuation(_ continuation: CheckedContinuation<Data?, Error>) {
        lock.lock()
        if let result = pendingResult {
            pendingResult = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }
    func installProgress(_ progress: Progress) {
        lock.lock()
        let shouldCancel = cancelled
        if !completed { self.progress = progress }
        lock.unlock()
        if shouldCancel { progress.cancel() }
    }
    func finishRequest(_ result: Result<Data?, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let waiting = continuation
        continuation = nil; progress = nil
        if waiting == nil { pendingResult = result }
        lock.unlock()
        waiting?.resume(with: result)
    }
    func cancelRequest() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true; cancelled = true
        let waiting = continuation, loading = progress
        continuation = nil; progress = nil
        let result: Result<Data?, Error> = .failure(CancellationError())
        if waiting == nil { pendingResult = result }
        lock.unlock()
        // Cancellation may synchronously invoke the provider callback. Never call it under the lock.
        loading?.cancel()
        waiting?.resume(with: result)
    }
}

enum NativePhotoDataLoader {
    typealias Completion = @Sendable (Result<Data?, Error>) -> Void
    static func loadData(from item: PhotosPickerItem) async throws -> Data {
        try await loadData { completion in item.loadTransferable(type: Data.self, completionHandler: completion) }
    }
    static func loadData(start: @Sendable (@escaping Completion) -> Progress) async throws -> Data {
        let request = NativePhotoDataRequest()
        let data: Data? = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                request.installContinuation(continuation)
                guard !Task.isCancelled else { request.cancelRequest(); return }
                let progress = start { request.finishRequest($0) }
                request.installProgress(progress)
            }
        } onCancel: { request.cancelRequest() }
        try Task.checkCancellation()
        guard let data else { throw DomainError("无法读取图片，请重新选择。") }
        return data
    }
}

struct NativePhotoPreviewRoute: Identifiable {
    let id: String
}

struct NativePhotoStrip: View {
    @EnvironmentObject var store: NativeStore
    let owner: String
    let ownerID: String
    @State private var preview: NativePhotoPreviewRoute?
    private var photos: [Value] { store.view["photos"].array.filter { $0["ownerType"].text == owner && $0["ownerId"].text == ownerID } }
    var body: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button { preview = NativePhotoPreviewRoute(id: photo.id) } label: {
                            NativePhotoThumbnail(photoID: photo.id, width: 100, height: 80)
                        }.buttonStyle(.plain).accessibilityLabel("查看第 \(index + 1) 张图片，共 \(photos.count) 张")
                            .accessibilityIdentifier("photo-open-" + photo.id)
                    }
                }
            }.frame(height: 80)
            .sheet(item: $preview) { route in NativePhotoGallery(ids: photos.map(\.id), initialID: route.id) }
        }
    }
}

private struct NativePhotoThumbnail: View {
    @EnvironmentObject private var store: NativeStore
    let photoID: String
    let width: CGFloat
    let height: CGFloat
    @State private var image: UIImage?
    @State private var loaded = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045))
                    .overlay {
                        Image(systemName: loaded ? "photo.badge.exclamationmark" : "photo")
                            .font(.title3).foregroundStyle(NativeAppearance.secondaryText)
                    }
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .task(id: photoID) {
            image = nil; loaded = false
            let result = await NativeImageLoader.shared.loadImage(at: store.photoURL(photoID), pixels: Int(max(width, height) * 3))
            guard !Task.isCancelled else { return }
            image = result; loaded = true
        }
    }
}

struct NativePhotoGallery: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    @State private var selection: String
    init(ids: [String], initialID: String? = nil) {
        self.ids = ids
        _selection = State(initialValue: initialID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first ?? "")
    }
    private var currentIndex: Int { ids.firstIndex(of: selection) ?? 0 }
    var body: some View {
        NavigationStack {
            Group {
                if ids.isEmpty {
                    ContentUnavailableView("暂无图片", systemImage: "photo")
                } else {
                    TabView(selection: $selection) {
                        ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                            NativePhotoPage(photoID: id, position: index + 1, count: ids.count, active: selection == id).tag(id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: ids.count > 1 ? .automatic : .never))
                    .background(.black)
                }
            }
            .navigationTitle(ids.isEmpty ? "图片" : "\(currentIndex + 1) / \(ids.count)").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar).tint(.white)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct NativePhotoPage: View {
    @EnvironmentObject private var store: NativeStore
    let photoID: String
    let position: Int
    let count: Int
    let active: Bool
    @State private var image: UIImage?
    @State private var loaded = false
    @State private var attempt = 0
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    NativeZoomableImage(image: image, accessibilityLabel: "第 \(position) 张图片，共 \(count) 张",
                                        accessibilityIdentifier: "photo-zoom-" + photoID)
                } else if loaded {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.exclamationmark").font(.system(size: 40)).accessibilityHidden(true)
                        Text("无法打开图片").font(.headline)
                        Text("请重新添加图片，或从完整备份恢复。").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                        Button("重试") { attempt += 1 }.buttonStyle(.bordered).tint(.white)
                            .accessibilityIdentifier("photo-retry-" + photoID)
                    }
                    .multilineTextAlignment(.center).foregroundStyle(.white).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("正在载入图片")
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .task(id: "\(photoID):\(active):\(attempt)") {
            image = nil; loaded = false
            guard active else { return }
            let result = await NativeImageLoader.shared.loadImage(at: store.photoURL(photoID), pixels: 2560)
            guard !Task.isCancelled else { return }
            image = result; loaded = true
        }
    }
}

#if DEBUG
struct NativePhotoZoomPreview: View {
    @EnvironmentObject private var store: NativeStore
    @State private var photoIDs: [String] = []
    @State private var failure: String?
    @State private var presenting = false
    var body: some View {
        Color.black.overlay {
            if let failure { Text(failure).padding() }
            else if photoIDs.isEmpty { ProgressView() }
        }
        .sheet(isPresented: $presenting) { NativePhotoGallery(ids: photoIDs) }
        .task {
            guard photoIDs.isEmpty, store.directory.lastPathComponent == "GearhousePreview" else { return }
            do {
                var ids: [String] = []
                for page in 1...2 {
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900), format: format).image { renderer in
                        for row in 0..<4 {
                            for column in 0..<6 {
                                let rect = CGRect(x: column * 200, y: row * 225, width: 200, height: 225)
                                UIColor(hue: CGFloat(page == 1 ? 0.58 : 0.06), saturation: 0.7,
                                        brightness: (row + column).isMultiple(of: 2) ? 0.75 : 0.45, alpha: 1).setFill()
                                renderer.fill(rect)
                                UIColor.white.setStroke()
                                let border = UIBezierPath(rect: rect.insetBy(dx: 2, dy: 2)); border.lineWidth = 4; border.stroke()
                                let label = "\(page)·\(row + 1)\(column + 1)" as NSString
                                label.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 70),
                                           withAttributes: [.font:UIFont.monospacedDigitSystemFont(ofSize: 58, weight: .bold), .foregroundColor:UIColor.white])
                            }
                        }
                    }
                    guard let bytes = image.jpegData(compressionQuality: 0.95) else { throw DomainError("无法创建图片预览。") }
                    ids.append(try store.addImage(bytes, owner: "gear", id: "tarmac"))
                }
                photoIDs = ids
                presenting = true
            } catch { failure = error.userFacingMessage }
        }
    }
}
#endif

struct NativePhotoSection: View {
    @EnvironmentObject var store: NativeStore
    let owner: String
    let ownerID: String
    var gearID = ""
    var readOnly = false
    var body: some View {
        Section {
            NativePhotoStrip(owner: owner, ownerID: ownerID)
            NativePhotoActions(owner: owner, ownerID: ownerID, gearID: gearID, readOnly: readOnly)
        }
    }
}

struct NativePhotoEntry: View {
    var overlaysImage = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "photo")
                .font(.subheadline.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .background {
                    if overlaysImage { Circle().fill(.regularMaterial) }
                }
        }.buttonStyle(.plain)
            .foregroundStyle(overlaysImage ? Color.primary : NativeAppearance.accent)
            .accessibilityLabel("图片").accessibilityIdentifier("gear-photo-actions")
    }
}

struct NativePhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let owner: String
    let ownerID: String
    var gearID = ""
    var body: some View {
        NavigationStack {
            List {
                NativePhotoStrip(owner: owner, ownerID: ownerID)
                NativePhotoActions(owner: owner, ownerID: ownerID, gearID: gearID)
            }
            .navigationTitle("图片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct NativePhotoActions: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let owner: String
    let ownerID: String
    var gearID = ""
    var readOnly = false
    var compact = false
    @State private var selected: [PhotosPickerItem] = []
    @State private var managing = false
    @State private var loading = false
    @State private var failure: String?
    @State private var importID: UUID?
    private var photos: [Value] { store.view["photos"].array.filter { $0["ownerType"].text == owner && $0["ownerId"].text == ownerID } }
    var body: some View {
        if !readOnly {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { renderPhotoControls() }
                } else {
                    HStack(spacing: 18) { renderPhotoControls() }
                }
            }
            .font(compact ? .subheadline : .body)
            .buttonStyle(.borderless)
            .onChange(of: selected) { _, items in
                guard !items.isEmpty else { return }
                let currentImport = UUID()
                let generation = store.imageImportGeneration
                importID = currentImport
                loading = true
                // Finish the chosen batch even if its row or sheet leaves the screen.
                Task {
                    defer {
                        if importID == currentImport { loading = false; selected = []; importID = nil }
                    }
                    do {
                        _ = try await store.importImages(count: items.count, owner: owner, id: ownerID, gearID: gearID, expectedGeneration: generation) { index in
                            try await NativePhotoDataLoader.loadData(from: items[index])
                        }
                    } catch {
                        if !Task.isCancelled && !(error is CancellationError) && importID == currentImport { failure = error.userFacingMessage }
                    }
                }
            }
            .sheet(isPresented: $managing) { NativePhotoManager(owner: owner, ownerID: ownerID) }
            .alert("无法添加图片", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(failure ?? "") }
        }
    }
    @ViewBuilder private func renderPhotoControls() -> some View {
        if compact && !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        PhotosPicker(selection: $selected, maxSelectionCount: max(1, 40 - photos.count), matching: .images) {
            Label(compact && !photos.isEmpty ? "添加" : "添加图片", systemImage: "photo.badge.plus").frame(minHeight: 44)
                .foregroundStyle(loading || photos.count >= 40 ? NativeAppearance.secondaryText : NativeAppearance.accent)
        }.disabled(loading || photos.count >= 40).accessibilityIdentifier("gear-add-photo")
        if !compact && !dynamicTypeSize.isAccessibilitySize { Spacer() }
        if loading { ProgressView().accessibilityLabel("正在添加图片") }
        if !photos.isEmpty {
            Button(compact ? "管理图片" : "管理") { managing = true }.buttonStyle(.borderless)
                .frame(minHeight: 44).accessibilityLabel("管理图片").accessibilityIdentifier("gear-manage-photos")
        }
    }
}
struct NativePhotoManager: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let owner: String
    let ownerID: String
    @State private var deleting: String?
    @State private var failure: String?
    @State private var editMode = EditMode.inactive
    private var photos: [Value] { store.state["photos"].array.filter { $0["ownerType"].text == owner && $0["ownerId"].text == ownerID } }
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    HStack(spacing: 12) {
                        NativePhotoThumbnail(photoID: photo.id, width: 72, height: 60)
                        Spacer(minLength: 0)
                        if owner == "gear" {
                            let isCover = store.readCoverPhotoID(ownerID) == photo.id
                            Button {
                                performPhotoEdit(["action":"cover", "id":photo["id"]])
                            } label: {
                                Image(systemName: isCover ? "star.fill" : "star")
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel(isCover ? "第 \(index + 1) 张图片，当前封面" : "将第 \(index + 1) 张图片设为封面")
                                .accessibilityAddTraits(isCover ? .isSelected : [])
                                .accessibilityIdentifier("gear-photo-cover-" + photo.id)
                        }
                        Button(role: .destructive) { deleting = photo.id } label: { Image(systemName:"trash").frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("删除第 \(index + 1) 张图片")
                            .accessibilityIdentifier("photo-delete-" + photo.id)
                    }.padding(.vertical, 4)
                }.onMove { indexes, target in
                    var ids = photos.map(\.id); ids.move(fromOffsets:indexes,toOffset:target)
                    performPhotoEdit(["action":"reorder", "ids":.array(ids.map(Value.string))])
                }
                if photos.isEmpty { Text("暂无图片").foregroundStyle(NativeAppearance.secondaryText) }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("图片").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? "完成排序" : "排序") {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    }.disabled(photos.count < 2).accessibilityIdentifier("gear-photo-sort")
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("删除这张图片？", isPresented: Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}), titleVisibility:.visible, presenting: deleting) { id in
                Button("删除",role:.destructive) { performPhotoEdit(["action":"delete","id":.string(id),"confirmed":true]); deleting=nil }
            }
            .alert("图片操作未完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(failure ?? "") }
        }
    }
    private func performPhotoEdit(_ input: Value) {
        var request = input; request["ownerType"] = .string(owner); request["ownerId"] = .string(ownerID)
        do { try store.commit("photo-edit", request) }
        catch { failure = error.userFacingMessage }
    }
}
struct NativeEventPhotos: View {
    @EnvironmentObject var store: NativeStore
    let draft: String
    let gearID: String
    @Binding var selected: [String]
    @State private var picking: [PhotosPickerItem] = []
    @Binding var loading: Bool
    @Binding var preview: NativePhotoPreviewRoute?
    @State private var failure: String?
    @State private var importID: UUID?
    @State private var importTask: Task<Void, Never>?
    @State private var stoppingImport = false
    @State private var holdingPreviewImport = false
    var body: some View {
        Section("图片") {
            ForEach(Array(selected.enumerated()), id: \.element) { index, id in
                HStack(spacing: 12) {
                    Button { preview = NativePhotoPreviewRoute(id: id) } label: {
                        NativePhotoThumbnail(photoID: id, width: 90, height: 65)
                    }.buttonStyle(.plain).accessibilityLabel("查看第 \(index + 1) 张图片，共 \(selected.count) 张")
                        .accessibilityIdentifier("event-photo-open-" + id)
                    Spacer(minLength: 0)
                    Button { movePhotoForward(id) } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).disabled(loading || selected.first == id)
                        .accessibilityLabel("将第 \(index + 1) 张图片向前移")
                        .accessibilityIdentifier("event-photo-forward-" + id)
                    Button { removePhoto(id) } label: { Image(systemName:"minus.circle").foregroundStyle(loading ? NativeAppearance.secondaryText : NativeAppearance.dangerText).frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).disabled(loading).accessibilityLabel("移除第 \(index + 1) 张图片")
                        .accessibilityIdentifier("event-photo-remove-" + id)
                }.padding(.vertical, 4)
            }.onMove { indexes,target in selected.move(fromOffsets:indexes,toOffset:target) }
            PhotosPicker(selection:$picking,maxSelectionCount:max(1,40-selected.count),matching:.images) {
                Label("添加图片",systemImage:"photo.badge.plus").frame(minHeight: 44)
                    .foregroundStyle(loading || selected.count >= 40 ? NativeAppearance.secondaryText : NativeAppearance.accent)
            }.disabled(loading || selected.count>=40).accessibilityIdentifier("event-add-photo")
            if loading {
                HStack(spacing: 12) {
                    ProgressView().accessibilityLabel(stoppingImport ? "正在取消添加" : "正在添加图片")
                        .accessibilityIdentifier(holdingPreviewImport ? "event-photo-import-held" : "event-photo-import-progress")
                    Button(stoppingImport ? "正在停止…" : "取消添加") {
                        stoppingImport = true
                        importTask?.cancel()
                    }.frame(minHeight: 44).disabled(stoppingImport).accessibilityIdentifier("event-cancel-photo-import")
                }
            }
        }
        .onChange(of: picking) { _, items in
            guard !items.isEmpty else { return }
            let currentImport = UUID()
            let generation = store.imageImportGeneration
            importID = currentImport
            loading = true; stoppingImport = false; holdingPreviewImport = false
            // The parent editor keeps its save and cancel actions disabled until this finishes.
            importTask = Task {
                defer {
                    if importID == currentImport {
                        loading = false; picking = []; importID = nil; importTask = nil
                        stoppingImport = false; holdingPreviewImport = false
                    }
                }
                do {
                    let ids = try await store.importImages(count: items.count, owner: "draft", id: draft, gearID: gearID, expectedGeneration: generation) { index in
                        #if DEBUG
                        if index == 1, store.directory.lastPathComponent == "GearhousePreview",
                           ProcessInfo.processInfo.arguments.contains("-preview-route"),
                           ProcessInfo.processInfo.arguments.contains("-hold-photo-import") {
                            holdingPreviewImport = true
                            return try await NativePhotoDataLoader.loadData { _ in Progress(totalUnitCount: 1) }
                        }
                        #endif
                        return try await NativePhotoDataLoader.loadData(from: items[index])
                    }
                    selected.append(contentsOf: ids)
                } catch {
                    if !Task.isCancelled && !(error is CancellationError) && importID == currentImport { failure = error.userFacingMessage }
                }
            }
        }
        .alert("图片操作未完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }
    private func movePhotoForward(_ id: String) {
        guard let index = selected.firstIndex(of: id), index > 0 else { return }
        selected.swapAt(index, index - 1)
    }
    private func removePhoto(_ id: String) {
        do {
            if store.state["photos"].array.first(where: { $0.id == id })?["ownerType"].text == "draft" {
                try store.removeDraftImage(photoID: id, draftID: draft, gearID: gearID)
            }
            selected.removeAll { $0 == id }
        } catch { failure = error.userFacingMessage }
    }
}
