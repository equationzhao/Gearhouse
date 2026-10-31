import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

extension NativeStore {
    func readCoverPhotoID(_ gearID: String) -> String {
        let selected = gear(gearID)["coverPhotoId"].text
        if !selected.isEmpty { return selected }
        return firstGearPhotoIDs[gearID] ?? ""
    }
}

struct NativeGearThumbnail: View {
    @EnvironmentObject private var store: NativeStore
    let gearID: String
    var size: CGFloat = 38
    @State private var image: UIImage?
    private var photoID: String { store.readCoverPhotoID(gearID) }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035))
                    .overlay { Image(systemName: nativeIcon(store.gear(gearID)["type"].text)).font(.system(size: size * 0.40, weight: .regular)).foregroundStyle(NativeAppearance.secondaryText) }
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size > 60 ? 18 : 11, style: .continuous))
        .accessibilityHidden(true)
        .task(id: photoID + ":" + String(Int(size))) {
            image = nil
            guard !photoID.isEmpty else { return }
            let loaded = await NativeImageLoader.shared.loadImage(at: store.photoURL(photoID), pixels: Int(size * 3))
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct NativeEquipmentSummary: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let gear: Value
    var pending = false
    var isEditing = false
    var body: some View {
        let metrics = store.view["statistics"][gear.id]
        Group {
            if dynamicTypeSize >= .accessibility4 && !isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    NativeGearThumbnail(gearID: gear.id, size: 60)
                    renderSummaryDetails(metrics).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 14) {
                    if !isEditing { NativeGearThumbnail(gearID: gear.id, size: 60) }
                    renderSummaryDetails(metrics)
                    Spacer(minLength: 0)
                }
            }
        }.padding(.vertical, 3).contentShape(Rectangle())
    }
    private func renderSummaryDetails(_ metrics: Value) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.displayName(gear.id)).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(isEditing || dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if pending { Text("未保存").font(.caption.weight(.medium)).foregroundStyle(NativeAppearance.warningText) }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        NativeDistanceMetric(meters: metrics["distance"].isNull ? nil : metrics["distance"].double)
                        Text(nativeDuration(metrics["seconds"])).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        NativeDistanceMetric(meters: metrics["distance"].isNull ? nil : metrics["distance"].double)
                        Text(nativeDuration(metrics["seconds"])).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                    }
                }
            }
        }
    }
}

struct NativeGearHero: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let gearID: String
    var readOnly = false
    let openActivities: () -> Void
    @State private var image: UIImage?
    @State private var galleryOpen = false
    @State private var photoActionsOpen = false
    private var gear: Value { store.gear(gearID) }
    private var photoID: String { store.readCoverPhotoID(gearID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let image {
                ZStack(alignment: .bottomTrailing) {
                    GeometryReader { geometry in
                        Button { galleryOpen = true } label: {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: 148).clipped()
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("查看装备图片").accessibilityIdentifier("gear-cover-photo")
                    }.frame(height: 148)
                    if !readOnly {
                        NativePhotoEntry(overlaysImage: true) { photoActionsOpen = true }
                            .padding(10)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(store.categoryName(for: gear)).font(.subheadline).foregroundStyle(NativeAppearance.secondaryText)
                    if store.status(gearID) != "active" { NativeStatusBadge(status: store.status(gearID)) }
                    if store.conditionName(gear) == "未使用" { Text("未使用").font(.caption).foregroundStyle(NativeAppearance.secondaryText) }
                    Spacer(minLength: 0)
                    if image == nil && !readOnly {
                        NativePhotoEntry { photoActionsOpen = true }
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 18) { renderMetrics() }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 18) { renderMetrics() }
                            .fixedSize(horizontal: true, vertical: true)
                        VStack(alignment: .leading, spacing: 16) {
                            renderDistanceMetric()
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 24) { renderSecondaryMetrics() }
                                    .fixedSize(horizontal: true, vertical: true)
                                VStack(alignment: .leading, spacing: 16) { renderSecondaryMetrics() }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !gear["notes"].text.isEmpty {
                    Text(gear["notes"].text).font(.subheadline).foregroundStyle(NativeAppearance.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, image == nil ? 14 : 0)
        }
        .task(id: photoID) {
            image = nil
            guard !photoID.isEmpty else { return }
            let loaded = await NativeImageLoader.shared.loadImage(at: store.photoURL(photoID), pixels: 1280)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .sheet(isPresented: $galleryOpen) {
            NativePhotoGallery(ids: store.view["photos"].array.filter { $0["ownerType"].text == "gear" && $0["ownerId"].text == gearID }.map(\.id), initialID: photoID)
        }
        .sheet(isPresented: $photoActionsOpen) {
            NativePhotoSheet(owner: "gear", ownerID: gearID, gearID: gearID)
        }
    }

    @ViewBuilder private func renderMetrics() -> some View {
        renderDistanceMetric()
        renderSecondaryMetrics()
    }

    private func renderDistanceMetric() -> some View {
        let metrics = store.view["statistics"][gearID]
        return VStack(alignment: .leading, spacing: 4) {
            NativeDistanceMetric(meters: metrics["distance"].isNull ? nil : metrics["distance"].double, prominent: true)
            Text("累计距离").font(.caption).foregroundStyle(NativeAppearance.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("gear-distance-metric")
    }

    @ViewBuilder private func renderSecondaryMetrics() -> some View {
        let metrics = store.view["statistics"][gearID]
        NativeMetric(title: "使用时长", value: nativeDuration(metrics["seconds"]))
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("gear-duration-metric")
        Button(action: openActivities) {
            NativeMetric(title: "活动", value: metrics["count"].isNull ? "—" : "\(metrics["count"].integer) 次")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("gear-open-activities")
    }
}
