import SwiftUI

final class DiskNameForm: ObservableObject {
    @Published var name: String

    init(name: String) {
        self.name = name
    }
}

struct DiskRenameSheet: View {
    let volume: DiskVolume
    @StateObject private var form: DiskNameForm
    @ObservedObject private var tools = DiskToolsController.shared

    init(volume: DiskVolume) {
        self.volume = volume
        _form = StateObject(wrappedValue: DiskNameForm(name: volume.name))
    }

    private var format: DiskFormat? { DiskFormat(fileSystem: volume.fileSystem) }

    private var problem: String? {
        if let format { return format.nameProblem(form.name) }
        return form.name.trimmingCharacters(in: .whitespaces).isEmpty ? L10n.text("Tên ổ không được để trống.") : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandSectionTitle(L10n.format("Đổi tên %@", volume.name), subtitle: "Tên mới hiển thị trong Finder và trên máy khác.")
            BrandTextField("Tên mới", text: $form.name)
            if let problem {
                Text(problem).font(.system(size: 11)).foregroundColor(.red)
            } else if format == .fat32 {
                Text("FAT32 lưu tên bằng chữ in hoa.").font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Huỷ") { tools.activeSheet = nil }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Đổi tên") { submit() }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func submit() {
        let volume = volume
        let newName = form.name
        let format = format
        tools.activeSheet = nil
        tools.run(L10n.format("Đang đổi tên %@...", volume.name)) {
            let report = await DiskOperations.rename(volume, to: newName, format: format)
            return report.succeeded
                ? L10n.format("Đã đổi tên thành %@.", format?.normalizedName(newName) ?? newName)
                : L10n.format("Không đổi tên được: %@", report.summary)
        }
    }
}
