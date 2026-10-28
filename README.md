# Xmac - Tiện Ích Thiết Yếu Tất Cả Trong Một Cho macOS 

<p align="center">
  <b>Bộ tiện ích macOS hỗ trợ tải tệp, tìm tệp nhanh, Cắt/Dán file Finder, gắn ổ NTFS đọc-ghi qua helper bên ngoài, gõ Tiếng Việt, dọn rác và gỡ ứng dụng có kiểm soát.</b>
</p>

---

## 🌟 Tính Năng Nổi Bật

### Thông tin hệ thống (từ v1.4.0)
- Theo dõi CPU và biểu đồ, RAM/nén/wired/swap, dung lượng lưu trữ và tốc độ nhận/gửi qua Wi-Fi/Ethernet mỗi 2 giây.
- Tốc độ đọc/ghi ổ đĩa, tình trạng pin (mức pin, % so với thiết kế, số lần sạc) và 5 tiến trình của bạn dùng CPU nhiều nhất.
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
  - Cache công cụ lập trình nằm ngoài `~/Library/Caches`: npm, pnpm, Bun, uv, Gradle, Cargo, bản iOS DeviceSupport/CoreSimulator cũ.
  - Dữ liệu sót lại của ứng dụng đã gỡ (không còn cài, không thay đổi 30 ngày) — chỉ gợi ý, không chọn sẵn.
  - Các mục được chuyển vào Thùng rác (riêng mục đã ở trong Thùng rác bị xóa vĩnh viễn).
  - **Không đụng tới mục đang được dùng**: kiểm tra tệp đang mở bằng `lsof` trước khi dọn; nếu không kiểm tra được thì bỏ qua thay vì đoán.
  - **Bảo vệ & lịch sử**: nhấp phải để luôn giữ một mục; mọi thao tác dọn/gỡ được ghi vào `~/Library/Logs/Xmac/operations.log` và xem lại trong "Lịch sử & bảo vệ".
- **Giải phóng bộ nhớ RAM (Purge Memory)**: Nút giải phóng RAM Inactive tức thì giúp máy tính nhẹ và mượt mà hơn.
- **Gỡ ứng dụng có kiểm soát (App Uninstaller)**:
  - Tự động dò tìm toàn bộ các file phụ trợ nằm ẩn sâu trong thư viện: `Application Support`, `Caches`, `Preferences .plist` (cả `ByHost`), `Saved State`, `WebKit`, `HTTPStorages`, `Cookies`, `Logs`, `Sandbox Containers`, `Group Containers`, `Application Scripts`, `LaunchAgents`.
  - Launch Agent của ứng dụng được gỡ khỏi launchd trước khi chuyển vào Thùng rác để không tự chạy lại.
  - Tính toán tổng dung lượng thực tế của ứng dụng.
  - Mặc định chọn các đường dẫn xác định bằng bundle identifier; đường dẫn suy đoán theo tên ứng dụng phải được người dùng chọn thủ công.
  - Từ chối gỡ khi ứng dụng đang chạy; gỡ được cả ứng dụng Apple cài trong `/Applications` (Xcode, Pages…), chỉ chặn ứng dụng hệ thống.
  - Chuyển app bundle vào Thùng rác trước; nếu thất bại thì không đụng tới file phụ trợ, và báo rõ file phụ trợ nào chưa chuyển được.

### 7. 🗂️ Hợp Nhất Tệp CoW APFS (Storage Deduplication)
- **Tiết kiệm dung lượng không cần xóa tệp**: Tận dụng cơ chế Copy-on-Write nguyên bản của hệ thống tệp APFS (`clonefile(2)`), gộp các khối vật lý trùng nhau trên SSD về cùng một bản sao duy nhất trong khi giữ nguyên 100% đường dẫn và cấu trúc thư mục.
- **Pipeline 4 tầng siêu tốc**:
  - Quét hệ thống siêu tốc bằng `getattrlistbulk(2)` với buffer 256KB, giảm hàng triệu lệnh `lstat`.
  - Phân cụm kích thước & phân vùng (Size & Device Bucket).
  - Băm biên (Edge Hash) 4KB đầu + 4KB cuối của tệp.
  - Băm toàn phần SHA-256 đối với các tệp có cùng edge hash.
  - Đối soát từng byte sống (`memcmp` 128KB buffer) trước khi tiến hành hoán đổi.
- **An toàn tuyệt đối & Nguyên tử (Atomic Swap)**:
  - Bỏ qua tệp hệ thống có cờ bảo vệ đặc biệt (`SF_DATALESS`, `UF_COMPRESSED`, `UF_IMMUTABLE`, `SF_RESTRICTED`, `UF_TRACKED`).
  - Kiểm tra Extent vật lý qua `fcntl(fd, F_LOG2PHYS_EXT)` để nhận diện tệp đã chia sẻ khối, tránh xử lý lặp.
  - Bảo tồn toàn diện quyền POSIX, cờ tệp, Extended Attributes và timestamps (`btime`, `mtime`) chuẩn xác đến cấp nanosecond.
  - Sử dụng tệp clone tạm thời và syscall `rename(2)` để thay thế tức thì, không bao giờ để lại tệp hỏng.
- **Quét theo danh mục chuyên biệt (Category Filtering)**: Tùy chọn lọc nhanh theo nhóm tệp (Tất cả, Ảnh, Video, Mã nguồn, Tài liệu, Tệp nén). Khi chọn Mã nguồn, ngưỡng kích thước tối thiểu tự động hạ xuống 1 KB.
- **Lập lịch quét tự động định kỳ (Background Scheduler)**: Chạy ngầm định kỳ khi máy rảnh rỗi (Hàng ngày, Hàng tuần, Hàng tháng) và gửi thông báo hệ thống khi phát hiện lượng dung lượng trùng lặp vượt ngưỡng đã chọn (500MB - 5GB).
- **Nhật ký & Hoàn tác một chạm (Undo / Unfold)**:
  - Ghi nhận mọi giao dịch vào nhật ký JSONL tại `~/Library/Application Support/Xmac/dedup_journal.jsonl`.
  - Nút **"Hoàn tác tất cả"** khôi phục mọi tệp CoW trở lại trạng thái độc lập riêng biệt thông qua phép sao chép dữ liệu thật `copyfile(..., COPYFILE_DATA)`.

Chi tiết: [`docs/DEDUPLICATOR.md`](docs/DEDUPLICATOR.md).

### 8. 🔄 Chuyển Đổi Tệp
- **Không cần cài thêm**: ảnh (JPG, PNG, HEIC, TIFF, GIF, BMP, ICNS) kèm cắt ảnh, ảnh → PDF, PDF → ảnh/gộp/nén/tách trang/trích khoảng trang, OCR ảnh & PDF → văn bản, văn bản (DOCX, RTF, ODT, HTML, TXT), EPUB → TXT/HTML/DOCX/RTF, video/âm thanh (MP4, MOV, HEVC, 720p, M4A), nén ZIP và giải nén ZIP/TAR/7Z/ISO, phụ đề (SRT, VTT, ASS), phông TTF/OTF ↔ WOFF, mô hình 3D (OBJ, STL, PLY, USD + ảnh xem trước), dữ liệu bản đồ (GeoJSON, KML/KMZ, GPX, CSV).
- **Chuyển mã TCVN3/VNI → Unicode** cho TXT, SRT, HTML… và DOCX dùng phông `.VnTime`/`VNI-Times`.
- **Khi máy đã cài sẵn**: `ffmpeg` (`brew install ffmpeg`) mở thêm MKV, WEBM, AVI, GIF, MP3, FLAC, OGG, OPUS…; LibreOffice mở thêm Word/Excel/PowerPoint → PDF, DOC ↔ DOCX, XLS ↔ XLSX, PPT ↔ PPTX, HWP (đời cũ), DXF; app Pages/Numbers/Keynote xuất ra PDF, DOCX, XLSX, PPTX…; calibre mở thêm MOBI, AZW3, FB2… Xmac chỉ gọi các công cụ này, không đóng gói kèm.
- **Lưu cạnh tệp gốc**, không ghi đè (tự thêm hậu tố ` 1`, ` 2`); lỗi hoặc hủy thì không để lại tệp hỏng.
- **Lối vào**: tab "Chuyển đổi tệp", menu chuột phải Finder › Dịch vụ › "Chuyển đổi bằng Xmac", Mở nhanh "Chuyển đổi tệp đang chọn trong Finder", thả tệp lên icon Menu Bar, kéo ảnh/liên kết https từ trình duyệt, thư mục theo dõi (mặc định tắt), lệnh `xmac convert` (cài bằng `Xmac.app/Contents/MacOS/Xmac install-cli`).
- **Donut ⌃ + kéo (thử nghiệm, mặc định tắt)**: đang kéo tệp thì nhấn ⌃, vòng định dạng hiện ngay tại con trỏ; Tab hoặc cuộn chuột để lật mặt sau; thả lên một ô để chuyển đổi.
- **Nhận chữ từ vùng màn hình**: Mở nhanh hoặc chuột phải icon Menu Bar › "Nhận chữ từ vùng màn hình", chữ tiếng Việt/Anh được chép vào bộ nhớ tạm (cần quyền Ghi màn hình).

Chi tiết: [`docs/CONVERTER.md`](docs/CONVERTER.md).

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
1. Tải file `Xmac-1.11.2.dmg` từ phần Releases của GitHub hoặc thư mục `build/`.
2. Kéo thả `Xmac.app` vào thư mục `Applications`.
3. Mở ứng dụng và làm theo hướng dẫn cấp quyền.

### 2. Tự biên dịch từ mã nguồn (Build from source)
```bash
git clone https://github.com/trinhhaox/x-mac.git
cd x-mac
chmod +x Scripts/build.sh
./Scripts/build.sh
```
Sau khi hoàn tất, file `Xmac.app` và `Xmac-1.11.2.dmg` sẽ được tạo trong thư mục `build/`.

Mặc định script ký ad-hoc để kiểm thử local. Nếu máy đã có sẵn chứng thư và hồ sơ notarization trong Keychain, có thể tạo bản phát hành bằng:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: ..." \
NOTARY_PROFILE="xmac-notary" \
./Scripts/build.sh
```

Script không tạo hoặc thay đổi chứng thư/thông tin xác thực. Khi đặt `NOTARY_PROFILE`, quá trình build sẽ dừng nếu notarization hoặc stapling thất bại.

Nếu không có chứng thư Developer ID trong Keychain nhưng tài khoản Apple Developer (gói trả phí) đã đăng nhập trong Xcode, dùng Developer ID do Apple quản lý trên đám mây. Script ký trước bằng chứng thư Apple Development (để gắn entitlements), sau đó `Scripts/notarize-with-xcode.sh` ký lại bằng Developer ID, gửi notarize và staple:

```bash
CODE_SIGN_IDENTITY="Apple Development: ..." \
XCODE_NOTARIZE_TEAM="<team-id>" \
./Scripts/build.sh
```

Ở chế độ này DMG không được ký (chứng thư nằm trên đám mây); Gatekeeper kiểm tra `Xmac.app` đã staple bên trong.

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
2. **Tự động hoá (Automation)**: Cho phép `Xmac` điều khiển `Finder` khi xuất hiện thông báo cấp quyền lần đầu; tương tự với Pages/Numbers/Keynote khi chuyển đổi tệp iWork.
3. **Ghi màn hình (Screen Recording)**: Chỉ cần cho "Nhận chữ từ vùng màn hình".
4. **Quyền truy cập toàn bộ ổ đĩa (Full Disk Access - Khuyên dùng)**: Cho phép Xmac quét sạch bộ nhớ đệm sâu và file thừa khi gỡ ứng dụng.

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
│   │   ├── Converter/                     # Chuyển đổi tệp: registry, hàng đợi, 9 bộ chuyển đổi
│   │   │   └── Donut/                     # Vòng định dạng ⌃ + kéo tại con trỏ
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
