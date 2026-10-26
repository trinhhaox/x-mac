import SwiftUI

/// Preset and notification options for the converter, shown in Settings.
struct ConverterSettingsCard: View {
    @ObservedObject private var manager = ConverterManager.shared
    @ObservedObject private var donut = DonutController.shared
    @State private var notifyOnFinish = ConverterManager.shared.notifyOnFinish
    @State private var browserDropMode = BrowserDropCoordinator.shared.mode

    private enum Tab: String, CaseIterable {
        case image = "Ảnh", pdf = "PDF", video = "Video"

        var group: ConversionGroup {
            switch self {
            case .image: return .image
            case .pdf: return .pdf
            case .video: return .media
            }
        }
    }

    @State private var tab = Tab.image

    private func binding<Value>(_ keyPath: WritableKeyPath<ConversionPreset, Value>) -> Binding<Value> {
        let group = tab.group
        return Binding(
            get: { manager.preset(for: group)[keyPath: keyPath] },
            set: { value in manager.updatePreset(for: group) { $0[keyPath: keyPath] = value } }
        )
    }

    /// 0 stands for "no limit" in the segmented pickers.
    private func limit(_ keyPath: WritableKeyPath<ConversionPreset, Int?>) -> Binding<Int> {
        let source = binding(keyPath)
        return Binding(get: { source.wrappedValue ?? 0 }, set: { source.wrappedValue = $0 == 0 ? nil : $0 })
    }

    var body: some View {
        ModernCard {
            BrandSectionTitle("Chuyển đổi tệp", subtitle: "Mặc định theo từng loại tệp.")
            BrandToggleRow("Thông báo khi chuyển đổi xong", isOn: $notifyOnFinish)
                .onChange(of: notifyOnFinish) { manager.notifyOnFinish = $0 }
            BrandToggleRow(
                "Vòng chọn khi kéo tệp + ⌃ (thử nghiệm)",
                subtitle: "Đang kéo tệp, nhấn ⌃ để hiện vòng định dạng quanh con trỏ rồi thả vào ô muốn chuyển.",
                isOn: $donut.isEnabled
            )
            option("Tệp kéo từ trình duyệt", selection: $browserDropMode, choices: BrowserDropMode.allCases) {
                L10n.text($0 == .downloads ? "Lưu vào Tải về" : "Chỉ giữ tệp đã chuyển")
            }
            .onChange(of: browserDropMode) { BrowserDropCoordinator.shared.mode = $0 }
            Picker(L10n.text("Loại tệp"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(verbatim: L10n.text($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .image: imageControls
            case .pdf:
                option("Độ phân giải khi xuất PDF ra ảnh (DPI)", selection: binding(\.pdfRenderDPI), choices: [72, 150, 300]) {
                    Int($0).description
                }
                imageControls
            case .video:
                option("Chiều cao video tối đa", selection: limit(\.maxVideoHeight), choices: [0, 1080, 720], label: pixelLabel)
            }
        }
    }

    @ViewBuilder private var imageControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.format("Chất lượng ảnh JPG/HEIC: %d%%", Int((binding(\.imageQuality).wrappedValue * 100).rounded())))
                .font(.system(size: 13, weight: .medium))
            Slider(value: binding(\.imageQuality), in: 0.3...1, step: 0.05)
        }
        option("Cạnh dài tối đa của ảnh", selection: limit(\.maxImageDimension), choices: [0, 4096, 2048, 1024], label: pixelLabel)
    }

    /// 0 stands for "no limit".
    private func pixelLabel(_ value: Int) -> String { value == 0 ? L10n.text("Gốc") : value.description }

    private func option<Value: Hashable>(
        _ title: String, selection: Binding<Value>, choices: [Value], label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title)).font(.system(size: 13, weight: .medium))
            Picker(L10n.text(title), selection: selection) {
                ForEach(choices, id: \.self) { choice in
                    Text(verbatim: label(choice)).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
