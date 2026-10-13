import SwiftUI

public struct CutPasteView: View {
    @ObservedObject var cutPaste = FinderCutPasteManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finder Cut & Paste")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Di chuyển tệp và thư mục nhanh chóng trong Finder bằng phím tắt ⌘X và ⌘V tương tự Windows Explorer.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Kích hoạt", isOn: $cutPaste.isEnabled)
                        .toggleStyle(.switch)
                }
                
                // Keyboard Shortcuts Guide Card
                ModernCard {
                    Text("Phím tắt thao tác")
                        .font(.system(size: 15, weight: .bold))
                    
                    VStack(spacing: 12) {
                        ShortcutRow(key: "⌘X", title: "Cắt tệp / thư mục", desc: "Chọn các file trong Finder và nhấn ⌘X để đưa vào danh sách di chuyển.")
                        Divider()
                        ShortcutRow(key: "⌘V", title: "Dán di chuyển", desc: "Mở thư mục đích và nhấn ⌘V để di chuyển file đến (không phải copy).")
                        Divider()
                        ShortcutRow(key: "⌘Z", title: "Hoàn tác di chuyển", desc: "Trả các file vừa paste về lại vị trí ban đầu một cách an toàn.")
                        Divider()
                        ShortcutRow(key: "⌘C", title: "Sao chép thông thường", desc: "Nhấn ⌘C sẽ tự động huỷ bỏ trạng thái cắt tệp hiện tại.")
                    }
                }
                
                // Pending Files Card
                ModernCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Danh sách tệp đang chờ dán")
                                .font(.system(size: 15, weight: .bold))
                            Text(cutPaste.cutFiles.isEmpty ? "Hiện không có tệp nào được cắt." : "Có \(cutPaste.cutFiles.count) tệp đang chờ di chuyển.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !cutPaste.cutFiles.isEmpty {
                            Button("Huỷ bỏ cắt") {
                                cutPaste.handleCopy()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Dán ngay (⌘V)") {
                                _ = cutPaste.handlePaste()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if !cutPaste.cutFiles.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cutPaste.cutFiles, id: \.self) { path in
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.blue)
                                    Text((path as NSString).lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(path)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                // Undo Action Card
                ModernCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hoàn tác thao tác gần nhất")
                                .font(.system(size: 15, weight: .bold))
                            Text("Nếu bạn vô tình dán nhầm vị trí, bạn có thể hoàn tác ngay lập tức.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            _ = cutPaste.handleUndo()
                        }) {
                            Label("Hoàn tác (⌘Z)", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!FileMover.shared.canUndo)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct ShortcutRow: View {
    let key: String
    let title: String
    let desc: String
    
    var body: some View {
        HStack(spacing: 14) {
            Text(key)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}
