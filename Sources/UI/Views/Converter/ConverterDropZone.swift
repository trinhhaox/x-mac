import SwiftUI
import UniformTypeIdentifiers

struct ConverterDropZone: View {
    let onFiles: (BrowserDropInputs) -> Void
    @ObservedObject private var browserDrops = BrowserDropCoordinator.shared
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(XmacTheme.blue)
            if browserDrops.activeCount > 0 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Đang tải…")).font(.system(size: 14, weight: .semibold))
                }
                Button(L10n.text("Huỷ"), action: browserDrops.cancelAll)
                    .buttonStyle(BrandSecondaryButtonStyle())
            } else {
                Text(L10n.text("Thả tệp vào đây để chuyển đổi"))
                    .font(.system(size: 14, weight: .semibold))
                Button(L10n.text("Chọn tệp…"), action: chooseFiles)
                    .buttonStyle(BrandPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(XmacTheme.blue.opacity(isTargeted ? 0.14 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(XmacTheme.blue.opacity(isTargeted ? 0.7 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .onDrop(of: [.fileURL, .url, .image, .plainText, .utf8PlainText], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = L10n.text("Chọn")
        if panel.runModal() == .OK { onFiles(BrowserDropInputs(urls: panel.urls)) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let typeID = UTType.fileURL.identifier
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(typeID) }
        guard !fileProviders.isEmpty else { return handleBrowserDrop(providers) }
        // Loads finish in any order; slots keep the drop order (it decides the merge order).
        let lock = NSLock()
        var slots = [URL?](repeating: nil, count: fileProviders.count)
        let group = DispatchGroup()
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, error in
                defer { group.leave() }
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    if let error { NSLog("Converter: could not read dropped item: \(error)") }
                    return
                }
                lock.lock()
                slots[index] = url
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            let urls = slots.compactMap { $0 }
            if !urls.isEmpty { onFiles(BrowserDropInputs(urls: urls)) }
        }
        return true
    }

    /// Links, images and downloads dragged out of a browser: fetch them all, then offer formats.
    private func handleBrowserDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var payloads: [BrowserDragPayload] = []
            for provider in providers {
                if let payload = await BrowserDragProviderReader.payload(from: provider) { payloads.append(payload) }
            }
            guard !payloads.isEmpty else {
                browserDrops.reportUnreadable()
                return
            }
            if let inputs = await browserDrops.fetch(payloads) { browserDrops.deliver(inputs, show: onFiles) }
        }
        return true
    }
}
