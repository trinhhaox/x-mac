# Xmac - Tiện Ích Thiết Yếu Tất Cả Trong Một Cho macOS 

<p align="center">
  <b>Phần mềm giải quyết trọn vẹn những điểm thiếu sót lớn nhất trên macOS dành cho người dùng Mac: Cắt/Dán file Finder, Ghi ổ NTFS, Bộ gõ Tiếng Việt, Dọn rác & Gỡ ứng dụng triệt để.</b>
</p>

---

## 🌟 Tính Năng Nổi Bật

### 1. ✂︎ True Cut & Paste cho Finder (⌘X & ⌘V)
- **⌘X**: Cắt tệp tin hoặc thư mục đang chọn trong Finder (thay thế thao tác rườm rà ⌘C rồi ⌥⌘V của macOS).
- **⌘V**: Dán di chuyển tức thì vào thư mục đích đang mở (hỗ trợ cả Desktop và nhiều cửa sổ Finder).
- **⌘Z**: Hoàn tác (Undo) đưa tệp tin trở lại vị trí ban đầu an toàn nếu paste nhầm.
- **Không chiếm phím khi sửa tên**: Tự động nhận diện khi người dùng đang đổi tên file để ⌘X, ⌘C, ⌘V thao tác trên chữ bình thường.
- **Âm thanh và thông báo**: Phản hồi âm thanh nhẹ nhàng và banner thông báo số lượng tệp đã di chuyển.

### 2. 💽 Quản Lý Ổ Đĩa Ngoại Vi & Đọc / Ghi Ổ NTFS (Windows)
- **Tự động nhận diện ổ đĩa**: Nhận diện tất cả USB, thẻ nhớ, ổ cứng di động SSD/HDD cắm vào máy.
- **Kích hoạt Ghi NTFS (Read-Write)**: Vượt qua rào cản chỉ đọc của macOS, cho phép ghi dữ liệu, sao chép file lớn vào ổ cứng NTFS của Windows.
- **Đồ họa dung lượng trực quan**: Hiển thị chính xác dung lượng tổng, đã dùng, còn trống và định dạng phân vùng.
- **Ngắt kết nối an toàn (Safe Eject)**: Nút ngắt kết nối an toàn 1 chạm giúp bảo vệ dữ liệu không bị hỏng khi rút cáp.
- **Mở nhanh trong Finder**: Truy cập ngay ổ đĩa chỉ với 1 click.

### 3. 🇻🇳 Bộ Gõ Tiếng Việt Thông Minh Xmac
- **Hỗ trợ đầy đủ kiểu gõ**: Telex, VNI và Simple Telex.
- **Bảng mã chuẩn Unicode**: Tương thích hoàn hảo với mọi trình duyệt, Word, Excel, ghi chú, ứng dụng chat.
- **Quy tắc bỏ dấu linh hoạt**: Tùy chọn kiểu bỏ dấu mới (`hòa`, `thúy`) hoặc chuẩn truyền thống (`hoà`, `thuý`).
- **Phím tắt chuyển đổi nhanh (V / E)**: Chuyển đổi ngôn ngữ gõ tức thì bằng tổ hợp phím `Control + Shift` hoặc nhấn trực tiếp trên thanh Menu Bar.
- **Bảng gõ tắt (Macro)**: Tự động mở rộng từ viết tắt (ví dụ: `vn` ➔ `Việt Nam`, `dc` ➔ `được`, `ko` ➔ `không`).
- **Danh sách loại trừ (Excluded Apps)**: Tự động tắt tiếng Việt khi làm việc trong Terminal, iTerm, Xcode để tránh gõ nhầm lệnh.

### 4. 🧹 Dọn Rác Hệ Thống & Gỡ Ứng Dụng Triệt Để
- **Dọn rác hệ thống (System Junk Cleaner)**:
  - Quét sạch bộ nhớ đệm người dùng (User Caches `~/Library/Caches`).
  - Dọn dẹp tệp nhật ký hệ thống (System & User Logs `~/Library/Logs`).
  - Xoá báo cáo lỗi tự động (Diagnostic & Crash Reports).
  - Quét dữ liệu biên dịch khổng lồ của lập trình viên (Xcode DerivedData).
  - Làm sạch Thùng rác (Trash).
- **Giải phóng bộ nhớ RAM (Purge Memory)**: Nút giải phóng RAM Inactive tức thì giúp máy tính nhẹ và mượt mà hơn.
- **Gỡ ứng dụng triệt để (App Uninstaller)**:
  - Tự động dò tìm toàn bộ các file phụ trợ nằm ẩn sâu trong thư viện: `Application Support`, `Caches`, `Preferences .plist`, `Saved State`, `WebKit`, `Sandbox Containers`.
  - Tính toán tổng dung lượng thực tế của ứng dụng.
  - Chuyển ứng dụng và toàn bộ file rác vào Thùng rác một cách an toàn (dễ dàng khôi phục nếu muốn).

---

## 🖥 Giao Diện Người Dùng Hiện Đại (macOS Native)
- **Menu Bar Agent**: Icon động hiển thị `🇻🇳 V` hoặc `🇺🇸 E`, số lượng tệp đang cắt `[✂︎n]`, menu thao tác nhanh 1 chạm.
- **Control Center Window**: Cửa sổ điều khiển Sidebar phong cách macOS Ventura / Sonoma / Sequoia, hỗ trợ Dark Mode và Light Mode tự động.

---

## 🚀 Cài Đặt & Sử Dụng

### 1. Cài đặt từ DMG (Khuyến nghị)
1. Tải file `Xmac-1.0.0.dmg` từ thư mục `build/`.
2. Kéo thả `Xmac.app` vào thư mục `Applications`.
3. Mở ứng dụng và làm theo hướng dẫn cấp quyền.

### 2. Tự biên dịch từ mã nguồn (Build from source)
```bash
git clone https://github.com/trinhhao/Xmac.git
cd Xmac
chmod +x Scripts/build.sh
./Scripts/build.sh
```
Sau khi hoàn tất, file `Xmac.app` và `Xmac-1.0.0.dmg` sẽ được tạo trong thư mục `build/`.

### 3. Chạy kiểm thử

```bash
./Scripts/test.sh
```

Script sử dụng Swift Testing từ toolchain đang active và tự nạp macro plugin khi chỉ cài Command Line Tools.

---

## 🔐 Cấp Quyền Hệ Thống (Privacy & Security)

Để tất cả tính năng của Xmac hoạt động trơn tru:
1. **Trợ năng (Accessibility)**: Mở `Cài đặt hệ thống` ➔ `Quyền riêng tư & Bảo mật` ➔ `Trợ năng`, bật `Xmac`.
2. **Tự động hoá Finder (Automation)**: Cho phép `Xmac` điều khiển `Finder` khi xuất hiện thông báo cấp quyền lần đầu.
3. **Quyền truy cập toàn bộ ổ đĩa (Full Disk Access - Khuyên dùng)**: Cho phép Xmac quét sạch bộ nhớ đệm sâu và file thừa khi gỡ ứng dụng.

---

## 🛠 Kiến Trúc Mã Nguồn

```text
Xmac/
├── Package.swift                   # Cấu hình Swift Package Manager
├── Resources/
│   ├── Info.plist                  # Cấu hình bundle, quyền & định danh macOS
│   └── AppIcon.icns                # Icon chuẩn Retina cho ứng dụng
├── Sources/
│   ├── App/
│   │   ├── AppDelegate.swift       # Vòng đời ứng dụng & Quản lý cửa sổ
│   │   ├── AppState.swift          # Trạng thái điều hướng & số liệu hệ thống
│   │   └── main.swift              # Điểm khởi chạy app
│   ├── Core/
│   │   ├── LaunchAtLoginManager.swift # Tự khởi động cùng hệ thống (macOS 13+)
│   │   ├── PermissionsManager.swift   # Kiểm tra và cấp quyền hệ thống
│   │   └── SoundEffectManager.swift   # Hiệu ứng âm thanh tương tác
│   ├── Features/
│   │   ├── Cleaner/
│   │   │   ├── AppUninstallerEngine.swift # Engine gỡ triệt để ứng dụng
│   │   │   ├── CleanerEngine.swift        # Engine quét và dọn rác hệ thống
│   │   │   └── CleanerModels.swift        # Cấu trúc dữ liệu dọn dẹp
│   │   ├── DiskNTFS/
│   │   │   ├── DiskManager.swift          # Quét ổ đĩa ngoại vi & phân vùng
│   │   │   ├── DiskModel.swift            # Cấu trúc dữ liệu ổ đĩa
│   │   │   └── NTFSMountHelper.swift      # Hỗ trợ mount NTFS đọc-ghi & Safe Eject
│   │   ├── FinderCutPaste/
│   │   │   ├── EventTapManager.swift      # Hook bắt phím ⌘X, ⌘V, ⌘Z
│   │   │   ├── FileMover.swift            # Xử lý di chuyển file & Undo
│   │   │   ├── FinderBridge.swift         # Kết nối Finder qua AppleScript
│   │   │   └── FinderCutPasteManager.swift# Quản lý hàng đợi cắt dán
│   │   └── VietnameseIME/
│   │       ├── InputHookManager.swift     # Hook gõ phím & chuyển đổi V/E
│   │       ├── MacroManager.swift         # Quản lý gõ tắt
│   │       └── VietnameseEngine.swift     # Thuật toán gõ Telex/VNI tiếng Việt
│   └── UI/
│       ├── Components/
│       │   └── ModernComponents.swift     # UI components phong cách Apple
│       ├── MenuBar/
│       │   └── StatusBarController.swift  # Điều khiển Menu Bar status item
│       ├── ViewModels/
│       │   └── AppViewModels.swift        # State ViewModels cho các màn hình
│       └── Views/
│           ├── AppUninstallerView.swift   # Giao diện gỡ ứng dụng
│           ├── CutPasteView.swift         # Giao diện Finder Cut & Paste
│           ├── DiskNTFSView.swift         # Giao diện Ổ đĩa & NTFS
│           ├── JunkCleanerView.swift      # Giao diện Dọn rác hệ thống
│           ├── MainView.swift             # Khung cửa sổ chính với Sidebar
│           ├── OverviewView.swift         # Tổng quan Control Center
│           ├── SettingsView.swift         # Cài đặt ứng dụng
│           └── VietnameseIMEView.swift    # Giao diện Bộ gõ tiếng Việt
└── Scripts/
    └── build.sh                    # Script biên dịch Universal Binary & tạo DMG
```

---

## 📄 Bản Quyền
Phát triển dành riêng cho cộng đồng người dùng macOS Việt Nam.
