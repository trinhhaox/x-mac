# Xmac UI Redesign — Control Deck

## Mục tiêu

- Đồng bộ giao diện với icon Xmac mới mà không thay đổi luồng nghiệp vụ.
- Đưa trạng thái hệ thống và hành động thường dùng lên trước.
- Giảm cảm giác “nhiều card mặc định”, tăng nhận diện bằng sidebar và vật liệu xuyên suốt.

## Hướng thiết kế

**Bắc cực:** dùng Xmac như một bảng điều khiển macOS chính xác, sáng rõ và luôn sẵn sàng.

- Phẩm loại: tiện ích hệ thống / control center cho macOS.
- Người dùng mở app để kiểm tra trạng thái, bật hoặc chạy nhanh một công cụ.
- Cấu trúc giữ sidebar quen thuộc của ứng dụng macOS, nhưng biến sidebar thành phần nhận diện thương hiệu thay vì dùng mặc định của `NavigationSplitView`.
- Nền sidebar lấy trực tiếp từ icon: midnight indigo → cobalt; cyan chỉ dành cho mục đang chọn và hành động chính.
- Vùng làm việc dùng nền lạnh thích ứng Light/Dark Mode; card trắng/kính có viền xanh rất nhẹ.
- SF Symbols là bộ icon duy nhất; xanh lá, cam và đỏ chỉ dùng cho trạng thái hệ thống.

## Hệ thống thị giác

- Brand blue: `#147AF9`
- Brand indigo: `#1F3DD1`
- Brand cyan: `#24C7FA`
- Brand violet: `#784CFA`
- Sidebar navy: `#071038`
- Góc card: 18 pt; nút: 10 pt; item sidebar: 11 pt.
- Tiêu đề dùng SF Rounded; nội dung và điều khiển dùng SF Pro hệ thống.

## Chuyển động

1. Nút chính/phụ co về `0.97–0.98` khi nhấn và trở lại trong 140 ms.
2. Mục sidebar đổi nền, màu icon và chấm cyan trong 220 ms khi chuyển module.
3. Nội dung trang xuất hiện bằng opacity + dịch chuyển 10 pt trong 320 ms; banner và nhóm mở rộng dùng transition theo hướng phát sinh.

## Phạm vi và kiểm tra

- Màn hình mục tiêu: cửa sổ macOS từ 900×600, mặc định 1060×700.
- Các trang: Tổng quan, Cut & Paste, Ổ đĩa & NTFS, Bộ gõ, Dọn rác, Gỡ ứng dụng, Cài đặt.
- Không đổi hành vi xử lý file, mount ổ đĩa, bộ gõ hoặc xóa dữ liệu.
- Văn bản đã rút gọn: mô tả trang dài, tiêu đề lặp “Xmac Control Center”, các đoạn giải thích trùng với nhãn điều khiển.
