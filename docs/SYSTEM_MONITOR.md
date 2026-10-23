# Thông tin hệ thống

Mở **Thông tin hệ thống** ở sidebar hoặc tìm tên trang trong Mở nhanh.
Trang dùng bố cục và các thành phần gốc của Xmac: CPU là thông tin chính,
RAM, mạng, lưu trữ và nhiệt là các khối phía dưới. Hỗ trợ sáng/tối và vùng
nội dung tối thiểu rộng 672pt trong cửa sổ Xmac 900pt.

## Số liệu và giới hạn

- **CPU:** chênh lệch tick user/system/nice/idle từ Mach host statistics.
  Trung bình tất cả nhân, thang 0–100%, không phải CPU riêng của Xmac.
  Mẫu đầu chưa có tỷ lệ; sau 2 giây hiển thị số và biểu đồ tối đa 30 mẫu.
  Xử lý tràn bộ đếm UInt32. Không hiển thị tần số CPU; CPU theo tiến trình xem mục bổ sung bên dưới.
- **RAM:** tổng RAM vật lý; ước tính dùng = active + wired + compressed,
  giới hạn không vượt RAM vật lý. Hiển thị riêng wired, nén và swap.
  Đây không phải phép đo áp lực bộ nhớ và có thể khác Activity Monitor.
- **Mạng:** bộ đếm byte 64-bit từ `NET_RT_IFLIST2`, tính byte/giây theo
  thời gian uptime giữa hai mẫu; giao diện `en*` đang UP (Wi-Fi/Ethernet).
  Không cộng tunnel VPN, loopback, bridge hoặc giao diện ngang hàng.
  Không phải speed test, tốc độ link hoặc tốc độ riêng từng ứng dụng.
  Bộ đếm reset/giao diện mới cần thiết lập lại mốc; không tạo tốc độ âm.
  Giao diện khác tên `en*` không được tính và được ghi rõ trên màn hình.
- **Lưu trữ:** tổng/trống của volume chứa home; không cộng các volume APFS
  dùng chung container. Không gồm ước tính dung lượng có thể thu hồi.
- **Nhiệt:** dùng `ProcessInfo.thermalState` (bình thường/ấm/nóng/rất nóng).
  **Chưa đọc nhiệt độ °C**. Không giả lập cảm biến hoặc đổi trạng thái thành
  số độ; chưa tích hợp SMC/HID riêng cho từng đời máy hay helper đặc quyền.

Không cần quyền quản trị, không chạy subprocess, không gửi dữ liệu hoặc lưu
lịch sử xuống đĩa. Khi đóng/chuyển trang hoặc nhấn Tạm dừng, dừng lấy mẫu.
Tiếp tục bắt đầu lại mốc CPU/mạng. Khoảng mẫu quá 10 giây (ví dụ sau ngủ)
bị bỏ để tránh hiển thị lưu lượng trung bình sai. Lỗi đọc hiển thị trạng thái
không đọc được hoặc đang chờ mẫu, không thay bằng số 0 giả.

## Kiểm chứng

`Tests/SystemMonitorTests.swift` kiểm tra phép tính CPU, tràn tick, tốc độ
mạng, reset bộ đếm, đổi giao diện, khoảng thời gian không hợp lệ, giới hạn
lịch sử, tạm dừng/tiếp tục và đọc Mach/sysctl thật không quyền quản trị.
Kiểm thử parser có bản tin địa chỉ ngắn đứng trước giao diện và bộ đếm
vượt 4 GiB. Kiểm tra live đối chiếu danh sách `en*` UP với `getifaddrs`.

```sh
XMAC_TEST_MONITOR_UI=1 ./Scripts/test.sh
# Chạy lại riêng nhóm kiểm thử sau khi đã biên dịch:
XMAC_TEST_MONITOR_UI=1 swift test --skip-build --filter SystemMonitorTests
```

UI test dựng cửa sổ native, chụp light 900×1500 và dark 672×600 với số liệu
thật. Ảnh local: `/tmp/xmac-system-monitor-full.png`,
`/tmp/xmac-system-monitor-compact.png`; không đưa dữ liệu máy vào Git.
Đã tự kiểm tra hình ảnh; chưa đánh giá độc lập. Giữ hiệu ứng vào trang và
phản hồi nút native hiện có; biểu đồ cập nhật không tween để tránh làm sai
cảm giác về số liệu. Không thêm hiệu ứng trang trí hoặc giảm cỡ chữ để nhét
nội dung. Tính năng có từ v1.4.0, bundle universal arm64/x86_64 và DMG
ký ad-hoc; chưa notarize. Phát hành không tự thay bản đang cài.

Kết quả: toàn bộ 76/76 kiểm thử đạt; nhóm SystemMonitor 7/7 đạt trong
3 lần chạy liên tiếp (lần đầu trong toàn bộ suite, hai lần sau chạy riêng).
Đã đặt nhãn trục CPU với anchor chuẩn của Charts; lượt kiểm thử giao diện
sau sửa không còn cảnh báo anchor tự động. Chưa kiểm chứng chạy trên máy Intel.
Build Intel có cảnh báo từ SDK về thư viện compatibility chỉ chứa arm64;
link vẫn thành công, universal binary chứa đủ hai kiến trúc. DMG checksum hợp lệ.


## Bổ sung (đọc/ghi ổ đĩa, pin, tiến trình)

- **Đọc/ghi ổ đĩa:** cộng bộ đếm `Bytes (Read/Write)` của mọi `IOBlockStorageDriver`
  (cả ổ ngoài), tính byte/giây như mạng; bộ đếm giảm (rút ổ) thì bỏ mẫu đó.
- **Pin:** đọc registry `AppleSmartBattery` (không cần quyền). Tình trạng =
  `AppleRawMaxCapacity` (hoặc `NominalChargeCapacity` trên Intel) / `DesignCapacity`.
  Máy không có pin thì ẩn thẻ. Không đọc nhiệt độ pin.
- **Tiến trình dùng CPU nhiều nhất:** `proc_listallpids` + `proc_pid_rusage`, chênh lệch thời
  gian CPU giữa hai mẫu (đổi đơn vị Mach → ns), % theo một nhân. Chỉ thấy tiến trình
  của người dùng hiện tại; PID mới hoặc bị tái sử dụng (đổi tên) bị bỏ qua.

Vẫn không chạy subprocess, không cần quyền quản trị, không lưu số liệu.
