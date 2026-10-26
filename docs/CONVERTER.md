# Chuyển Đổi Tệp

Ý tưởng tham khảo từ [Filee](https://github.com/KnifeLemon/Filee) (MIT, KnifeLemon). Xmac viết lại bằng Swift và API của Apple; không dùng mã của Filee.

## Phạm vi hiện tại

| Nhóm | Vào | Ra | Công cụ |
|---|---|---|---|
| Ảnh | mọi định dạng ImageIO đọc được (JPG, PNG, HEIC, TIFF, GIF, BMP, WebP, AVIF…) | JPG, PNG, HEIC, TIFF, GIF, BMP, ICNS (chỉ liệt kê định dạng máy ghi được) | ImageIO |
| Ảnh, PDF → văn bản (OCR) | ảnh đọc được, PDF | TXT (UTF-8; PDF: mỗi trang cách bằng `--- Trang N ---`) | Vision, chạy trên máy |
| Ảnh → PDF | nhiều ảnh | một PDF | PDFKit |
| PDF | PDF | ảnh PNG/JPG từng trang (thư mục `page-001.png`…), gộp (≥ 2 tệp), nén; tách từng trang (thư mục `<tên> - trang 001.pdf`…), trích khoảng trang (ô “Khoảng trang”, vd. `1-3, 5, 8-`) | PDFKit, bộ lọc Quartz "Reduce File Size" |
| Văn bản | DOCX, DOC, RTF, ODT, HTML, TXT, webarchive | DOCX, RTF, ODT, HTML, TXT | `textutil` |
| Video/âm thanh | MOV, MP4, M4V, 3GP, M4A, MP3, WAV, AIFF, CAF | MP4 (H.264), MOV, MP4 (HEVC), 720p, M4A | AVFoundation |
| Nén | tệp/thư mục bất kỳ | ZIP | `ditto` |
| Giải nén | ZIP, TAR, TGZ, TBZ2, TXZ, 7Z, ISO, CAB, XAR | thư mục | `ditto`, `tar` |
| Phụ đề | SRT, VTT, ASS | SRT, VTT, ASS (UTF-8) | Swift |
| Chuyển mã TCVN3/VNI | TXT, SRT, VTT, ASS, CSV, HTML, MD | cùng định dạng, Unicode UTF-8 (chọn “từ TCVN3” hoặc “từ VNI”; HTML đổi `charset` thành utf-8) | Swift |
| Sửa phông VNI/TCVN3 | DOCX dùng phông `.Vn*` / `VNI-*` (cả Strict OOXML) | DOCX Unicode: đổi chữ trong `w:t`/`w:delText` của thân, header/footer, chú thích, comments, glossary và chữ số thứ tự/dấu đầu dòng (`numbering.xml`); phông thành Times New Roman/Arial (cả `fontTable.xml`, bỏ phông cũ nhúng trong tệp); phông thừa kế theo style/mặc định | `ditto`, XMLDocument |
| Pages/Numbers/Keynote *(cần app iWork)* | PAGES, NUMBERS, KEY | Pages → PDF, DOCX, RTF, TXT, EPUB; Numbers → PDF, XLSX, CSV; Keynote → PDF, PPTX | app iWork qua AppleScript (`osascript`) |
| Office *(cần LibreOffice)* | DOC, DOCX, ODT, RTF, XLS, XLSX, ODS, CSV, PPT, PPTX, ODP, Pages, Numbers, Keynote, HWP (đời HWP 97), DXF | PDF; DOC ↔ DOCX, XLS ↔ XLSX, PPT ↔ PPTX; HWP → DOCX, ODT; DXF → SVG, PNG | `soffice --headless` |
| E-book | EPUB | TXT, HTML (một tệp, ảnh ≤ 2 MB nhúng sẵn), DOCX, RTF | Swift, `textutil` |
| E-book *(cần calibre)* | MOBI, AZW, AZW3, AZW4, FB2, FBZ, LIT, LRF, PDB, CBZ, CBR, CB7, HTMLZ, TXTZ, CHM, EPUB, DOCX, ODT, RTF | EPUB, MOBI, AZW3, PDF, DOCX, TXT, FB2 | `ebook-convert` |
| Phông chữ | TTF, OTF, WOFF | TTF/OTF → WOFF; WOFF → TTF/OTF (không có WOFF2, không đổi TTF ↔ OTF) | Swift, Compression |
| Mô hình 3D | OBJ, STL, PLY, USD/USDA/USDC/USDZ, ABC | OBJ (bỏ tệp .mtl), STL, PLY, USD, USDA, USDC; PNG xem trước 1024 px | ModelIO, SceneKit |
| Dữ liệu bản đồ | GeoJSON, KML, KMZ, GPX | GeoJSON, KML, GPX, CSV toạ độ (GPX không có đa giác → ghi thành đường theo viền ngoài) | Swift |
| Video/âm thanh *(cần ffmpeg)* | MKV, WEBM, AVI, FLV, WMV, MPEG, TS, OGV, VOB, FLAC, OGG, OPUS, WMA, APE… | MP4, WEBM, MKV, GIF; MP3, M4A, FLAC, OGG, OPUS, WAV | `ffmpeg`, `ffprobe` |

Khi nhiều bộ cùng có một định dạng ra, chỉ hiện một lựa chọn: bộ có sẵn của macOS trước, rồi app iWork, rồi LibreOffice/ffmpeg/calibre.

Xuất qua iWork: lần đầu macOS hỏi quyền Tự động hoá; tài liệu đang mở sẵn được xuất mà không đóng, Xmac chỉ đóng tài liệu do nó mở và chỉ thoát app nếu chính nó mở app và app không còn tài liệu nào. Numbers có nhiều bảng xuất CSV ra nhiều tệp: chưa hỗ trợ.

## Khả năng hiện tại

- Lối vào: tab "Chuyển đổi tệp"; Finder › chuột phải › Dịch vụ › "Chuyển đổi bằng Xmac"; Mở nhanh (`⌥⇧Space`) › "Chuyển đổi tệp đang chọn trong Finder"; thả tệp lên icon Menu Bar.
- Donut ⌃ + kéo (thử nghiệm, mặc định tắt; bật trong Cài đặt › Chuyển đổi tệp):
  - bắt đầu kéo tệp như thường, **sau đó** nhấn ⌃ → vòng định dạng hiện tại con trỏ;
  - thả lên một ô → chuyển đổi; nhả ⌃, thả ra ngoài vòng hoặc nhấn Esc → đóng, Finder xử lý như bình thường;
  - giữ ⌃ trước khi nhấn chuột không kích hoạt (trong Finder đó là chuột phải);
  - tối đa 8 ô, định dạng dùng gần đây lên đầu; còn nhiều hơn thì có mặt sau: nhấn Tab hoặc cuộn chuột một nấc (các nấc cách nhau dưới ~250 ms tính là một lần) để lật, chỉ báo 1/2 – 2/2 ở giữa; ô "Khác…" ở cuối mặt sau mở bảng chọn đầy đủ; bật "Giảm chuyển động" thì lật tức thì;
  - khi vòng đang mở, ⌃⇧ không đổi bộ gõ V/E.
- Tệp ra nằm cạnh tệp gốc, không ghi đè (`ảnh 1.png`…). Trong lúc chạy, tệp dở là tệp ẩn `.<tên>.xmac-partial`; xong mới đổi tên.
- Chạy song song tối đa 4 việc; việc dùng ffmpeg/LibreOffice/video chạy lần lượt từng việc.
- Thông báo khi xong cả lô, có nút "Hiện trong Finder"; lịch sử 20 kết quả gần nhất có ảnh thu nhỏ.
- Cài đặt chia theo mục Ảnh / PDF / Video: chất lượng JPG/HEIC, cạnh ảnh tối đa, DPI khi xuất PDF ra ảnh, chiều cao video tối đa; OCR và PDF dùng mục PDF, video dùng mục Video, còn lại dùng mục Ảnh. Cài đặt cũ (một bộ chung) được dùng làm mặc định cho mọi mục ở lần mở đầu.
- Cắt ảnh: khi chỉ chọn ảnh, nút "Cắt ảnh…" lần lượt mở từng ảnh với khung kéo được và tỉ lệ (Tự do, 1:1, 4:3, 3:2, 16:9, 9:16). Vùng cắt áp dụng sau khi xoay theo EXIF, trước khi thu nhỏ, chỉ khi chuyển sang định dạng ảnh từ tab (không áp dụng cho "Gộp ảnh thành một PDF", donut, thư mục theo dõi, CLI); đổi lựa chọn thì vùng cắt bị bỏ.
- Nhận chữ từ vùng màn hình: Mở nhanh › "Nhận chữ từ vùng màn hình" hoặc chuột phải icon Menu Bar; kéo chọn vùng, chữ tiếng Việt/Anh được chép vào bộ nhớ tạm. Cần quyền Ghi màn hình.
- Lệnh dòng lệnh: xem mục CLI bên dưới.
- Thẻ "Công cụ ngoài" hiện đường dẫn ffmpeg/LibreOffice tìm được (`/opt/homebrew/bin`, `/usr/local/bin`, `/Applications/LibreOffice.app`) và cho chọn đường dẫn tay.

## Ranh giới kỹ thuật

- Công cụ ngoài chạy bằng `Process` với mảng tham số, không qua shell; đường dẫn tệp chỉ đi qua tham số.
- Giải nén liệt kê nội dung trước và từ chối mục có đường dẫn tuyệt đối hoặc `..`; `ditto`/`bsdtar` chặn ghi xuyên symlink.
- Thư mục tạm đặt trên cùng ổ với thư mục đích, tránh làm đầy ổ trong khi xử lý tệp trên ổ ngoài.
- Thoát Xmac khi đang chuyển: hủy các việc và dừng ffmpeg/soffice. Tệp dở ẩn được ghi vào `~/Library/Application Support/Xmac/converter-partials.json`; lần mở app sau xoá những tệp còn sót (chỉ tệp có tên đúng mẫu tệp dở, chỉ của phiên trước). CLI dùng nhật ký riêng nên không bị app dọn nhầm.
- EPUB → HTML/TXT/DOCX/RTF đi qua bộ lọc chỉ giữ thẻ an toàn và hoàn toàn không tải gì từ ngoài: bỏ script, style, form, iframe, SVG, video; ảnh chỉ nhúng dạng `data:` (≤ 2 MB mỗi ảnh, tổng ≤ 50 MB); chỉ giữ liên kết http/https/mailto; HTML có Content-Security-Policy chặn tải ngoài.
- EPUB và KMZ được kiểm bằng `zipinfo` trước khi giải nén: từ chối nếu tổng dung lượng khai báo > 512 MB, > 10.000 mục hoặc có đường dẫn không an toàn; tổng HTML các chương ≤ 256 MB.
- WOFF → TTF/OTF: tối đa 128 MB mỗi bảng và tổng; từ chối bảng trùng, dữ liệu chồng nhau hoặc `totalSfntSize` không khớp. Khi tạo WOFF, bảng chỉ được nén nếu nhỏ hơn hẳn, không thì giữ nguyên.
- CSV toạ độ: tên bắt đầu bằng `= + - @`, tab hoặc CR được thêm `'` ở đầu để bảng tính không chạy như công thức.
- CLI: Ctrl-C/SIGTERM/SIGHUP hủy việc và dừng tiến trình con (mã thoát 130/143/129); lần chạy `xmac convert` sau dọn tệp dở của tiến trình CLI đã chết. `xmac install-cli` chỉ thay link `xmac` cũ khi link hỏng hoặc trỏ vào Xmac.app, và từ chối chạy khi app đang ở chế độ App Translocation (hãy chuyển Xmac.app vào /Applications).
- Nhận chữ từ vùng màn hình kiểm và xin quyền Ghi màn hình trước khi chụp.
- `textutil` không giữ bố cục phức tạp; có LibreOffice thì nên dùng đích Office cho DOCX → PDF.
- Mục Dịch vụ có thể chỉ hiện sau khi đăng xuất/đăng nhập (hoặc `/System/Library/CoreServices/pbs -update`), và có thể phải bật trong Cài đặt hệ thống › Bàn phím › Phím tắt bàn phím › Dịch vụ › Tệp và thư mục.

### Giấy phép công cụ ngoài

Xmac không đóng gói hay phân phối lại ffmpeg (LGPL/GPL tùy bản build), LibreOffice (MPL 2.0) và calibre (GPL v3); chỉ gọi bản người dùng đã tự cài.

## CLI (`xmac`)

Cùng binary, chạy không giao diện khi tham số đầu đúng là `convert`, `formats`, `install-cli`, `--help`/`-h`/`help`:

- `xmac formats <tệp…>`: liệt kê định dạng đích (id, đuôi, tên) và công cụ còn thiếu.
- `xmac convert <tệp…> --to <id|đuôi> [--out thư-mục] [--quality 0-100] [--max-size N] [--dpi N] [--pages "1-3,5"] [--height N] [--quiet]`: `--to` nhận id (vd. `image.jpg`) hoặc đuôi/tên duy nhất; mặc định lấy cài đặt đã lưu trong app, cờ ghi đè. Đường dẫn kết quả in ra stdout, tiến độ/lỗi ra stderr. Mã thoát: 0 xong, 1 có tệp lỗi, 2 sai cú pháp, 130 Ctrl-C (hủy việc, dừng tiến trình con).
- `xmac install-cli`: tạo symlink `xmac` trong `/usr/local/bin` (hoặc `~/.local/bin` nếu không ghi được), không dùng sudo.

## Thư mục theo dõi

Tab Chuyển đổi, thẻ "Thư mục theo dõi": bật công tắc chung (mặc định tắt), thêm quy tắc gồm thư mục, loại tệp vào (Ảnh, PDF, Video, Âm thanh, Tài liệu, Phụ đề), định dạng đích và thư mục con chứa kết quả (tuỳ chọn; bỏ trống thì lưu cạnh tệp gốc). Tệp gốc luôn được giữ lại.

- Chỉ xử lý tệp mới được tạo hoặc đổi tên vào thư mục sau khi theo dõi chạy (FSEvents); tệp có sẵn không bị chuyển hàng loạt khi bật. Chỉ xét tệp nằm trực tiếp trong thư mục, không xét thư mục con.
- Bỏ qua tệp ẩn, `.xmac-partial`, `.download`, `.crdownload`, `.part` và thư mục. Tệp phải ổn định (kích thước và giờ sửa không đổi qua 2 lần kiểm tra cách nhau 2 giây, chờ tối đa 10 phút) mới được chuyển.
- Tệp do Xmac tạo ra không kích hoạt quy tắc khác. Mỗi tệp chỉ được một quy tắc chuyển một lần (nhớ theo đường dẫn, 500 tệp gần nhất, cả sau khi mở lại app): sửa rồi lưu lại hay đổi tên tệp gốc không chuyển lại. Quy tắc không cho chọn "Trích trang đã chọn".
- Mỗi tệp tự động là một lượt riêng nên có thông báo riêng.

## Kéo từ trình duyệt

Thả ảnh, liên kết tệp hoặc tệp đang tải từ Safari, Chrome, Edge, Firefox, Arc vào ô thả của tab Chuyển đổi, icon Menu Bar hoặc vòng donut: Xmac tải tệp về máy rồi mới chuyển.

- Thứ tự ưu tiên: tệp thật > tệp hứa (file promise) > dữ liệu ảnh trên clipboard kéo (PNG, JPEG, HEIC, WebP, GIF; TIFF của Safari chỉ dùng khi không có liên kết) > liên kết (cũng nhận văn bản chỉ gồm một URL) > URL `data:image/…;base64`. Mọi scheme khác (`javascript:`, `file:`, `ftp:`…) bị từ chối.
- Tải ẩn danh: không gửi cookie hay thông tin đăng nhập của trình duyệt (trang cần đăng nhập sẽ báo lỗi), không dùng cache, quá hạn 60 giây không có dữ liệu, tối đa 2 GB, chỉ nhận liên kết https (liên kết http báo "Chỉ hỗ trợ liên kết https", chuyển hướng sang http bị từ chối), không trả lời yêu cầu đăng nhập của máy chủ. Tên tệp lấy theo `Content-Disposition`, rồi tên trình duyệt gợi ý, rồi phần cuối đường dẫn, rồi "download"; thiếu đuôi thì thêm theo kiểu MIME; không ghi đè tệp có sẵn. Mọi tệp lấy về đều gắn dấu quarantine như tải từ trình duyệt (Gatekeeper kiểm tra khi mở lần đầu) và không bao giờ được mở hay chạy; ký tự điều khiển/đảo chiều trong tên bị bỏ, tên bị cắt ở 200 byte.
- Cài đặt "Tệp kéo từ trình duyệt": "Lưu vào Tải về" (mặc định: giữ tệp trong ~/Downloads, kết quả nằm cạnh) hoặc "Chỉ giữ tệp đã chuyển" (tải vào thư mục tạm, kết quả lưu ở ~/Downloads, tệp tạm xoá khi lượt chuyển thành công hoặc khi bỏ chọn/đóng bảng chọn; nếu lượt chuyển THẤT BẠI thì tệp tạm được chuyển sang ~/Downloads để không mất; thư mục tạm bỏ quên quá 24 giờ được dọn ở lần kéo sau).
- Tab Chuyển đổi và Menu Bar tải xong mới cho chọn định dạng. Donut cần biết định dạng trước khi thả nên dựa vào đuôi trong liên kết hoặc tên gợi ý, hoặc kiểu ảnh/kiểu tệp hứa; không đoán được đuôi thì donut không hiện (kéo vào tab hoặc Menu Bar thay thế). Nếu tệp thật khác đuôi dự đoán, lượt chuyển báo lỗi như thường.
- Đang tải: ô thả của tab hiện "Đang tải…" kèm nút Huỷ; Menu Bar và donut không có chỉ báo. Lỗi tải được báo bằng thông báo hệ thống. Tải xong mà không có định dạng nào cho tệp (cả hai chế độ) thì tệp vừa tải bị xoá và có thông báo; Menu Bar chỉ nhận liên kết có đuôi tệp đã biết hoặc đi kèm ảnh, để thả liên kết trang web không tải về HTML.

## Chưa nằm trong phạm vi

- WOFF2, TTF ↔ OTF, TTC; DWG; Shapefile; HWPX và HWP 5.x; EPUB → PDF khi không có calibre.
- Thư mục theo dõi và CLI chưa có nhóm loại tệp riêng cho phông, 3D, bản đồ, e-book (CLI vẫn chuyển được theo đuôi).

## Kiểm tra

- `Scripts/test.sh`: test đơn vị cho registry, hàng đợi, đặt tên, từng bộ chuyển đổi (tệp mẫu sinh trong test), giải nén độc, cử chỉ và hình học donut. Test ffmpeg/LibreOffice chỉ chạy khi máy có công cụ đó.
- Thử tay: mỗi lối vào với ảnh, PDF, DOCX, MKV; icon Menu Bar vẫn nhấp trái/phải đúng; donut trong Finder (biểu tượng/danh sách/cột), Desktop, nhiều màn hình; kéo không nhấn ⌃ không đổi gì; ⌘X/⌘V và ⌃⇧ của bộ gõ vẫn đúng.
