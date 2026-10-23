# Dọn rác & gỡ ứng dụng — mô hình an toàn

Ý tưởng tham khảo từ [tw93/Mole](https://github.com/tw93/Mole) (GPL-3.0); toàn bộ mã Xmac được viết lại bằng Swift, không chép mã hay danh sách đường dẫn của Mole.

## Thứ tự kiểm tra trước khi dọn một mục (`CleanerEngine.decide`)
1. `CleanerPathPolicy`: mục phải nằm dưới một gốc cho phép. Gốc chỉ được tin khi không thành phần nào dưới thư mục home là symlink (`HomePathGuard.trustedRoot`), nên `~/Library/Caches` bị trỏ sang `~/Documents` sẽ bị từ chối.
   - Gốc "con bất kỳ": `Library/Caches`, `Library/Logs`, Xcode DerivedData, `.Trash`, iOS DeviceSupport, CoreSimulator/Caches.
   - Đường dẫn chính xác: cache công cụ lập trình trong `DeveloperCacheCatalog`.
   - Gốc "chỉ con trực tiếp mang tên bundle id": Application Support, Preferences, Saved Application State, HTTPStorages, WebKit (dữ liệu sót lại).
2. Danh sách bảo vệ (`cleaner-whitelist.json`): mục, thư mục cha hoặc tệp con được bảo vệ → bỏ qua. Tệp hỏng → dừng toàn bộ lần dọn. Danh sách được đọc lại ngay trước khi chuyển từng mục, nên bảo vệ trong lúc đang dọn vẫn có hiệu lực.
3. Mục trong Thùng rác → xóa vĩnh viễn; còn lại → chuyển vào Thùng rác.
4. Tên mục trùng bundle id ứng dụng đang chạy → bỏ qua.
5. `OpenFileSnapshot` (`lsof -u <uid>`, chụp một lần/lần dọn): mục hoặc tệp con đang mở → bỏ qua. Không chạy được `lsof` → bỏ qua mọi mục ngoài Thùng rác.

## Dữ liệu sót lại (`OrphanedAppDataScanner`)
Chỉ đề xuất khi: tên là bundle id; không cùng nhà phát hành (2 thành phần đầu, ví dụ `com.microsoft`) với bất kỳ bundle nào đang cài hoặc đang chạy (app, bộ gõ trong `Input Methods`, `PreferencePanes`, plug-in trong `/Library/Application Support`…); Launch Services không biết app đó; và **không tệp nào bên trong** thay đổi trong 30 ngày (duyệt tối đa 3 cấp / 2000 mục, vượt giới hạn thì coi như còn dùng). Không quét `~/Library/Containers` (gây hộp thoại quyền riêng tư) và `~/Library/Caches` (đã có ở mục User Caches). Luôn không chọn sẵn.

## Gỡ ứng dụng (`AppLeftoverLocator`)
Khớp đúng bundle id (hoặc LaunchAgent chạy mã trong bundle, `<TEAMID>.<id>`) → "Xác định", chọn sẵn. Khớp theo tiền tố `<id>.` (ByHost, LaunchAgents, `group.<id>.*`) có thể thuộc app anh em như `com.jetbrains.intellij.ce` → "Suy đoán", không chọn sẵn. LaunchAgent được `launchctl bootout` (tối đa 5 giây) trước khi chuyển vào Thùng rác.

## Khi lsof thất bại
`lsof` bị kill giữa chừng (không thoát bình thường, mã khác 0/1), quá 20 giây hoặc không trả về gì → coi như không biết, bỏ qua mọi mục ngoài Thùng rác và báo rõ cho người dùng. Đường dẫn giữ nguyên văn (tên như `iPhone14,5 16.4.1 (20E252)` có dấu ngoặc), so sánh không phân biệt hoa thường.

## Không đưa vào (cố ý)
Go module cache (tệp chỉ đọc, Thùng rác không dọn được), `~/.m2`, cache mô hình (Hugging Face…), mọi thứ ngoài thư mục home hoặc cần quyền admin.

## Nhật ký
`~/Library/Logs/Xmac/operations.log`, JSON Lines, xoay vòng ở 5 MB (`operations.log.1`). Thư mục `Logs/Xmac` không bao giờ xuất hiện trong mục dọn Logs.
