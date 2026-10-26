import SwiftUI

/// "Hiện trong Finder" / "Mở" for a finished output; disabled once the file is gone.
struct ConverterOutputButtons: View {
    let url: URL

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        HStack(spacing: 8) {
            Button(L10n.text("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(L10n.text("Mở")) { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(BrandSecondaryButtonStyle())
        .disabled(!exists)
    }
}

struct ConverterJobRow: View {
    let job: ConversionJob
    let onCancel: () -> Void

    private var title: String {
        job.inputs.count == 1 ? job.inputs[0].lastPathComponent : L10n.format("%d tệp", job.inputs.count)
    }

    var body: some View {
        BrandListRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(verbatim: "→ " + L10n.text(job.target.title)).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                status
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .queued:
            Text(L10n.text("Đang chờ")).font(.system(size: 12)).foregroundColor(.secondary)
            cancelButton
        case .running(let value):
            ProgressView(value: value).frame(width: 120)
            Text(verbatim: "\(Int(value * 100))%").font(.system(size: 12).monospacedDigit()).foregroundColor(.secondary)
            cancelButton
        case .done(let url):
            ConverterOutputButtons(url: url)
        case .failed(let message):
            Text(verbatim: L10n.text(message)).font(.system(size: 12)).foregroundColor(.red).lineLimit(2).frame(maxWidth: 260, alignment: .trailing)
        case .cancelled:
            Text(L10n.text("Đã hủy")).font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(L10n.text("Hủy"))
    }
}
