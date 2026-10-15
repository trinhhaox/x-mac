# Làm gọn trang Thông tin hệ thống

## Mục tiêu

Giữ nhận diện Xmac và số liệu hiện có, giúp đọc nhanh cả CPU, RAM, mạng,
lưu trữ và trạng thái nhiệt mà không cuộn qua từng thẻ toàn chiều ngang.
Thiết kế được đưa vào phiên bản 1.4.1; không tự cài đè bản đang chạy.

## Quyết định giao diện

- Hai cột: CPU/RAM ở hàng đầu, mạng/lưu trữ ở hàng thứ hai. Các thẻ trong
  cùng hàng có chiều cao tối thiểu bằng nhau nhưng vẫn nở theo nội dung.
- CPU là số chính và biểu đồ thang 0–100%; bỏ chấm tại từng mẫu khi đã có
  đường liên tục. RAM có vòng tỷ lệ và số dung lượng, nén/swap phía dưới.
- Nhận/gửi đặt cạnh nhau với nhãn hướng; dung lượng trống là số chính của
  lưu trữ, thanh luôn có nhãn phần trăm “đã dùng”. Giữ cảnh báo mạng không
  phải speed test và RAM chỉ là ước tính.
- Nhiệt là một dải trạng thái có chữ và màu; luôn ghi chưa có nhiệt độ °C.
- Bỏ eyebrow tiếng Anh và mô tả dài ở đầu trang. Build macOS, wired, công
  thức và giới hạn chi tiết được thu vào “Chi tiết & cách đo”, không xóa.
- Giữ nền, thẻ ModernCard, SF Symbols, font hệ thống và màu xanh của Xmac.
  Không thêm hình trang trí; chính số liệu, biểu đồ và tỷ lệ là nội dung.

## Trạng thái và chuyển động

- Tạm dừng/tiếp tục giữ nguyên hành vi lấy mẫu; có nhãn và thời điểm mẫu
  cuối. Không thay đổi SystemProbe hoặc quyền của ứng dụng.
- Không có số liệu dùng dấu — và giải thích trạng thái, không giả số 0.
  Khi còn đồ thị cũ nhưng thiếu mẫu CPU mới, ghi “Chờ mẫu mới” và “Lịch sử
  trước đó”. Khi tạm dừng, số CPU được ghi “Mẫu cuối”.
- Nút dùng phản hồi nhấn của BrandSecondaryButtonStyle hiện có.
- Vào trang: opacity + dịch 6pt trong 200ms; mở/đóng chi tiết: native
  DisclosureGroup, chuyển bố cục 180ms. Tôn trọng Reduce Motion cho hai
  chuyển động này; không tween số liệu hoặc tạo hiệu ứng lặp liên tục.
- Ảnh tĩnh không chứng minh chất lượng chuyển động hoặc thao tác chuột;
  chưa có video kiểm chứng ba hiệu ứng hoặc kiểm tra bật Reduce Motion
  qua System Settings. Kiểm thử trạng thái tĩnh có tắt animation transaction.

## Kiểm chứng local

Chạy riêng SystemMonitorTests với `XMAC_TEST_MONITOR_UI=1`, không chạy
production build hoặc thay ứng dụng đang dùng. UI test sử dụng cửa sổ
native, không khởi động bộ gõ hoặc chạm clipboard người dùng.

- Live: sáng 900×700 và tối 672×600, chờ mẫu CPU thật thay vì chờ cố định.
- Fixture: đồ thị 30 mẫu, tạm dừng, nhiệt nghiêm trọng, mở/đóng chi tiết,
  thiếu số liệu; xác nhận model giữ tối đa 30 mẫu và nil không trở thành 0.
- Preview fixture không phải số liệu máy của người dùng.
- Ảnh trước/sau và log local đặt trong `build/system-monitor-redesign/`
  (được Git bỏ qua). Test cũng ghi ảnh `/tmp/xmac-system-monitor-*.png`.

Lệnh chạy nhóm kiểm thử với plugin đã dùng trong Scripts/test.sh:

```sh
XMAC_TEST_MONITOR_UI=1 swift test \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  --filter SystemMonitorTests
```

Phát hành trong phiên bản 1.4.1 theo yêu cầu riêng của người dùng; không tự cài đè.

## Rà soát độc lập

Một lượt đánh giá hình ảnh, theo chế độ cải thiện giao diện hiện có, không
chấm điểm. Xác nhận đủ năm nhóm số liệu ở 672×600, không cắt chữ. Đã áp dụng
hai góp ý: nhãn thanh lưu trữ và phân biệt lịch sử CPU với mẫu hiện tại.
Đánh giá chỉ kiểm chứng hình ảnh tĩnh, không xác nhận hoạt ảnh hoặc thao tác chuột.

Kết quả sau chỉnh cuối: SystemMonitorTests đạt **8/8** ở cả ba lượt liên
tiếp (`xmac-monitor-redesign-verified1.log`, `verified2.log`, `verified3.log`).
Swift format lint và git diff check đều đạt. Không chạy lại toàn bộ suite.
