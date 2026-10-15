# Tiện ích desktop - đợt 1

## Cập nhật ứng dụng

Mở **Cài đặt → Cập nhật ứng dụng**, hoặc **Menu Bar → Kiểm tra cập nhật**.
Xmac đọc GitHub Releases của `trinhhaox/x-mac`, chỉ nhận bản chính thức mới
hơn phiên bản đang chạy (định dạng `major.minor.patch`). Tự kiểm tra mỗi ngày
là lựa chọn người dùng bật; mặc định tắt. Việc cài luôn cần xác nhận.

Tài sản phải mang tên `Xmac-<version>.dmg`, nằm trong đúng release và có
`digest` SHA-256 từ GitHub. Bộ cài được tải với tiến trình, đối chiếu kích thước
và hash, mount chỉ đọc, kiểm tra bundle ID `vn.xmac.app`, phiên bản và
`codesign --verify --deep --strict` trước khi thay app. Không có checksum thì
từ chối cài trong app; vẫn có liên kết trang phát hành.

Đây là mô hình tin cậy GitHub Releases qua HTTPS + checksum do GitHub cung
cấp. Chữ ký ad-hoc chỉ xác minh tính toàn vẹn bundle, không chứng minh danh
tính nhà phát hành. Chưa có feed ký bằng khóa độc lập hoặc notarization mới;
không tạo khóa/chứng thư. Khi có Developer ID, quy trình phát hành hiện có
vẫn hỗ trợ ký/notarize qua `Scripts/build.sh`.

Chỉ thay app ở `/Applications/Xmac.app` hoặc `~/Applications/Xmac.app` khi
thư mục có quyền ghi. Bản mới được chuẩn bị ở cùng thư mục rồi mới đổi tên;
nếu đổi tên thất bại thì đưa bản cũ về lại. Bản cũ được giữ dưới tên
`Xmac-before-update-<UUID>.app` để khôi phục thủ công. Chưa tự phát hiện crash
và rollback sau khi bản mới khởi chạy. Sau cập nhật có thể cần bật lại quyền
Trợ năng do đổi chữ ký. Xmac không dùng sudo hoặc yêu cầu mật khẩu admin.

## Giữ máy thức

**Cài đặt → Tải xuống → Giữ máy thức khi đang tải** mặc định bật. Xmac giữ
một activity token khi có tải đang chạy và mạng online. Token được nhả khi
tải hết, dừng, hủy, chờ mạng hoặc thoát app. Màn hình vẫn được phép tắt;
không ngăn sleep do đóng nắp hoặc người dùng chủ động cho máy ngủ.

## Phục hồi tải theo kết nối

`NWPathMonitor` cung cấp trạng thái online và mạng expensive/constrained.
Tác vụ chờ hiển thị **Chờ kết nối**, nằm trong bộ lọc **Đang tải**, không bị
xóa bởi **Xóa lịch sử**. Cấu hình tránh mạng tính phí mặc định tắt; khi bật,
tải chờ đến khi có mạng phù hợp hoặc người dùng bỏ tùy chọn.

Chỉ lỗi kết nối tạm thời được tự thử lại, tối đa 3 lần với khoảng chờ
1/2/4 giây. HTTP lỗi, lỗi chứng thư, lỗi ghi file và người dùng hủy không
được tự thử lại. Resume data được tận dụng nếu URLSession cung cấp; nếu
không có, tác vụ tải lại từ đầu. Tác vụ tự dừng/hủy không tự khởi chạy khi
mạng trở lại. Khi thoát app, tải đang chạy được lưu thành tạm dừng để người
dùng tiếp tục ở lần mở sau; không hứa tiếp tục từng byte qua lần khởi động.

## Kiểm tra

```sh
./Scripts/test.sh
./Scripts/build.sh
XMAC_TEST_APP="$PWD/build/Xmac.app" ./Scripts/test.sh
```

Kiểm thử dùng URLProtocol mô phỏng transport HTTP thực của URLSession,
không tải file Internet hay thay ứng dụng đang cài. Có kiểm thử offline →
online → ghi file hoàn tất, lỗi mạng → tự thử lại, giữ trạng thái người dùng,
chính sách mạng tính phí, phiên bản release, checksum và rollback khi thay
bundle lỗi. Biến `XMAC_TEST_APP` bật thêm smoke test cài bundle có chữ ký
vào thư mục tạm và xác nhận giữ nguyên bản cũ.
