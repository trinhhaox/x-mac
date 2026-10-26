import SwiftUI

/// Collects folder, input group, output format and optional output subfolder for a new watch rule.
struct WatchFolderRuleSheet: View {
    let onAdd: (WatchFolderRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folder: URL?
    @State private var group = WatchInputGroup.image
    @State private var choiceID = ""
    @State private var subfolder = ""

    private var choices: [ConversionTarget] { group.targets(in: ConverterManager.shared.registry) }
    private var selected: ConversionTarget? { choices.first { $0.id == choiceID } ?? choices.first }
    private var subfolderIsValid: Bool {
        subfolder.trimmingCharacters(in: .whitespaces).isEmpty || WatchFolderRule.normalizedSubfolder(subfolder) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandSectionTitle("Thêm quy tắc", subtitle: "Tệp mới thuộc loại đã chọn sẽ được chuyển sang định dạng đích.")
            row("Thư mục") {
                Text(verbatim: folder?.path ?? L10n.text("Chưa chọn"))
                    .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L10n.text("Chọn…"), action: chooseFolder).buttonStyle(BrandSecondaryButtonStyle())
            }
            row("Loại tệp vào") {
                Picker("", selection: $group) {
                    ForEach(WatchInputGroup.allCases) { Text(L10n.text($0.title)).tag($0) }
                }.labelsHidden()
            }
            row("Chuyển thành") {
                Picker("", selection: Binding(get: { selected?.id ?? "" }, set: { choiceID = $0 })) {
                    ForEach(choices) { Text(verbatim: $0.title).tag($0.id) }
                }.labelsHidden()
            }
            row("Thư mục con chứa kết quả (tuỳ chọn)") {
                TextField(L10n.text("Để trống: lưu cạnh tệp gốc"), text: $subfolder).textFieldStyle(.roundedBorder)
            }
            if !subfolderIsValid {
                Text(L10n.text("Tên thư mục con không hợp lệ")).font(.system(size: 11)).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button(L10n.text("Huỷ")) { dismiss() }.buttonStyle(BrandSecondaryButtonStyle())
                Button(L10n.text("Thêm"), action: add)
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(folder == nil || selected == nil || !subfolderIsValid)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title)).font(.system(size: 13, weight: .medium))
            HStack { content() }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Chọn")
        if panel.runModal() == .OK { folder = panel.url }
    }

    private func add() {
        guard let folder, let selected else { return }
        onAdd(WatchFolderRule(
            folderPath: folder.path, extensions: group.extensions, targetID: selected.id, targetTitle: selected.title,
            outputSubfolder: WatchFolderRule.normalizedSubfolder(subfolder)
        ))
        dismiss()
    }
}
