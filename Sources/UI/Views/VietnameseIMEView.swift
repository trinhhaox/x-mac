import SwiftUI

public struct VietnameseIMEView: View {
    @ObservedObject var ime = InputHookManager.shared
    @ObservedObject var macroManager = MacroManager.shared
    @ObservedObject var vm = VietnameseIMEViewModel.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bộ gõ Tiếng Việt")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Engine gõ tiếng Việt thông minh, hỗ trợ Telex và VNI, gõ tắt macro, không bị dính chữ.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle(ime.isVietnameseMode ? "Đang bật (V)" : "Đang tắt (E)", isOn: $ime.isVietnameseMode)
                        .toggleStyle(.switch)
                }
                
                // Typing Method & Orthography Settings
                ModernCard {
                    Text("Cấu hình kiểu gõ & Quy tắc")
                        .font(.system(size: 15, weight: .bold))
                    
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
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kiểu bỏ dấu mới")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Bỏ dấu theo chuẩn mới: hòa, thúy, khỏe thay vì hoà, thuý, khoẻ.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $ime.modernOrthography)
                                .labelsHidden()
                        }
                        
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
                            Text("Control + Shift")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
                
                // Macro (Gõ tắt) Management Card
                ModernCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bảng gõ tắt (Macro)")
                                .font(.system(size: 15, weight: .bold))
                            Text("Tự động mở rộng từ viết tắt khi nhấn dấu cách Space.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Bật gõ tắt", isOn: $macroManager.isMacroEnabled)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    // Form thêm mới
                    HStack(spacing: 10) {
                        TextField("Từ viết tắt (vd: vn)", text: $vm.newShortcut)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        TextField("Từ mở rộng (vd: Việt Nam)", text: $vm.newExpansion)
                            .textFieldStyle(.roundedBorder)
                        Button("Thêm") {
                            macroManager.addMacro(shortcut: vm.newShortcut, expansion: vm.newExpansion)
                            vm.newShortcut = ""
                            vm.newExpansion = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.newShortcut.isEmpty || vm.newExpansion.isEmpty)
                    }
                    
                    // Danh sách Macro hiện có
                    VStack(spacing: 6) {
                        ForEach(macroManager.macros) { item in
                            HStack {
                                Text(item.shortcut)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .frame(width: 100, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(item.expansion)
                                    .font(.system(size: 13))
                                Spacer()
                                Button(action: {
                                    macroManager.removeMacro(shortcut: item.shortcut)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                
                // Excluded Apps Card
                ModernCard {
                    Text("Ứng dụng không dùng bộ gõ (Excluded Apps)")
                        .font(.system(size: 15, weight: .bold))
                    Text("Tự động tắt gõ tiếng Việt khi đang làm việc trong các ứng dụng này:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ime.excludedApps, id: \.self) { bundleId in
                            HStack {
                                Image(systemName: "app.badge.checkmark")
                                    .foregroundColor(.blue)
                                Text(bundleId)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
