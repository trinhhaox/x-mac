# 🗂️ Hợp Nhất Tệp CoW APFS (Storage Deduplication via Copy-on-Write)

## 1. Giới thiệu
Tính năng **Hợp nhất tệp CoW (APFS Deduplicator)** trong `x-mac` giúp giải phóng dung lượng ổ đĩa SSD bằng cách tận dụng tính năng Copy-on-Write (CoW) nguyên bản của hệ thống tệp Apple File System (APFS).

Khác với các công cụ dọn dẹp truyền thống yêu cầu người dùng **xóa tệp**, cơ chế CoW Clone **giữ nguyên 100% tất cả các tệp, đường dẫn và cấu trúc thư mục**, nhưng trỏ các khối dữ liệu vật lý (physical extents) trên SSD về cùng một bản sao duy nhất. Khi một trong các tệp bị sửa đổi sau này, hệ thống tệp APFS sẽ tự động cấp phát khối mới chỉ cho phần dữ liệu thay đổi mà không làm ảnh hưởng đến các tệp còn lại.

---

## 2. Kiến trúc & Pipeline 4 Lớp

Hệ thống lọc tệp trùng lặp hoạt động theo quy trình 4 tầng lọc nhằm tối ưu tốc độ và an toàn tuyệt đối:

```
[ Cây Thư Mục ]
       │
       ▼  (getattrlistbulk(2) - Buffer 256KB)
[ Tầng 1: Phân cụm theo Size & Phân vùng (Device Bucket) ]
       │  (Bỏ qua các tệp có kích thước duy nhất)
       ▼
[ Tầng 2: Băm Biên (Edge Hash) ]
       │  (SHA-256 trên 4KB đầu + 4KB cuối của tệp)
       ▼
[ Tầng 3: Băm Toàn Phần (Full SHA-256) ]
       │  (Băm tuần tự khối 256KB đối với các ứng viên còn lại)
       ▼
[ Tầng 4: Đối Soát Từng Byte Sống (Live Byte-for-byte Verification) ]
       │  (memcmp buffer 128KB trực tiếp trước khi clone)
       ▼
[ APFS clonefile(2) + Atomic rename(2) ]
```

---

## 3. Các Nguyên Tắc An Toàn Cốt Lõi

1. **Kiểm tra khả năng phân vùng (Volume Capabilities):**
   - Chỉ kích hoạt trên các volume APFS có cờ `VOL_CAP_INT_CLONE`.
   - Ngăn chặn thao tác trên các phân vùng HFS+, FAT32, exFAT hoặc SMB shares.

2. **Cờ tệp bất khả xâm phạm (Untouchable Flags):**
   - Không xử lý các tệp có cờ hệ thống đặc biệt:
     - `SF_DATALESS` (iCloud Drive evicted / FileProvider chưa tải về)
     - `UF_COMPRESSED` (HFS/APFS transparent compression)
     - `UF_IMMUTABLE`, `SF_IMMUTABLE` (Tệp khóa chống sửa)
     - `UF_APPEND`, `SF_APPEND` (Tệp chỉ được nối)
     - `SF_RESTRICTED` (SIP / System Integrity Protection)
     - `UF_TRACKED` (Dataless download tracking)

3. **Tránh xử lý tệp đang mở / vừa sửa (Quiet Period):**
   - Bắt buộc tệp phải ổn định (không thay đổi `mtime` và `ctime`) trong ít nhất 5 phút trước khi tiến hành clone.

4. **Kiểm tra Extent vật lý đã chia sẻ (F_LOG2PHYS_EXT):**
   - Sử dụng syscall `fcntl(fd, F_LOG2PHYS_EXT)` để đọc vị trí khối vật lý trên SSD.
   - Nếu hai tệp đã chia sẻ khối CoW từ trước, hệ thống đánh dấu `.alreadyShared` và bỏ qua, tránh ghi đè lặp vô ích.

5. **Bảo toàn Metadata & Timestamps không cần Root:**
   - Dùng `copyfile(source, tempClone, nil, COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_NOFOLLOW)` để sao chép ACLs và Extended Attributes.
   - Dùng `chmod` và `chflags` áp dụng chính xác quyền POSIX và cờ tệp.
   - Dùng `setattrlist` với `ATTR_CMN_CRTIME | ATTR_CMN_MODTIME` theo chuẩn thứ tự bit kernel Darwin để sao chép thời gian tạo (`btime`) và sửa đổi (`mtime`) chính xác đến cấp nanosecond.

6. **Hoán đổi nguyên tử (Atomic Swap):**
   - Tạo clone tạm thời `.xmac-clone-[UUID]` cùng thư mục cha.
   - So sánh byte sống giữa bản clone và tệp đích.
   - Kiểm tra `lstat` xem tệp đích có bị chỉnh sửa trong quá trình xử lý không.
   - Dùng syscall `rename(tempClone, targetPath)` để thay thế tức thì, không bao giờ để lại trạng thái tệp hỏng nếu xảy ra sự cố đột ngột.

---

## 4. Nhật Ký Giao Dịch & Hoàn Tác (Journal & Undo)

- **Nhật ký:** Mọi giao dịch CoW clone được ghi lại dưới dạng JSONL tại:
  `~/Library/Application Support/Xmac/dedup_journal.jsonl`
- **Hoàn tác (Unfold):**
  - Người dùng có thể bấm nút **"Hoàn tác tất cả"** bất cứ lúc nào.
  - Động cơ sẽ thực hiện phép sao chép vật lý thực sự qua `copyfile(..., COPYFILE_DATA | COPYFILE_NOFOLLOW)` (không dùng cờ `COPYFILE_CLONE`), tách rời các khối CoW thành dữ liệu độc lập hoàn toàn mà không làm mất bất kỳ thuộc tính nào của tệp.

---

## 5. Quét Theo Loại Tệp (Category Filtering)

Để đáp ứng các nhu cầu dọn dẹp chuyên biệt và tối ưu hiệu suất, hệ thống cung cấp các bộ lọc danh mục tại **Tầng 1 (Tier 1)**:
- **Tất cả (All):** Quét toàn bộ các tệp hợp lệ theo ngưỡng kích thước mặc định (>= 64 KB).
- **Hình ảnh (Images):** `.png`, `.jpg`, `.jpeg`, `.gif`, `.heic`, `.webp`, `.tiff`, `.raw`, `.svg`...
- **Video:** `.mp4`, `.mov`, `.mkv`, `.avi`, `.m4v`, `.webm`, `.flv`...
- **Mã nguồn (Code):** `.swift`, `.m`, `.h`, `.c`, `.cpp`, `.rs`, `.go`, `.py`, `.js`, `.ts`, `.json`, `.yaml`, `.xml`... *(Khi chọn danh mục Mã nguồn, ngưỡng kích thước tối thiểu tự động hạ xuống 1 KB để bắt kịp các file code nhỏ).*
- **Tài liệu (Documents):** `.pdf`, `.docx`, `.xlsx`, `.pptx`, `.txt`, `.md`, `.rtf`, `.csv`...
- **Tệp nén (Archives):** `.zip`, `.tar`, `.gz`, `.dmg`, `.pkg`, `.7z`, `.rar`, `.iso`...

Việc lọc phần mở rộng ngay tại bước duyệt cây thư mục giúp loại bỏ các tệp không liên quan trước khi tính toán băm SHA-256, tăng tốc độ quét chuyên biệt lên nhiều lần.

---

## 6. Lập Lịch Quét Tự Động Định Kỳ (Background Scheduler)

- **Cơ chế hoạt động:**
  - Lập lịch quét chạy nền thông qua `DeduplicatorScheduler` được tích hợp vào vòng đời ứng dụng (`AppDelegate`).
  - Hỗ trợ các chu kỳ định kỳ: **Hàng ngày (Daily)**, **Hàng tuần (Weekly)**, **Hàng tháng (Monthly)**.
  - Tự động ghi nhớ thời điểm quét gần nhất (`UserDefaults`).
- **Ngưỡng thông báo thông minh:**
  - Người dùng có thể cấu hình ngưỡng dung lượng lãng phí có thể giải phóng: **500 MB**, **1 GB**, **2 GB**, hoặc **5 GB**.
  - Khi phát hiện lượng dung lượng trùng lặp vượt ngưỡng đã chọn, dịch vụ nền sẽ gửi thông báo hệ thống qua `UNUserNotificationCenter` để nhắc nhở người dùng mở ứng dụng và hợp nhất tệp CoW, không làm gián đoạn công việc hiện tại.
