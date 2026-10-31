import SwiftUI
import ImageIO

enum NativeAppearance {
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.63, blue: 1, alpha: 1) : UIColor(red: 0.14, green: 0.34, blue: 0.80, alpha: 1) })
    static let prominentText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.06, alpha: 1) : .white })
    static let secondaryText = Color(uiColor: UIColor { traits in
        let increased = traits.accessibilityContrast == .high
        return traits.userInterfaceStyle == .dark
            ? UIColor(white: increased ? 0.82 : 0.68, alpha: 1)
            : UIColor(white: increased ? 0.28 : 0.40, alpha: 1)
    })
    static let dangerText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)
        : UIColor(red: 0.73, green: 0.09, blue: 0.09, alpha: 1) })
    static let warningText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.68, blue: 0.33, alpha: 1)
        : UIColor(red: 0.63, green: 0.31, blue: 0.03, alpha: 1) })
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.055, alpha: 1) : UIColor(white: 0.965, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.105, alpha: 1) : .white })
    static let guide = Color.primary.opacity(0.10)
}

struct NativeReadableValueStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content.foregroundStyle(NativeAppearance.secondaryText)
        } label: { configuration.label }
            .labeledContentStyle(.automatic)
    }
}

struct NativeMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
        }.accessibilityElement(children: .combine)
    }
}

struct NativeDistanceMetric: View {
    let meters: Double?
    var prominent = false
    @ScaledMetric(relativeTo: .largeTitle) private var largeSize = 34
    @ScaledMetric(relativeTo: .title2) private var regularSize = 22
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(meters.map { ($0 / 1000).formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(.system(size: prominent ? largeSize : regularSize, weight: .semibold))
                .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
            Text("km").font(.subheadline).foregroundStyle(NativeAppearance.secondaryText)
        }.accessibilityElement(children: .combine)
    }
}

struct NativeStatusBadge: View {
    let status: String
    var body: some View {
        Text(status == "stock" ? "库存" : status == "retired" ? "已退役" : "使用中")
            .font(.caption).foregroundStyle(NativeAppearance.secondaryText)
    }
}

struct NativeHierarchyGuide: View {
    let depth: Int
    let continuingLevels: Set<Int>
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for index in 0..<min(depth, 6) {
                    let x = CGFloat(index) * 18 + 12
                    if continuingLevels.contains(index) || index == min(depth, 6) - 1 {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: continuingLevels.contains(index) ? geometry.size.height : geometry.size.height / 2))
                    }
                }
                if depth > 0 {
                    let x = CGFloat(min(depth, 6) - 1) * 18 + 12
                    path.move(to: CGPoint(x: x, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: x + 8, y: geometry.size.height / 2))
                }
            }.stroke(NativeAppearance.guide, lineWidth: 1)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct NativeActionSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

actor NativeImageLoader {
    static let shared = NativeImageLoader()
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    init() { cache.totalCostLimit = 24 * 1024 * 1024 }
    func loadImage(at url: URL, pixels: Int) async -> UIImage? {
        let key = url.path + ":" + String(pixels)
        if let image = cache.object(forKey: key as NSString) { return image }
        if let request = inFlight[key] { return await request.value }
        let request = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return Optional<UIImage>.none }
            return UIImage(cgImage: thumbnail)
        }
        inFlight[key] = request
        let image = await request.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }
}
