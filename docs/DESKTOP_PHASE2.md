# Mở nhanh và bảng điều khiển Menu Bar

## Bảng mở nhanh

- Phím mặc định **⌥⇧Space**, có thể đổi sang **⌃⌥Space** hoặc **⌘⌥K** trong
  Cài đặt → Mở nhanh. Dùng Carbon hot key, không cần quyền Trợ năng.
- Đăng ký phím mới trước khi nhả phím cũ. Nếu không đăng ký được, giữ lại phím
  cũ và hiển thị lỗi trong Cài đặt. Không ghi đè phím của ứng dụng khác.
- Tìm các trang chức năng Xmac và lệnh chuyển Tiếng Việt/English; tìm ứng dụng
  trong `/Applications`, `/System/Applications`, `~/Applications`; tìm tệp
  qua Spotlight sau khi nhập từ hai ký tự.
- Tìm lệnh/ứng dụng không phân biệt hoa thường hoặc dấu tiếng Việt. Xếp hạng
  tên chính xác, tiền tố rồi kết quả chứa từ. Giới hạn 20 lệnh/ứng dụng và
  10 tệp; khả năng tìm tệp phụ thuộc chỉ mục và quyền Spotlight.
- **↑/↓** chọn, **Enter** mở, **Esc** hoặc chuyển focus đóng bảng. Phím chọn
  ứng viên của bộ gõ hệ thống không bị launcher chặn khi đang có marked text.
- Dùng NSPanel không kích hoạt ứng dụng, xuất hiện ở màn hình chứa con trỏ,
  theo Space hiện tại; đóng bảng trả bàn phím về ứng dụng trước đó.
- Quét danh sách app ở nền, cache 60 giây. Không đi vào nội dung app bundle.
- Bảng mở nhanh có FileSearchEngine riêng. Đóng hoặc đổi truy vấn hủy công
  việc đang chờ và query của launcher, không can thiệp trang Tìm tệp nhanh.
- Lệnh cần quyền Trợ năng vẫn kiểm tra quyền; khi thiếu quyền, mở Cài đặt.
  Không có lệnh dọn/xóa tệp tự động trong bảng mở nhanh.

## Menu Bar

- **Nhấp trái** mở popover: trạng thái bộ gõ và mạng, tối đa 3 tác vụ tải
  đang chạy/chờ mạng, tiến trình và tạm dừng, tùy chọn giữ máy thức, tối đa 4
  ổ ngoài với dung lượng khả dụng, mở Finder và ngắt kết nối.
- Ngắt kết nối cần xác nhận; Finder/Eject bị vô hiệu hóa khi ổ chưa mount.
- Nút “Xem tất cả” và “Quản lý” mở trang chức năng đầy đủ; các nút dưới cùng
  mở Bảng điều khiển, Tìm tệp hoặc Cài đặt.
- **Nhấp phải** vẫn mở menu đầy đủ cũ, thêm mục mở bảng lệnh.
- Mở launcher đóng popover và ngược lại để không tranh focus.

## Kiểm thử

`./Scripts/test.sh` kiểm tra tìm không dấu, thứ tự xếp hạng, phát hiện app
trong Utilities, loại trừ app lồng trong bundle và hủy truy vấn launcher
độc lập. `./Scripts/build.sh` dựng app universal và DMG.

Trong phiên desktop local, chạy thêm:

```sh
XMAC_TEST_APP="$PWD/build/Xmac.app" XMAC_TEST_LAUNCHER_UI=1 ./Scripts/test.sh
```

Các kiểm thử UI chỉ bật theo biến môi trường: kiểm tra đăng ký hotkey thật,
giữ phím cũ khi phím mới bị chiếm, mở panel, truy vấn và Esc, rồi nhả hotkey
và khôi phục tùy chọn đã lưu. Render panel được ghi ở
`/tmp/xmac-launcher-preview.png`. Không khởi động event tap hoặc bộ gõ mới
trong tiến trình kiểm thử.
