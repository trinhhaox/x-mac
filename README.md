# Xmac - Tiện Ích Thiết Yếu Tất Cả Trong Một Cho macOS 

<p align="center">
  <b>Bộ tiện ích macOS hỗ trợ tải tệp, tìm tệp nhanh, Cắt/Dán file Finder, gắn ổ NTFS đọc-ghi qua helper bên ngoài, gõ Tiếng Việt, dọn rác và gỡ ứng dụng có kiểm soát.</b>
</p>

---

## 🌟 Tính Năng Nổi Bật

### Thông tin hệ thống (từ v1.4.0)
- Theo dõi CPU và biểu đồ, RAM/nén/wired/swap, dung lượng lưu trữ và tốc độ nhận/gửi qua Wi-Fi/Ethernet mỗi 2 giây.
- Tạm dừng/tiếp tục; chỉ lấy mẫu khi mở trang, không lưu hoặc gửi số liệu.
- Hiển thị trạng thái nhiệt của macOS; **chưa hỗ trợ nhiệt độ °C**.

Chi tiết và giới hạn: [`docs/SYSTEM_MONITOR.md`](docs/SYSTEM_MONITOR.md).

### 1. ⬇️ Trung Tâm Tải Xuống Native
- **HTTP/HTTPS**: Thêm tối đa 20 liên kết mỗi lần mà không cần engine hoặc extension bên ngoài.
- **Kiểm soát tác vụ**: Theo dõi dung lượng, tạm dừng, tiếp tục, hủy và thử lại.
- **An toàn tệp**: Chuẩn hóa tên do máy chủ trả về và tự tăng hậu tố khi trùng tên, không ghi đè tệp đã có.
- **Tích hợp macOS**: Chọn thư mục lưu, mở tệp trong Finder, lưu lịch sử và nhận thông báo hoàn tất/lỗi.
- **Theo kết nối mạng**: Chờ khi ngoại tuyến, tự thử lại lỗi mạng tối đa 3 lần và tùy chọn tránh mạng tính phí/hạn chế dữ liệu.
- **Giữ máy thức**: Tùy chọn giữ máy thức khi đang tải và trả chế độ ngủ bình thường khi hết tác vụ; màn hình vẫn được phép tắt.

### 2. 🔎 Tìm Tệp Nhanh Bằng Spotlight
- **Tìm native**: Tìm theo tên hoặc nội dung đã được Spotlight lập chỉ mục, không cần daemon nền.
- **Bộ lọc thực dụng**: Chọn phạm vi, loại tệp; dùng `ext:pdf`, `type:image`, `mtime:<7d`, `^prefix`, `suffix$` và `!exclude`.
- **Thao tác trực tiếp**: Mở tệp, hiện trong Finder hoặc sao chép đường dẫn ngay trên kết quả.
- **Thiết kế độc lập**: Tham khảo trải nghiệm truy vấn của [FSearch](https://github.com/noahdunnagan/fsearch), không đóng gói binary/daemon của dự án ngoài.

Chi tiết: [`docs/FILE_SEARCH.md`](docs/FILE_SEARCH.md).

### 3. ✂︎ True Cut & Paste cho Finder (⌘X & ⌘V)
- **⌘X**: Cắt tệp tin hoặc thư mục đang chọn trong Finder (thay thế thao tác rườm rà ⌘C rồi ⌥⌘V của macOS).
- **⌘V**: Dán di chuyển tức thì vào thư mục đích đang mở (hỗ trợ cả Desktop và nhiều cửa sổ Finder).
- **⌘Z**: Hoàn tác (Undo) đưa tệp tin trở lại vị trí ban đầu an toàn nếu paste nhầm.
- **Không chiếm phím khi sửa tên**: Tự động nhận diện khi người dùng đang đổi tên file để ⌘X, ⌘C, ⌘V thao tác trên chữ bình thường.
- **Âm thanh và thông báo**: Phản hồi âm thanh nhẹ nhàng và banner thông báo số lượng tệp đã di chuyển.

### 4. 💽 Quản Lý Ổ Đĩa Ngoại Vi & Đọc / Ghi Ổ NTFS (Windows)
- **Tự động nhận diện ổ đĩa**: Nhận diện tất cả USB, thẻ nhớ, ổ cứng di động SSD/HDD cắm vào máy.
- **Kích hoạt Ghi NTFS (Read-Write)**: Sử dụng AnyLinuxFS hoặc `ntfs-3g`/macFUSE đã cài trên máy, xác minh trạng thái đọc-ghi sau khi mount và tự khôi phục cách mount mặc định nếu thao tác thất bại.
- **Đồ họa dung lượng trực quan**: Hiển thị chính xác dung lượng tổng, đã dùng, còn trống và định dạng phân vùng.
- **Ngắt kết nối an toàn (Safe Eject)**: Nút ngắt kết nối an toàn 1 chạm giúp bảo vệ dữ liệu không bị hỏng khi rút cáp.
- **Mở nhanh trong Finder**: Truy cập ngay ổ đĩa chỉ với 1 click.

### 5. 🇻🇳 Bộ Gõ Tiếng Việt Thông Minh Xmac
- **Hỗ trợ đầy đủ kiểu gõ**: Telex, VNI và Simple Telex.
- **Bảng mã Unicode**: Hoạt động qua Accessibility event tap; mức tương thích phụ thuộc cách từng ứng dụng xử lý nhập liệu và secure input.
- **Quy tắc bỏ dấu linh hoạt**: Tùy chọn kiểu bỏ dấu mới (`hòa`, `thúy`) hoặc chuẩn truyền thống (`hoà`, `thuý`).
- **Gõ Việt–Anh thông minh**: Tự khôi phục các từ tiếng Anh bị Telex/VNI biến đổi khi kết thúc từ; có thể gõ lặp phím dấu để giữ nguyên chữ Latin mà không cần chuyển sang chế độ E.
- **Phím tắt chuyển đổi nhanh (V / E)**: Chuyển đổi ngôn ngữ gõ tức thì bằng tổ hợp phím `Control + Shift` hoặc nhấn trực tiếp trên thanh Menu Bar.
- **Bảng gõ tắt (Macro)**: Tự động mở rộng từ viết tắt (ví dụ: `vn` ➔ `Việt Nam`, `dc` ➔ `được`, `ko` ➔ `không`).
- **Danh sách loại trừ (Excluded Apps)**: Tự động tắt tiếng Việt khi làm việc trong Terminal, iTerm, Xcode để tránh gõ nhầm lệnh.

### 6. 🧹 Dọn Rác Hệ Thống & Gỡ Ứng Dụng Có Kiểm Soát
- **Dọn rác hệ thống (System Junk Cleaner)**:
  - Quét sạch bộ nhớ đệm người dùng (User Caches `~/Library/Caches`).
  - Dọn dẹp tệp nhật ký hệ thống (System & User Logs `~/Library/Logs`).
  - Cho phép chọn riêng báo cáo lỗi (Diagnostic & Crash Reports).
  - Quét dữ liệu biên dịch khổng lồ của lập trình viên (Xcode DerivedData).
  - Làm sạch Thùng rác (Trash).
  - Các mục được chuyển vào Thùng rác (riêng mục đã ở trong Thùng rác bị xóa vĩnh viễn); cache của ứng dụng đang chạy được bỏ qua.
- **Giải phóng bộ nhớ RAM (Purge Memory)**: Nút giải phóng RAM Inactive tức thì giúp máy tính nhẹ và mượt mà hơn.
- **Gỡ ứng dụng có kiểm soát (App Uninstaller)**:
  - Tự động dò tìm toàn bộ các file phụ trợ nằm ẩn sâu trong thư viện: `Application Support`, `Caches`, `Preferences .plist`, `Saved State`, `WebKit`, `Sandbox Containers`.
  - Tính toán tổng dung lượng thực tế của ứng dụng.
  - Mặc định chọn các đường dẫn xác định bằng bundle identifier; đường dẫn suy đoán theo tên ứng dụng phải được người dùng chọn thủ công.
  - Từ chối gỡ khi ứng dụng đang chạy; gỡ được cả ứng dụng Apple cài trong `/Applications` (Xcode, Pages…), chỉ chặn ứng dụng hệ thống.
  - Chuyển app bundle vào Thùng rác trước; nếu thất bại thì không đụng tới file phụ trợ, và báo rõ file phụ trợ nào chưa chuyển được.

---

## 🖥 Giao Diện Người Dùng Hiện Đại (macOS Native)
- **Lịch sử clipboard**: Tùy chọn bật lưu cục bộ, tìm kiếm, ghim, chép văn bản thuần và loại trừ ứng dụng. Mặc định tắt, dữ liệu không mã hóa; xem giới hạn bảo mật trong [`docs/DESKTOP_PHASE3.md`](docs/DESKTOP_PHASE3.md).
- **Sắp xếp Downloads**: Xem trước quy tắc theo loại tệp, xác nhận di chuyển không ghi đè và hoàn tác có nhật ký qua lần khởi động lại.
- **Mở nhanh**: `⌥⇧Space` tìm lệnh Xmac, ứng dụng và tệp Spotlight; hỗ trợ ↑/↓, Enter, Esc và đổi phím trong Cài đặt.
- **Menu Bar Dashboard**: Nhấp trái xem tải xuống, bộ gõ và ổ ngoài; nhấp phải giữ menu đầy đủ. Chi tiết: [`docs/DESKTOP_PHASE2.md`](docs/DESKTOP_PHASE2.md).
- **Menu Bar Agent**: Icon động hiển thị `🇻🇳 V` hoặc `🇺🇸 E`, số lượng tệp đang cắt `[✂︎n]`, menu thao tác nhanh 1 chạm.
- **Control Center Window**: Cửa sổ điều khiển Sidebar phong cách macOS Ventura / Sonoma / Sequoia, hỗ trợ Dark Mode và Light Mode tự động.

---

## 🚀 Cài Đặt & Sử Dụng

Trong **Cài đặt → Cập nhật ứng dụng**, Xmac có thể kiểm tra, tải, xác minh
SHA-256, kiểm tra chữ ký (cùng Team ID và bundle identifier với bản đang chạy) rồi cài bản mới từ GitHub Releases; bản cũ được chuyển vào Thùng rác sau khi cài thành công.
Tự kiểm tra mỗi ngày là tùy chọn; cài đặt cần xác nhận. Xem
[`docs/DESKTOP_PHASE1.md`](docs/DESKTOP_PHASE1.md) về điều kiện cập nhật,
mô hình tin cậy chữ ký và giới hạn phục hồi tải.

### 1. Cài đặt từ DMG (Khuyến nghị)
1. Tải file `Xmac-1.7.6.dmg` từ phần Releases của GitHub hoặc thư mục `build/`.
2. Kéo thả `Xmac.app` vào thư mục `Applications`.
3. Mở ứng dụng và làm theo hướng dẫn cấp quyền.

### 2. Tự biên dịch từ mã nguồn (Build from source)
```bash
git clone https://github.com/trinhhaox/x-mac.git
cd x-mac
chmod +x Scripts/build.sh
./Scripts/build.sh
```
Sau khi hoàn tất, file `Xmac.app` và `Xmac-1.7.6.dmg` sẽ được tạo trong thư mục `build/`.

Mặc định script ký ad-hoc để kiểm thử local. Nếu máy đã có sẵn chứng thư và hồ sơ notarization trong Keychain, có thể tạo bản phát hành bằng:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: ..." \
NOTARY_PROFILE="xmac-notary" \
./Scripts/build.sh
```

Script không tạo hoặc thay đổi chứng thư/thông tin xác thực. Khi đặt `NOTARY_PROFILE`, quá trình build sẽ dừng nếu notarization hoặc stapling thất bại.

### 3. Chạy kiểm thử

```bash
./Scripts/test.sh
```

Script sử dụng Swift Testing từ toolchain đang active và tự nạp macro plugin khi chỉ cài Command Line Tools.

GitHub Actions chạy kiểm thử, dựng Universal Binary (`arm64` + `x86_64`), xác minh chữ ký ad-hoc và DMG trên mỗi push/pull request. Artifact CI không phải bản phân phối notarized.

Khi push tag `v*`, workflow `release.yml` ký Developer ID, notarize và đăng DMG lên GitHub Releases nếu repo có đủ secrets `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`; thiếu secrets thì workflow bỏ qua và bản phát hành ad-hoc được đăng thủ công.

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
│   │   ├── Downloads/
│   │   │   └── DownloadManager.swift      # HTTP/HTTPS download engine, lịch sử & an toàn tên tệp
│   │   ├── FileSearch/
│   │   │   └── FileSearchEngine.swift      # Truy vấn Spotlight, bộ lọc và xếp hạng kết quả
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
│           ├── DownloadsView.swift        # Giao diện quản lý tác vụ tải xuống
│           ├── FileSearchView.swift       # Giao diện tìm tệp nhanh
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
