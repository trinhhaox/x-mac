# Đồng bộ bảng Menu Bar Xmac

## Phạm vi

Chỉnh bảng popover nhấp trái theo ảnh người dùng; giữ menu chuột phải,
backend tải xuống, bộ gõ, quyền và quản lý ổ đĩa. Đồng bộ với thiết kế
trang Thông tin hệ thống trong phiên bản 1.4.1; không tự cài đè.

## UX/UI

- Giữ font hệ thống/SF Symbols, xanh Xmac và nền sáng/tối cùng hệ thống.
  Dùng nhóm bo góc nhỏ hơn màn hình chính để phù hợp popover rộng 380pt.
- Đầu bảng: nhấp Xmac để mở Tổng quan; nút Mở nhanh hiển thị phím tắt
  đang cấu hình. Trạng thái mạng luôn có chữ, không chỉ có biểu tượng.
- Khi thiếu Trợ năng, hiển thị nút **Cấp quyền** dẫn tới trang quyền của
  macOS. Không tạo nút đổi bộ gõ bị khóa mà không có đường xử lý rõ ràng.
  Khi đã cấp quyền, chọn trực tiếp Tiếng Việt/English bằng hai nút.
- Nhóm tải và ổ đĩa có số lượng, lối mở trang đầy đủ và trạng thái trống
  ngắn. Giới hạn hiển thị 3 tác vụ đang tải/chờ mạng, 4 ổ ngoài; số đếm
  vẫn tính tất cả, các mục vượt giới hạn xem ở trang đầy đủ.
- Tên tệp dài cắt giữa, có tooltip đầy đủ. Tạm dừng có nhãn accessibility
  riêng cho từng tệp. Giữ cách xử lý tổng dung lượng chưa biết, không giả 0%.
- Công tắc giữ máy thức đặt ở mép phải. Tiếp tục dùng binding hiện có,
  không thay đổi ý nghĩa tùy chọn hoặc dữ liệu lưu của người dùng.
- Chưa mount/đang eject: khóa Finder và Eject, vẫn giữ xác nhận trước khi
  eject thật. Kết quả thành công/lỗi hiển thị trong bảng như trước.
- Cuối bảng luôn có Hệ thống, Tìm tệp, Cài đặt. Header/footer không cuộn;
  chỉ vùng giữa cuộn khi nhiều tác vụ hoặc ổ đĩa.

## Chiều cao

Bỏ khung trống cố định 560pt. Đo chiều cao nội dung bằng GeometryReader,
cập nhật qua onAppear/onChange, giới hạn vùng cuộn theo màn hình. Controller
dùng `NSHostingController.sizingOptions = [.preferredContentSize]` (macOS 13+)
để NSPopover cập nhật theo kích thước thật, không chỉ thay khung SwiftUI.

Kiểm tra giới hạn popover 480pt với dữ liệu cô lập:

- Thiếu quyền, không có tác vụ/ổ: 431.5pt.
- Đã cấp quyền, không có tác vụ/ổ: 439.5pt.
- Nhiều tác vụ và ổ: 466pt, cuộn giữa; footer vẫn ở cuối popover.
- NSPopover thật tăng chiều cao khi có dữ liệu và co lại khi dữ liệu rỗng.

## Kiểm chứng

`Tests/MenuBarDashboardTests.swift` kiểm tra lọc dữ liệu, render sáng/tối,
nhiều mục, ổ chưa mount, cuộn xuống cuối, NSPopover thật và sự kiện từ
NSSwitch với binding giả. Không truy cập clipboard, tải tệp hoặc eject ổ thật.
Snapshot và callback được tiêm riêng để test không khởi tạo các singleton
quyền/bộ gõ hoặc thay đổi UserDefaults của người dùng.

SwiftUI không cung cấp cây accessibility ảo trong test runner hiện tại;
chưa tự động bấm tất cả các nút qua AX. Không tuyên bố đã kiểm chứng thao
tác người dùng/confirmation của eject thật. Code xác nhận và các guard
mounted/ejecting được giữ lại ở adapter sản phẩm.

Không thêm hoạt ảnh tùy chỉnh hay biểu đồ giả trong popover. Dùng phản hồi
control và mở/đóng NSPopover native. Ảnh tĩnh không chứng minh chất lượng
chuyển động; chưa có video thử chuột/bàn phím trên app đang cài.

Ảnh kiểm tra chứa dữ liệu fixture, không phải tác vụ/ổ thật. Ảnh trước/sau
và log đặt trong `build/menubar-redesign/` (Git bỏ qua); ảnh render tạm là
`/tmp/xmac-menubar-{permission,ready-dark,busy,busy-scrolled}.png`.

Sau chỉnh cuối, nhóm MenuBar 4/4 đạt; chạy cùng SystemMonitor cho kết quả
12/12 ở ba lượt liên tiếp sau chỉnh câu trạng thái trống
(`xmac-ui-final1.log`, `xmac-ui-final2.log`, `xmac-ui-final3.log`).
Swift format lint và git diff check đạt. Không chạy production build hoặc
toàn bộ test suite trong thay đổi giao diện này.

Chủ task đã xem các ảnh sáng/tối, nhiều tác vụ và sau khi cuộn. Đã yêu cầu
rà soát hình ảnh độc lập nhưng lượt đó chưa trả kết quả và đã được dừng;
không ghi điểm đánh giá hoặc coi đây là chứng nhận UX độc lập.
