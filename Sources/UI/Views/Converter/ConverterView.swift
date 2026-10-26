import SwiftUI

public struct ConverterView: View {
    @ObservedObject private var manager = ConverterManager.shared
    @State private var selection = ConverterSelectionModel.empty
    @State private var origin = BrowserDropInputs(urls: [])

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    title: "Chuyển đổi tệp",
                    subtitle: "Thả tệp, chọn định dạng đích. Mọi thứ chạy ngay trên máy của bạn."
                ) { EmptyView() }
                ModernCard {
                    ConverterDropZone(onFiles: select)
                    if !selection.inputs.isEmpty { targets }
                }
                ConverterJobsCard(manager: manager)
                ConverterRecentCard(manager: manager)
                WatchFoldersCard()
                ConverterToolsCard()
            }
            .padding(26)
        }
        .xmacPage()
    }

    @ViewBuilder private var targets: some View {
        HStack {
            BrandSectionTitle(L10n.format("Chuyển %@ thành", selection.summary))
            Spacer()
            Button(L10n.text("Bỏ chọn")) { select(BrowserDropInputs(urls: [])) }.buttonStyle(BrandSecondaryButtonStyle())
        }
        if selection.inputs.allSatisfy({ $0.conversionType == .pdf }) { PDFPageRangeField(manager: manager) }
        if selection.hasTargets {
            ConverterTargetGrid(model: selection, columnCount: 5) { target in
                manager.enqueue(
                    inputs: selection.inputs, target: target,
                    outputDirectory: origin.outputDirectory, disposeInputs: origin.disposable
                )
                // The scratch copy goes away with its job, so it cannot be converted a second time.
                if origin.disposable { selection = .empty }
            }
        } else {
            Text(L10n.text("Không có định dạng đích phù hợp cho các tệp này."))
                .font(.system(size: 12)).foregroundColor(.secondary)
            ForEach(selection.missingToolHints, id: \.self) { hint in
                Text(L10n.text(hint)).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private func select(_ inputs: BrowserDropInputs) {
        if origin.disposable { BrowserDropCoordinator.dispose(selection.inputs) }
        origin = inputs
        selection = ConverterSelectionModel(inputs: inputs.urls, registry: manager.registry)
    }
}
