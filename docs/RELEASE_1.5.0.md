# Xmac 1.5.0

## Giao diện thống nhất và dễ tiếp cận hơn

- Chuẩn hóa header, ô nhập liệu, toggle row, list row, nút chính/phụ và nút nguy hiểm trên toàn ứng dụng.
- Tôn trọng Reduce Motion của macOS; bổ sung nhãn trợ năng cho toggle ẩn nhãn và các nút chỉ có biểu tượng.
- Tăng độ tương phản sidebar, chia điều hướng thành Tổng quan, Công việc và Hệ thống; giữ Cài đặt ở vị trí cố định.
- Tinh gọn Tổng quan, bỏ nội dung lặp và ưu tiên số liệu cùng tác vụ thường dùng.
- Thiết kế lại Clipboard, Sắp xếp Downloads, Cài đặt và Bộ gõ Tiếng Việt với phân cấp rõ ràng và danh sách gọn hơn.
- Gom kết quả Tìm tệp và tác vụ Tải xuống vào list surface thống nhất; phân biệt rõ thao tác thường và thao tác xóa/hủy.

## Phạm vi và kiểm chứng

- Giữ nguyên cơ chế tải xuống, tìm kiếm, clipboard, sắp xếp tệp, bộ gõ, NTFS, dọn rác và gỡ ứng dụng.
- 81 kiểm thử trong 17 test suite đạt; các snapshot Clipboard, Organizer, Settings, Bộ gõ và MainView được render ở kích thước desktop tối thiểu.
- Bản universal cho Apple Silicon và Intel, yêu cầu macOS 13 trở lên.
- Bộ cài ký ad-hoc, chưa có Developer ID/notarization; macOS có thể yêu cầu xác nhận cho phép mở ứng dụng.
- Việc phát hành không tự cài đè ứng dụng đang chạy trên máy.
