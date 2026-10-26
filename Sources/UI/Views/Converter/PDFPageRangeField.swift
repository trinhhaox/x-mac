import SwiftUI

/// Page-range input shown when every selected file is a PDF; feeds "Trích trang đã chọn".
struct PDFPageRangeField: View {
    @ObservedObject var manager: ConverterManager

    private var text: Binding<String> {
        Binding(
            get: { manager.preset.pdfPageRange ?? "" },
            set: { manager.preset.pdfPageRange = $0.isEmpty ? nil : $0 }
        )
    }

    private var message: String? {
        guard let range = manager.preset.pdfPageRange, !range.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return PageRangeParser.validationMessage(range)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(L10n.text("Khoảng trang (vd. 1-3, 5)"), text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            if let message {
                Text(message).font(.system(size: 11)).foregroundColor(.red)
            }
        }
    }
}
