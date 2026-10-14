# Tìm tệp nhanh

Xmac dùng `NSMetadataQuery` và chỉ mục Spotlight có sẵn của macOS để tìm tệp. Tính năng được thiết kế độc lập sau khi tham khảo ngôn ngữ truy vấn và trải nghiệm tìm kiếm của [FSearch](https://github.com/noahdunnagan/fsearch) (MIT).

## Khả năng hiện tại

- Tìm theo tên trong Home, Downloads, Documents, Desktop, Applications hoặc một thư mục do người dùng chọn.
- Tìm trong nội dung văn bản mà Spotlight đã lập chỉ mục.
- Lọc bằng giao diện theo tệp, thư mục, tài liệu, hình ảnh, video, âm thanh và tệp nén.
- Hỗ trợ truy vấn nhanh: `ext:pdf`, `type:image`, `mtime:<7d`, `^prefix`, `suffix$`, `'exact` và `!exclude`.
- Mở kết quả, hiện trong Finder hoặc sao chép đường dẫn.
- Xếp hạng ưu tiên tên khớp chính xác, tiền tố và tệp được sửa gần đây.

## Ranh giới kỹ thuật

Xmac không đóng gói binary hoặc daemon của FSearch. Điều này giữ bản dựng Universal (`arm64` + `x86_64`), tránh thêm tiến trình nền và dùng mô hình quyền riêng tư sẵn có của Spotlight. Do đó phiên bản này chưa có fuzzy typo-tolerance, chỉ mục trigram riêng, trạng thái Git hoặc tốc độ cấp micro-giây trên toàn ổ đĩa như FSearch.

Spotlight có thể không trả về tệp trong vùng chưa được lập chỉ mục hoặc nơi Xmac chưa có quyền đọc. Bật “Trong nội dung” chỉ áp dụng cho loại tệp có metadata nội dung do Spotlight cung cấp.
