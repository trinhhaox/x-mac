import SwiftUI
import Charts

struct SystemMonitorView: View {
    @StateObject private var monitor = SystemMonitor()

    private func bytes(_ value: UInt64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? "Không đọc được"
    }
    private func rate(_ value: Double?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64(min(max(0, $0), Double(Int64.max / 2))), countStyle: .file) + "/s" } ?? (monitor.sample?.network == nil ? "Không đọc được" : (monitor.sample?.network?.isEmpty == true ? "Không có giao diện en* đang bật" : "Đang đo…"))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(eyebrow: "System monitor", title: "Thông tin hệ thống",
                    subtitle: "CPU, RAM và lưu lượng mạng • Cập nhật mỗi 2 giây") {
                    Button(monitor.running ? "Tạm dừng" : "Tiếp tục") {
                        monitor.running ? monitor.stop() : monitor.start()
                    }.buttonStyle(BrandSecondaryButtonStyle())
                }
                Text("\(ProcessInfo.processInfo.processorCount) nhân CPU logic • \(bytes(ProcessInfo.processInfo.physicalMemory)) RAM • \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    .foregroundStyle(.secondary)
                ModernCard {
                    HStack {
                        Label("CPU toàn máy", systemImage: "cpu")
                        Spacer()
                        Text(monitor.cpuUsage.map { String(format: "%.1f %%", $0) } ?? (monitor.sample != nil && monitor.sample?.cpu == nil ? "Không đọc được" : "Đang đo…"))
                            .font(.title.bold()).monospacedDigit()
                    }
                    Chart(Array(monitor.cpuHistory.enumerated()), id: \.offset) { point in
                        LineMark(x: .value("Mẫu", point.offset), y: .value("CPU (%)", point.element))
                            .foregroundStyle(XmacTheme.blue)
                        PointMark(x: .value("Mẫu", point.offset), y: .value("CPU (%)", point.element))
                            .foregroundStyle(XmacTheme.blue).symbolSize(15)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXScale(domain: 0...29)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { _ in
                            AxisGridLine()
                            AxisValueLabel(anchor: .leading)
                        }
                    }
                    .frame(height: 110)
                    .accessibilityLabel("Biểu đồ CPU, tối đa 30 mẫu gần nhất, thang 0 đến 100 phần trăm")
                    Text("Trung bình trên tất cả nhân, 0–100%. Mẫu đầu cần 2 giây; lịch sử tối đa 1 phút.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ModernCard {
                    Label("RAM", systemImage: "memorychip").font(.headline)
                    metric("Đang dùng (ước tính)", bytes(monitor.sample?.memoryUsed))
                    if let used = monitor.sample?.memoryUsed {
                        ProgressView(value: Double(used), total: Double(ProcessInfo.processInfo.physicalMemory))
                            .tint(XmacTheme.blue)
                    }
                    metric("Bộ nhớ wired", bytes(monitor.sample?.memoryWired))
                    metric("Bộ nhớ nén", bytes(monitor.sample?.memoryCompressed))
                    metric("Swap đang dùng", bytes(monitor.sample?.swapUsed))
                    Text("RAM ước tính = active + wired + compressed; không phải áp lực bộ nhớ. Swap là dung lượng ổ đĩa dùng cho bộ nhớ ảo.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ModernCard {
                    Label("Tốc độ mạng", systemImage: "network").font(.headline)
                    metric("↓ Nhận", rate(monitor.networkRate?.received))
                    metric("↑ Gửi", rate(monitor.networkRate?.sent))
                    Text("Giao diện: \(monitor.sample?.network?.keys.sorted().joined(separator: ", ") ?? "Không đọc được")")
                        .foregroundStyle(.secondary)
                    Text("Lưu lượng thực tế qua Wi-Fi/Ethernet (en*), gồm cả mạng nội bộ; không phải tốc độ gói Internet. Không cộng trùng VPN, loopback hoặc kết nối ngang hàng.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ModernCard {
                    Label("Bộ nhớ lưu trữ", systemImage: "internaldrive").font(.headline)
                    metric("Volume chứa thư mục người dùng", "")
                    metric("Tổng dung lượng", bytes(monitor.sample?.diskTotal.flatMap { $0 >= 0 ? UInt64($0) : nil }))
                    metric("Dung lượng trống", bytes(monitor.sample?.diskAvailable.flatMap { $0 >= 0 ? UInt64($0) : nil }))
                    Text("Không cộng các volume APFS dùng chung dung lượng. Chưa gồm dung lượng có thể thu hồi; các ổ khác xem tại Ổ đĩa & NTFS.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ModernCard {
                    Label("Nhiệt độ & trạng thái nhiệt", systemImage: "thermometer.medium").font(.headline)
                    metric("Trạng thái macOS", monitor.sample.map { SystemMonitor.thermalTitle($0.thermal) } ?? "Đang đọc…")
                    Text("Nhiệt độ °C: chưa có nguồn cảm biến được hỗ trợ. Trạng thái nhiệt phản ánh mức tải nhiệt, không quy đổi thành °C. Không yêu cầu quyền quản trị hoặc cài helper.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let date = monitor.sample?.date {
                    Text("\(monitor.running ? "Cập nhật" : "Đã tạm dừng") lúc \(date.formatted(date: .omitted, time: .standard)) • Dữ liệu không được lưu hoặc gửi đi")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
        .xmacPage()
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).fontWeight(.medium).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}
