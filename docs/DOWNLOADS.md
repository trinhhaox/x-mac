# Trung tâm tải xuống Xmac

## Phạm vi hiện tại

Phiên bản đầu dùng `URLSessionDownloadTask` của macOS để tải HTTP/HTTPS mà không cần tiến trình hoặc thư viện bên ngoài.

- Thêm tối đa 20 URL mỗi lần.
- Chọn thư mục lưu bằng `NSOpenPanel`.
- Theo dõi dung lượng và tiến độ.
- Tạm dừng, tiếp tục, hủy, thử lại và mở tệp trong Finder.
- Lưu lịch sử bằng `UserDefaults`; tác vụ đang chạy được khôi phục về trạng thái tạm dừng sau khi app mở lại.
- Thông báo hoàn tất hoặc thất bại qua `UserNotifications`.
- Chỉ chấp nhận HTTP/HTTPS, chỉ theo redirect HTTP/HTTPS và coi HTTP ngoài khoảng 2xx là lỗi.
- Chuẩn hóa tên tệp từ máy chủ và tự tăng hậu tố khi đích đã tồn tại.

## Tham khảo Motrix MyGo

Thiết kế sản phẩm tham khảo các khái niệm trong [`missuo/motrix-mygo`](https://github.com/missuo/motrix-mygo): danh sách tác vụ theo trạng thái, tìm kiếm, hộp thêm nhiều liên kết, thư mục đích, chi tiết tiến độ và thông báo kết quả.

Xmac không sao chép mã nguồn hoặc tài sản từ repository này. Repository không công bố license tổng thể qua metadata GitHub, còn engine `aria2` mà dự án sử dụng được ghi rõ là GPL-2.0-or-later và chạy như một tiến trình riêng. Vì vậy phiên bản hiện tại được triển khai độc lập bằng API Apple và không bundle `aria2`.

## Chưa nằm trong phạm vi

- Magnet, BitTorrent và FTP.
- Chọn tệp bên trong torrent.
- Giới hạn tốc độ, lịch tốc độ và proxy.
- Download background sau khi tiến trình Xmac thoát hoàn toàn.
- Tự cập nhật ứng dụng.

Các khả năng phụ thuộc `aria2` chỉ nên được bổ sung sau khi chốt mô hình phân phối, nghĩa vụ GPL, ký/notarize binary và quy trình cập nhật engine.

## Kiểm tra

`DownloadManagerTests` xác minh URL scheme/host, làm sạch tên tệp và không ghi đè khi trùng tên. Kiểm tra end-to-end dùng HTTP server local, tải tệp thật vào thư mục tạm và so sánh SHA-256 nguồn/đích.

## Chuyển động giao diện

1. Nút chính/phụ dùng phản hồi nhấn 140 ms từ hệ thống component chung.
2. Bộ lọc trạng thái dùng segmented control native để chỉ báo lựa chọn di chuyển liên tục.
3. Tác vụ mới trượt nhẹ từ trên xuống và fade trong 240 ms; progress thay đổi trong 200 ms, còn lần đầu mở trang dùng page entrance chung 320 ms.
