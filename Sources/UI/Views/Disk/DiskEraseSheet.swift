import SwiftUI

final class DiskEraseForm: ObservableObject {
    @Published var format: DiskFormat = .exFAT
    @Published var scope: DiskEraseScope = .volume
    @Published var name: String
    @Published var confirmation = ""

    init(name: String) {
        self.name = name
    }
}

struct DiskEraseSheet: View {
    let volume: DiskVolume
    @StateObject private var form: DiskEraseForm
    @ObservedObject private var tools = DiskToolsController.shared

    init(volume: DiskVolume) {
        self.volume = volume
        _form = StateObject(wrappedValue: DiskEraseForm(name: volume.name))
    }

    private var nameProblem: String? { form.format.nameProblem(form.name) }
    /// Typing the current name proves the user is looking at the right drive.
    private var isConfirmed: Bool { form.confirmation.trimmingCharacters(in: .whitespaces) == volume.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandSectionTitle(L10n.format("Định dạng %@", volume.name), subtitle: "Toàn bộ dữ liệu sẽ bị xoá vĩnh viễn và không khôi phục được.")

            Picker(L10n.text("Định dạng"), selection: $form.format) {
                ForEach(DiskFormat.allCases) { Text($0.title).tag($0) }
            }
            Text(L10n.text(form.format.hint)).font(.system(size: 11)).foregroundColor(.secondary)

            Picker(L10n.text("Phạm vi"), selection: $form.scope) {
                Text(L10n.format("Chỉ phân vùng %@", volume.bsdName)).tag(DiskEraseScope.volume)
                Text(L10n.format("Toàn bộ ổ %@", volume.wholeDisk ?? "")).tag(DiskEraseScope.wholeDisk)
            }
            .pickerStyle(.radioGroup)
            .disabled(volume.wholeDisk == nil)

            BrandTextField("Tên ổ sau khi định dạng", text: $form.name)
            if let nameProblem {
                Text(nameProblem).font(.system(size: 11)).foregroundColor(.red)
            }

            Text(L10n.format("Gõ \"%@\" để xác nhận:", volume.name)).font(.system(size: 12, weight: .medium))
            BrandTextField(volume.name, text: $form.confirmation, accessibilityLabel: L10n.text("Xác nhận tên ổ"))

            HStack {
                Spacer()
                Button("Huỷ") { tools.activeSheet = nil }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Xoá và định dạng") { submit() }
                    .buttonStyle(BrandDestructiveButtonStyle())
                    .disabled(nameProblem != nil || !isConfirmed)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func submit() {
        let volume = volume
        let format = form.format
        let name = form.name
        let scope = form.scope
        tools.activeSheet = nil
        tools.run(L10n.format("Đang định dạng %@ sang %@. Đừng rút ổ...", volume.name, format.title)) {
            let report = await DiskOperations.erase(volume, format: format, name: name, scope: scope)
            return report.succeeded
                ? L10n.format("Đã định dạng xong ổ %@ (%@).", format.normalizedName(name), format.title)
                : L10n.format("Định dạng thất bại: %@", report.summary)
        }
    }
}
