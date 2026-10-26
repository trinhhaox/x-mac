import SwiftUI

/// Preset and notification options for the converter, shown in Settings.
struct ConverterSettingsCard: View {
    @ObservedObject private var manager = ConverterManager.shared
    @ObservedObject private var donut = DonutController.shared
    @State private var notifyOnFinish = ConverterManager.shared.notifyOnFinish
    @State private var browserDropMode = BrowserDropCoordinator.shared.mode

    private var maxImageDimension: Binding<Int> {
        Binding(get: { manager.preset.maxImageDimension ?? 0 }, set: { manager.preset.maxImageDimension = $0 == 0 ? nil : $0 })
    }

    private var maxVideoHeight: Binding<Int> {
        Binding(get: { manager.preset.maxVideoHeight ?? 0 }, set: { manager.preset.maxVideoHeight = $0 == 0 ? nil : $0 })
    }

    var body: some View {
        ModernCard {
            BrandSectionTitle("Chuyển đổi tệp", subtitle: "Mặc định áp dụng cho mọi lần chuyển đổi.")
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
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format("Chất lượng ảnh JPG/HEIC: %d%%", Int((manager.preset.imageQuality * 100).rounded())))
                    .font(.system(size: 13, weight: .medium))
                Slider(value: $manager.preset.imageQuality, in: 0.3...1, step: 0.05)
            }
            option("Cạnh dài tối đa của ảnh", selection: maxImageDimension, choices: [0, 4096, 2048, 1024], label: pixelLabel)
            option("Độ phân giải khi xuất PDF ra ảnh (DPI)", selection: $manager.preset.pdfRenderDPI, choices: [72, 150, 300]) {
                Int($0).description
            }
            option("Chiều cao video tối đa", selection: maxVideoHeight, choices: [0, 1080, 720], label: pixelLabel)
        }
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
