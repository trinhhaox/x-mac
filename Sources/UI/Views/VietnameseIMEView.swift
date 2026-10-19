import SwiftUI

public struct VietnameseIMEView: View {
    @ObservedObject var ime = InputHookManager.shared
    @ObservedObject var macroManager = MacroManager.shared
    @ObservedObject var vm = VietnameseIMEViewModel.shared
    @ObservedObject var permissions = PermissionsManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    title: "Bộ gõ Tiếng Việt",
                    subtitle: "Telex, VNI và gõ tắt với quy tắc dấu linh hoạt."
                ) {
                    Toggle(
                        permissions.isAccessibilityGranted
                            ? (ime.isVietnameseMode ? "Đang bật (V)" : "Đang tắt (E)")
                            : "Cần quyền Trợ năng",
                        isOn: $ime.isVietnameseMode
                    )
                        .toggleStyle(.switch)
                        .tint(XmacTheme.blue)
                        .disabled(!permissions.isAccessibilityGranted)
                }
                
                // Typing Method & Orthography Settings
                ModernCard {
                    BrandSectionTitle("Kiểu gõ & quy tắc", subtitle: "Thiết lập cách Xmac xử lý tiếng Việt.")
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Kiểu gõ chính")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $ime.typingMethod) {
                                ForEach(TypingMethod.allCases) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .frame(width: 150)
                        }
                        
                        Divider()
                        
                        BrandToggleRow(
                            "Kiểu bỏ dấu mới",
                            subtitle: "Bỏ dấu theo chuẩn mới: hòa, thúy, khỏe thay vì hoà, thuý, khoẻ.",
                            isOn: $ime.modernOrthography
                        )
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phím tắt chuyển đổi nhanh (V / E)")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Nhấn tổ hợp phím này bất cứ lúc nào để chuyển đổi giữa Tiếng Việt và Tiếng Anh.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            BrandKeycap("Control + Shift")
                        }
                    }
                }
                
                // Macro (Gõ tắt) Management Card
                ModernCard {
                    HStack {
                        BrandSectionTitle("Bảng gõ tắt", subtitle: "Mở rộng cụm từ khi nhấn dấu cách.")
                        Spacer()
                        Toggle("Bật gõ tắt", isOn: $macroManager.isMacroEnabled)
                            .toggleStyle(.switch)
                            .tint(XmacTheme.blue)
                    }
                    
                    Divider()
                    
                    // Form thêm mới
                    HStack(spacing: 10) {
                        BrandTextField("Từ viết tắt (vd: vn)", text: $vm.newShortcut)
                            .frame(width: 140)
                        BrandTextField("Từ mở rộng (vd: Việt Nam)", text: $vm.newExpansion)
                        Button("Thêm") {
                            macroManager.addMacro(shortcut: vm.newShortcut, expansion: vm.newExpansion)
                            vm.newShortcut = ""
                            vm.newExpansion = ""
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(vm.newShortcut.isEmpty || vm.newExpansion.isEmpty)
                    }
                    
                    // Danh sách Macro hiện có
                    if macroManager.macros.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "text.badge.plus")
                                .foregroundColor(XmacTheme.blue)
                            Text("Chưa có từ gõ tắt. Thêm mục đầu tiên ở phía trên.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(macroManager.macros.enumerated()), id: \.element.id) { index, item in
                                BrandListRow {
                                    HStack(spacing: 12) {
                                        Text(item.shortcut)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(XmacTheme.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .fill(XmacTheme.blue.opacity(0.08))
                                            )
                                            // Fixed column so arrows and expansions line up.
                                            .frame(minWidth: 64, alignment: .leading)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Text(item.expansion)
                                            .font(.system(size: 13))
                                        Spacer()
                                        MacroDeleteButton(shortcut: item.shortcut) {
                                            macroManager.removeMacro(shortcut: item.shortcut)
                                        }
                                    }
                                }
                                if index < macroManager.macros.count - 1 {
                                    Divider().opacity(0.55)
                                }
                            }
                        }
                    }
                }
                
                // Excluded Apps Card
                ModernCard {
                    BrandSectionTitle(
                        "Ứng dụng loại trừ",
                        subtitle: "Xmac tự bỏ qua bộ gõ trong các ứng dụng cần nhập lệnh chính xác."
                    )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ime.excludedApps, id: \.self) { bundleId in
                            HStack {
                                Image(systemName: "app.badge.checkmark")
                                    .foregroundColor(XmacTheme.blue)
                                Text(bundleId)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(26)
        }
        .xmacPage()
    }
}

private final class MacroDeleteHoverState: ObservableObject {
    @Published var isHovered = false
}

/// Neutral until hovered, so a column of red icons does not outweigh the macros.
private struct MacroDeleteButton: View {
    let shortcut: String
    let action: () -> Void
    @StateObject private var hover = MacroDeleteHoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(hover.isHovered ? .red : .secondary)
        .onHover { hover.isHovered = $0 }
        .help("Xóa gõ tắt")
        .accessibilityLabel(L10n.format("Xóa gõ tắt %@", shortcut))
    }
}
