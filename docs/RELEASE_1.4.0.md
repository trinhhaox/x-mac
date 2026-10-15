# Xmac v1.4.0 — System Monitor & Desktop Tools

## Tính năng mới

- **Thông tin hệ thống:** CPU toàn máy và biểu đồ, RAM/wired/nén/swap,
  dung lượng volume người dùng, tốc độ nhận/gửi Wi-Fi/Ethernet. Cập nhật
  mỗi 2 giây, có tạm dừng và chỉ lấy mẫu khi mở trang.
- **Lịch sử clipboard:** tìm kiếm, ghim, chép lại văn bản/HTML, ảnh hoặc
  danh sách tệp. Mặc định tắt; giới hạn dung lượng, thời gian lưu và loại
  trừ các marker nhạy cảm/ứng dụng quản lý mật khẩu được cấu hình.
- **Sắp xếp Downloads:** xem trước theo nhóm định dạng, xác nhận trước
  khi di chuyển, không ghi đè, lưu nhật ký hoàn tác. Theo dõi thư mục chỉ
  cập nhật bản xem trước, không tự chuyển tệp.
- **Máy tính trong Mở nhanh:** nhập `= (12 + 3) / 5`, Enter chép kết quả.
  Hỗ trợ cộng/trừ/nhân/chia, dấu âm, ngoặc và số thập phân.

## An toàn và giới hạn

- Nhiệt hiện là **trạng thái nhiệt macOS**, chưa hỗ trợ nhiệt độ **°C**.
- Tốc độ mạng là lưu lượng thực tế qua các giao diện `en*`, không phải
  speed test hoặc tốc độ gói Internet. RAM dùng là số ước tính.
- Lịch sử clipboard lưu JSON **không mã hóa** trên máy, quyền tệp 0600.
  Lọc nội dung nhạy cảm là best-effort, không bảo đảm phát hiện mọi mật khẩu.
- Không quét sâu thư mục Downloads; tệp mới sửa trong 5 giây bị bỏ qua.
  Không bảo đảm phát hiện mọi tiến trình đang ghi tệp; cần kiểm tra preview.
- Máy tính hiển thị tối đa 12 chữ số có nghĩa, không dùng cho tài chính
  yêu cầu độ chính xác thập phân tuyệt đối.
- Bộ cài universal **Apple Silicon + Intel**, macOS 13 trở lên. Ký **ad-hoc**,
  chưa có Developer ID/notarization; macOS có thể yêu cầu xác nhận mở app.
- Phát hành không tự cài đè phiên bản đang dùng.

## Kiểm thử

76 kiểm thử gồm phép tính, parser Mach/sysctl, đọc số liệu máy thực,
clipboard cô lập, di chuyển/hoàn tác tệp tạm, giao diện native và cài thử
bundle vào thư mục tạm. Kiểm tra chữ ký, hai kiến trúc và checksum DMG.
Chưa kiểm chứng chạy trực tiếp trên máy Intel.
