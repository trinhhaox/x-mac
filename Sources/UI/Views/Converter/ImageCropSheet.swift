import AppKit
import SwiftUI

/// Crop one image: preview, draggable frame, aspect presets. Reports a normalized rect in oriented image space.
struct ImageCropSheet: View {
    let url: URL
    let position: Int
    let total: Int
    let onApply: (CGRect) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var image: NSImage?
    @State private var aspect = CropAspect.free
    @State private var rect: CGRect

    init(
        url: URL, position: Int, total: Int, initial: CGRect?,
        onApply: @escaping (CGRect) -> Void, onSkip: @escaping () -> Void, onCancel: @escaping () -> Void
    ) {
        self.url = url
        self.position = position
        self.total = total
        self.onApply = onApply
        self.onSkip = onSkip
        self.onCancel = onCancel
        _rect = State(initialValue: initial ?? ImageCropMath.unit)
    }

    private var imageSize: CGSize { image?.size ?? CGSize(width: 1, height: 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format("Cắt ảnh %d/%d: %@", position, total, url.lastPathComponent))
                .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            if let image {
                ImageCropFrame(image: image, rect: $rect, aspect: aspect.ratio)
                    .frame(width: 520, height: 360)
            } else {
                Text(L10n.text("Không đọc được tệp")).foregroundColor(.secondary).frame(width: 520, height: 360)
            }
            Picker(L10n.text("Tỉ lệ"), selection: $aspect) {
                ForEach(CropAspect.allCases) { Text(verbatim: L10n.text($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: aspect) { value in
                if let ratio = value.ratio { rect = ImageCropMath.fitted(aspect: ratio, imageSize: imageSize) }
            }
            HStack {
                Button(L10n.text("Hủy")) { onCancel() }.buttonStyle(BrandSecondaryButtonStyle())
                Spacer()
                Button(L10n.text("Bỏ qua")) { onSkip() }.buttonStyle(BrandSecondaryButtonStyle())
                Button(L10n.text("Áp dụng")) { onApply(rect) }.disabled(image == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .task { await loadPreview() }
    }

    private func loadPreview() async {
        let url = url
        let cgImage = await Task.detached(priority: .userInitiated) { try? ImageIOSupport.loadImage(url, maxPixel: 1400) }.value
        if let cgImage { image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)) }
    }
}

/// The image fitted into its container with a dimmed surround and a movable, corner-resizable frame.
private struct ImageCropFrame: View {
    let image: NSImage
    @Binding var rect: CGRect
    let aspect: CGFloat?
    @State private var dragStart: CGRect?

    private static let handle: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let frame = CGRect(
                x: rect.minX * size.width, y: rect.minY * size.height,
                width: rect.width * size.width, height: rect.height * size.height
            )
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                Rectangle().stroke(Color.white, lineWidth: 1.5).frame(width: frame.width, height: frame.height)
                    .background(Color.clear.contentShape(Rectangle()))
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(moveGesture(in: size))
                ForEach(0..<4, id: \.self) { index in
                    let point = corner(index, of: frame)
                    Circle().fill(Color.white).overlay(Circle().stroke(Color.black.opacity(0.4)))
                        .frame(width: Self.handle, height: Self.handle)
                        .offset(x: point.x - Self.handle / 2, y: point.y - Self.handle / 2)
                        .gesture(resizeGesture(corner: index, in: size))
                }
            }
            .frame(width: size.width, height: size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    /// 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
    private func corner(_ index: Int, of frame: CGRect) -> CGPoint {
        CGPoint(x: index % 2 == 0 ? frame.minX : frame.maxX, y: index < 2 ? frame.minY : frame.maxY)
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                rect = ImageCropMath.moved(start, dx: value.translation.width / size.width, dy: value.translation.height / size.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(corner index: Int, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                let opposite = corner(3 - index, of: start)
                let moving = corner(index, of: start)
                let point = CGPoint(
                    x: moving.x + value.translation.width / size.width,
                    y: moving.y + value.translation.height / size.height
                )
                rect = ImageCropMath.resized(
                    anchor: opposite, to: point, aspect: aspect, imageSize: image.size
                )
            }
            .onEnded { _ in dragStart = nil }
    }
}
