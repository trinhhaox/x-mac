import SwiftUI

/// "Cắt ảnh…" for a selection made only of images: walks through them one by one in a sheet.
struct ImageCropSection: View {
    @ObservedObject var manager: ConverterManager
    let inputs: [URL]
    @State private var index: Int?

    static func applies(to inputs: [URL]) -> Bool {
        !inputs.isEmpty && inputs.allSatisfy { ImageIOSupport.isReadable($0.conversionType) }
    }

    private var cropped: Int { inputs.filter { manager.cropRects[$0.standardizedFileURL] != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button(L10n.text("Cắt ảnh…")) { index = 0 }.buttonStyle(BrandSecondaryButtonStyle())
                if cropped > 0 {
                    Text(L10n.format("Đã cắt %d ảnh", cropped)).font(.system(size: 12)).foregroundColor(.secondary)
                    Button(L10n.text("Bỏ cắt")) { manager.clearCrops() }.buttonStyle(BrandSecondaryButtonStyle())
                }
            }
            Text(L10n.text("Chỉ áp dụng khi chuyển sang định dạng ảnh")).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .sheet(isPresented: Binding(get: { index != nil }, set: { if !$0 { index = nil } })) {
            if let current = index, inputs.indices.contains(current) {
                let url = inputs[current]
                ImageCropSheet(
                    url: url, position: current + 1, total: inputs.count,
                    initial: manager.cropRects[url.standardizedFileURL],
                    onApply: { advance(url, crop: ImageCropMath.isFullFrame($0) ? nil : $0) },
                    onSkip: { advance(url, crop: nil) },
                    onCancel: { index = nil }
                )
                .id(url)
            }
        }
    }

    private func advance(_ url: URL, crop: CGRect?) {
        manager.setCrop(crop, for: url)
        guard let current = index, current + 1 < inputs.count else { return index = nil }
        index = current + 1
    }
}
