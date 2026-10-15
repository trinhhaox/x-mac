# Xmac 1.4.1

## Giao diện gọn và đồng bộ hơn

- Thông tin hệ thống: bố cục hai cột cho CPU, RAM, mạng và ổ đĩa; biểu đồ nhỏ gọn, tỷ lệ RAM trực quan, phân biệt rõ dung lượng đã dùng và còn trống.
- Chi tiết cách đo được thu gọn; trạng thái tạm dừng, chờ mẫu và lịch sử CPU cũ được ghi rõ.
- Menu Bar: đồng bộ màu sáng/tối, tự co chiều cao theo nội dung, giữ thanh mở nhanh và điều hướng luôn hiển thị.
- Chọn ngôn ngữ trực tiếp, hướng dẫn cấp quyền Trợ năng rõ ràng; thao tác tải xuống và ổ đĩa có nhãn, trạng thái và giới hạn hiển thị phù hợp.

## Phạm vi và kiểm chứng

- Giữ nguyên cơ chế lấy dữ liệu, tải xuống, bộ gõ và xác nhận tháo ổ đĩa. Nhiệt độ theo độ C chưa được hỗ trợ; chỉ hiển thị trạng thái nhiệt của macOS.
- Bộ kiểm thử giao diện Thông tin hệ thống và Menu Bar: 12 kiểm thử đạt trong ba lần chạy liên tiếp trên máy phát triển.
- Bản universal cho Apple Silicon và Intel, yêu cầu macOS 13 trở lên. Chưa kiểm thử chạy thực tế trên máy Intel.
- Bộ cài được tạo và kiểm chứng bởi CI. Ký ad-hoc, chưa có Developer ID/notarization; macOS có thể yêu cầu cho phép mở ứng dụng.
- Việc phát hành không tự cài đè ứng dụng đang chạy trên máy.
