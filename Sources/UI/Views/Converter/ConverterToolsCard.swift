import SwiftUI

private struct ConverterToolRow: View {
    let tool: ExternalTool
    @AppStorage private var overridePath: String
    @State private var errorMessage: String?

    init(tool: ExternalTool) {
        self.tool = tool
        _overridePath = AppStorage(wrappedValue: "", tool.overrideDefaultsKey)
    }

    private var displayName: String { tool == .soffice ? "LibreOffice (soffice)" : tool.rawValue }

    var body: some View {
        let located = BinaryLocator().locate(tool)
        BrandListRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: displayName).font(.system(size: 13, weight: .medium))
                    if let located {
                        Text(verbatim: located.path).font(.system(size: 11)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text(L10n.text(overridePath.isEmpty ? "Chưa cài" : "Đường dẫn đã chọn không dùng được"))
                            .font(.system(size: 11)).foregroundColor(.orange)
                    }
                    if let errorMessage {
                        Text(verbatim: errorMessage).font(.system(size: 11)).foregroundColor(.red)
                    }
                }
                Spacer(minLength: 12)
                Button(L10n.text("Chọn…"), action: choosePath).buttonStyle(BrandSecondaryButtonStyle())
                if !overridePath.isEmpty {
                    Button(L10n.text("Đặt lại")) { overridePath = ""; errorMessage = nil }
                        .buttonStyle(BrandSecondaryButtonStyle())
                }
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Lets the user reach LibreOffice.app/Contents/MacOS/soffice.
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = L10n.text("Chọn")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard BinaryLocator().usableExecutable(at: url.path) != nil else {
            errorMessage = L10n.text("Tệp này không phải chương trình chạy được")
            return
        }
        overridePath = url.path
        errorMessage = nil
    }
}

struct ConverterToolsCard: View {
    var body: some View {
        ModernCard {
            BrandSectionTitle(
                "Công cụ ngoài",
                subtitle: "Cần cho video, âm thanh nâng cao và tệp Office. Xmac tự tìm; bạn cũng có thể chọn đường dẫn riêng."
            )
            VStack(spacing: 0) {
                ForEach(ExternalTool.allCases, id: \.self) { tool in
                    ConverterToolRow(tool: tool)
                    if tool != ExternalTool.allCases.last { Divider() }
                }
            }
        }
    }
}
