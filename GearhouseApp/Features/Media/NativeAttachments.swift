import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import ImageIO
import CryptoKit
#if canImport(GearhouseCore)
import GearhouseCore
#endif

enum NativeAttachmentFiles {
    struct Prepared: Sendable { let name: String; let contentType: String; let data: Data }

    static func prepare(_ url: URL, beforePreparing: (@Sendable () async throws -> Void)? = nil) async throws -> Prepared {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try await beforePreparing?()
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var result: Result<Data, Error>?, coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { source in
                result = Result {
                    try Task.checkCancellation()
                    guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= GearAttachment.maximumBytes else { throw DomainError("附件不能超过 20 MB。") }
                    return try Data(contentsOf: source)
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw DomainError("无法读取附件，请重新选择文件。") }
            let bytes = try result.get()
            try Task.checkCancellation()
            guard !bytes.isEmpty, bytes.count <= GearAttachment.maximumBytes else { throw DomainError("附件不能超过 20 MB。") }
            let originalName = url.lastPathComponent
            guard originalName.count <= 240 else { throw DomainError("文件名过长，请重命名后重试。") }
            if bytes.starts(with: Data("%PDF-".utf8)) {
                guard let document = PDFDocument(data: bytes), !document.isLocked, document.pageCount > 0 else { throw DomainError("无法打开 PDF，请选择可正常阅读的文件。") }
                try Task.checkCancellation()
                return Prepared(name: originalName, contentType: "application/pdf", data: bytes)
            }
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2560
                  ] as CFDictionary), let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw DomainError("请选择 PDF 或图片。") }
            try Task.checkCancellation()
            return Prepared(name: url.deletingPathExtension().lastPathComponent + ".jpg", contentType: "image/jpeg", data: data)
        }
        return try await withTaskCancellationHandler {
            let prepared = try await task.value
            try Task.checkCancellation()
            return prepared
        } onCancel: { task.cancel() }
    }

    static func prepareShare(_ source: URL, name: String, afterCopying: (@Sendable (URL) async throws -> Void)? = nil) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseShare-" + UUID().uuidString)
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let leaf = URL(fileURLWithPath: name).lastPathComponent
            let target = folder.appendingPathComponent(leaf.isEmpty || leaf == "." || leaf == ".." ? source.lastPathComponent : leaf)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: source, to: target)
            try await afterCopying?(target)
            try Task.checkCancellation()
            return target
        }
        do {
            return try await withTaskCancellationHandler {
                let target = try await task.value
                try Task.checkCancellation()
                return target
            } onCancel: { task.cancel() }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

struct NativeAttachmentSection: View {
    @EnvironmentObject var store: NativeStore
    let gearID: String
    var readOnly = false
    @Binding var importing: Bool
    @Binding var loading: Bool
    @Binding var preview: Value?
    @State private var deleting: Value?
    private var attachments: [Value] { store.view["attachments"].array.filter { $0["gearId"].text == gearID } }

    var body: some View {
        if !attachments.isEmpty || !readOnly {
            Section("附件") {
                ForEach(attachments) { record in
                    Button {
                        do {
                            let url = try store.attachmentURL(record)
                            guard FileManager.default.fileExists(atPath: url.path) else { throw DomainError("找不到附件，请从完整备份恢复或重新添加。") }
                            preview = record
                        } catch { store.error = error.userFacingMessage }
                    } label: {
                        HStack {
                            Image(systemName: record["contentType"].text == "application/pdf" ? "doc.richtext" : "photo").foregroundStyle(NativeAppearance.secondaryText)
                            VStack(alignment: .leading) {
                                Text(record["name"].text).foregroundStyle(.primary).lineLimit(2)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(record["bytes"].integer), countStyle: .file)).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                            }
                        }
                    }
                    .swipeActions { if !readOnly { Button("删除", role: .destructive) { deleting = record } } }
                    .contextMenu { if !readOnly { Button("删除附件", role: .destructive) { deleting = record } } }
                }
                if !readOnly {
                    HStack {
                        Button("添加附件", systemImage: "paperclip") { importing = true }.disabled(loading).accessibilityIdentifier("gear-add-attachment")
                        if loading { Spacer(); ProgressView() }
                    }
                }
            }
            .confirmationDialog("删除附件？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { record in
                Button("删除", role: .destructive) { store.perform("attachment-delete", ["id": record["id"], "confirmed": true]); deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { record in Text("将删除「\(record["name"].text)」。") }
        }
    }
}

struct NativeAttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let name: String
    @State private var sharingURL: URL?
    @State private var failure: String?
    @State private var shareGeneration = 0
    var body: some View {
        NavigationStack {
            NativeAttachmentDocument(url: url).ignoresSafeArea(.container, edges: .bottom)
                .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let sharingURL { ShareLink(item: sharingURL) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享附件") }
                    }
                }
                .task {
                    guard sharingURL == nil else { return }
                    let generation = shareGeneration
                    do {
                        let target = try await NativeAttachmentFiles.prepareShare(url, name: name)
                        guard !Task.isCancelled, generation == shareGeneration else {
                            try? FileManager.default.removeItem(at: target.deletingLastPathComponent())
                            return
                        }
                        sharingURL = target
                    } catch {
                        if !Task.isCancelled && !(error is CancellationError) && generation == shareGeneration { failure = error.userFacingMessage }
                    }
                }
                .onDisappear {
                    shareGeneration += 1
                    if let sharingURL { try? FileManager.default.removeItem(at: sharingURL.deletingLastPathComponent()) }
                    sharingURL = nil
                }
                .alert("无法分享附件", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("好", role: .cancel) {} } message: { Text(failure ?? "") }
        }
    }
}

struct NativeAttachmentDocument: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .systemBackground
        if url.pathExtension.lowercased() == "pdf" { view.document = PDFDocument(url: url) }
        else if let image = UIImage(contentsOfFile: url.path), let page = PDFPage(image: image) {
            let document = PDFDocument(); document.insert(page, at: 0); view.document = document
        }
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
