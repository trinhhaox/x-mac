import QuickLookThumbnailing
import SwiftUI

@MainActor
final class ConverterThumbnailCache {
    static let shared = ConverterThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, points: CGFloat) async -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: points, height: points),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        // Folders and unsupported types have no thumbnail; the Finder icon is the intended fallback.
        let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
            ?? NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct ConverterThumbnail: View {
    static let side: CGFloat = 38
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Color.secondary.opacity(0.08)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: url) { image = await ConverterThumbnailCache.shared.image(for: url, points: Self.side) }
    }
}

struct ConverterRecentCard: View {
    @ObservedObject var manager: ConverterManager

    var body: some View {
        if !manager.recent.isEmpty {
            ModernCard {
                BrandSectionTitle("Gần đây")
                VStack(spacing: 0) {
                    ForEach(manager.recent) { item in
                        let url = URL(fileURLWithPath: item.outputPath)
                        BrandListRow {
                            HStack(spacing: 12) {
                                ConverterThumbnail(url: url)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: url.lastPathComponent)
                                        .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    Text(verbatim: "\(item.inputName) → \(L10n.text(item.targetTitle)) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 12)
                                ConverterOutputButtons(url: url)
                            }
                        }
                        if item.id != manager.recent.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
