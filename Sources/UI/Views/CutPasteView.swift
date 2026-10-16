import SwiftUI

public struct CutPasteView: View {
    @ObservedObject var cutPaste = FinderCutPasteManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    title: "Di chuyển tệp trong Finder",
                    subtitle: "Di chuyển tệp trong Finder bằng phím tắt quen thuộc, có thể hoàn tác an toàn."
                ) {
                    Toggle(
                        permissions.isAccessibilityGranted ? "Kích hoạt" : "Cần quyền Trợ năng",
                        isOn: $cutPaste.isEnabled
                    )
                        .toggleStyle(.switch)
                        .tint(XmacTheme.blue)
                        .disabled(!permissions.isAccessibilityGranted)
                }
                
                // Keyboard Shortcuts Guide Card
                ModernCard {
                    BrandSectionTitle("Phím tắt", subtitle: "Bốn thao tác cốt lõi trong Finder.")
                    
                    VStack(spacing: 12) {
                        ShortcutRow(key: "⌘X", title: "Cắt tệp / thư mục", desc: "Chọn các file trong Finder và nhấn ⌘X để đưa vào danh sách di chuyển.")
                        Divider()
                        ShortcutRow(key: "⌘V", title: "Di chuyển đến đây", desc: "Mở thư mục đích và nhấn ⌘V để chuyển các tệp đã cắt đến đó.")
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
                            Button("Bỏ danh sách") {
                                cutPaste.handleCopy()
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                            
                            Button("Di chuyển ngay (⌘V)") {
                                _ = cutPaste.handlePaste()
                            }
                            .buttonStyle(BrandPrimaryButtonStyle())
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
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(!FileMover.shared.canUndo)
                    }
                }
            }
            .padding(26)
        }
        .xmacPage()
    }
}

struct ShortcutRow: View {
    let key: String
    let title: String
    let desc: String
    
    var body: some View {
        HStack(spacing: 14) {
            BrandKeycap(key)
                .frame(width: 56)
            
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
