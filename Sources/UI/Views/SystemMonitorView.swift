import Charts
import SwiftUI

@MainActor final class SystemMonitorPresentation: ObservableObject {
  @Published var detailsExpanded: Bool
  @Published var appeared = false
  init(detailsExpanded: Bool = false) { self.detailsExpanded = detailsExpanded }
}

@MainActor struct SystemMonitorView: View {
  @StateObject private var monitor: SystemMonitor
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var presentation: SystemMonitorPresentation

  init(
    monitor: SystemMonitor? = nil, detailsExpanded: Bool = false,
    presentation: SystemMonitorPresentation? = nil
  ) {
    _monitor = StateObject(wrappedValue: monitor ?? SystemMonitor())
    _presentation = StateObject(
      wrappedValue: presentation ?? SystemMonitorPresentation(detailsExpanded: detailsExpanded))
  }

  private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
  private var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }
  private var cpuStatus: String {
    if monitor.cpuUsage != nil { return L10n.text(monitor.running ? "Đang dùng" : "Mẫu cuối") }
    if !monitor.cpuHistory.isEmpty { return L10n.text("Chờ mẫu mới") }
    return L10n.text(monitor.sample?.cpu == nil && monitor.sample != nil ? "Chưa có dữ liệu" : "Đang đo…")
  }
  private var cpuHistoryTitle: String {
    if monitor.cpuHistory.isEmpty { return L10n.text("Chưa có mẫu") }
    return monitor.cpuUsage == nil ? L10n.text("Lịch sử trước đó") : L10n.format("%lld mẫu gần nhất", Int64(monitor.cpuHistory.count))
  }
  private var memoryFraction: Double? {
    monitor.sample?.memoryUsed.map { min(1, Double($0) / Double(physicalMemory)) }
  }
  private var diskFraction: Double? {
    guard let total = monitor.sample?.diskTotal, let free = monitor.sample?.diskAvailable,
      total > 0, free >= 0, free <= total
    else { return nil }
    return Double(total - free) / Double(total)
  }
  private func bytes(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    if value == 0 { return "0 B" }
    return ByteSize.string(Int64(clamping: value), countStyle: .memory)
  }
  private func diskBytes(_ value: Int64?) -> String {
    bytes(value.flatMap { $0 >= 0 ? UInt64($0) : nil })
  }
  private func rate(_ value: Double?) -> String { MonitorFormat.rate(value) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        header
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
          cpuCard
          memoryCard
          networkCard
          storageCard
          DiskActivityCard(rate: monitor.diskRate, available: monitor.sample == nil || monitor.sample?.diskIO != nil)
          if let battery = monitor.sample?.battery {
            BatteryCard(info: battery)
          }
        }
        TopProcessesCard(processes: monitor.topProcesses)
        thermalStrip
        details
        footer
      }
      .padding(20)
      .opacity(presentation.appeared ? 1 : 0)
      .offset(y: presentation.appeared || reduceMotion ? 0 : 6)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: presentation.appeared)
    }
    .background(XmacTheme.workspaceBackground.ignoresSafeArea())
    .onAppear {
      presentation.appeared = true
      monitor.start()
    }
    .onDisappear { monitor.stop() }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Thông tin hệ thống")
          .font(.system(size: 25, weight: .bold, design: .rounded))
          .accessibilityAddTraits(.isHeader)
        Text(L10n.format(
          "%lld nhân CPU · %@ RAM · macOS %lld.%lld",
          Int64(ProcessInfo.processInfo.processorCount), bytes(physicalMemory),
          Int64(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
          Int64(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)
        ))
        .font(.system(size: 13)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Button {
        monitor.running ? monitor.stop() : monitor.start()
      } label: {
        Label(
          L10n.text(monitor.running ? "Tạm dừng" : "Tiếp tục"),
          systemImage: monitor.running ? "pause.fill" : "play.fill")
      }
      .buttonStyle(BrandSecondaryButtonStyle())
      .accessibilityIdentifier("monitor.pause")
    }
  }

  private func cardTitle(_ title: String, icon: String, caption: String? = nil) -> some View {
    HStack {
      Label(L10n.text(title), systemImage: icon).font(.system(size: 14, weight: .semibold))
      Spacer(minLength: 4)
      if let caption { Text(L10n.text(caption)).font(.system(size: 12)).foregroundStyle(.secondary) }
    }
  }

  private var cpuCard: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 14) {
        cardTitle("CPU", icon: "cpu", caption: "Toàn máy")
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(monitor.cpuUsage.map { String(format: "%.1f", $0) } ?? "—")
            .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
          Text("%").font(.title3).foregroundStyle(.secondary)
          Spacer()
          Text(cpuStatus)
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Chart(Array(monitor.cpuHistory.enumerated()), id: \.offset) { point in
          AreaMark(x: .value("Mẫu", point.offset), y: .value("CPU (%)", point.element))
            .foregroundStyle(
              LinearGradient(
                colors: [XmacTheme.blue.opacity(0.22), XmacTheme.blue.opacity(0.02)],
                startPoint: .top, endPoint: .bottom))
          LineMark(x: .value("Mẫu", point.offset), y: .value("CPU (%)", point.element))
            .foregroundStyle(XmacTheme.blue).lineStyle(StrokeStyle(lineWidth: 2))
          if monitor.cpuHistory.count == 1 {
            PointMark(x: .value("Mẫu", point.offset), y: .value("CPU (%)", point.element))
              .foregroundStyle(XmacTheme.blue).symbolSize(16)
          }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: 0...29)
        .chartXAxis(.hidden)
        .chartYAxis {
          AxisMarks(position: .trailing, values: [0, 100]) { _ in
            AxisGridLine()
            AxisValueLabel(anchor: .leading)
          }
        }
        .frame(height: 48)
        .accessibilityLabel("CPU toàn máy, tối đa 30 mẫu gần nhất, thang 0 đến 100 phần trăm")
        HStack {
          Text(cpuHistoryTitle)
          Spacer()
          Text("Mỗi 2 giây")
        }.font(.system(size: 12)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var memoryCard: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 14) {
        cardTitle("RAM", icon: "memorychip", caption: "Ước tính")
        HStack(spacing: 16) {
          ZStack {
            Circle().stroke(XmacTheme.blue.opacity(0.12), lineWidth: 7)
            if let fraction = memoryFraction {
              Circle().trim(from: 0, to: fraction)
                .stroke(XmacTheme.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            }
            Text(memoryFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
              .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
          }
          .frame(width: 64, height: 64)
          .accessibilityLabel("Tỷ lệ RAM đang dùng")
          .accessibilityValue(
            memoryFraction.map { L10n.format("%lld phần trăm", Int64(($0 * 100).rounded())) } ?? L10n.text("Chưa có dữ liệu"))
          VStack(alignment: .leading, spacing: 3) {
            Text(bytes(monitor.sample?.memoryUsed))
              .font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
            Text(L10n.format("đang dùng / %@", bytes(physicalMemory)))
              .font(.system(size: 12)).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        Divider()
        HStack(alignment: .top, spacing: 12) {
          smallMetric("Nén", bytes(monitor.sample?.memoryCompressed))
          Spacer(minLength: 0)
          smallMetric("Swap", bytes(monitor.sample?.swapUsed))
        }
      }.frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var networkCard: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 14) {
        cardTitle("Mạng", icon: "network", caption: "Wi-Fi / Ethernet")
        HStack(alignment: .top, spacing: 12) {
          smallMetric("↓ Nhận", rate(monitor.networkRate?.received), prominent: true)
          Spacer(minLength: 0)
          smallMetric("↑ Gửi", rate(monitor.networkRate?.sent), prominent: true)
        }
        Text(L10n.text(
          monitor.sample?.network == nil
            ? "Không đọc được giao diện mạng"
            : (monitor.sample?.network?.isEmpty == true
              ? "Không có giao diện en* đang bật"
              : (monitor.networkRate == nil
                ? "Đang chờ mẫu kế tiếp…" : "Lưu lượng thực tế · không phải speed test"))
        ))
        .font(.system(size: 12)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var storageCard: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 14) {
        cardTitle("Lưu trữ", icon: "internaldrive", caption: "Volume người dùng")
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(diskBytes(monitor.sample?.diskAvailable))
            .font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
          Text("trống").font(.system(size: 13)).foregroundStyle(.secondary)
          Spacer(minLength: 0)
        }
        if let used = diskFraction {
          ProgressView(value: used).tint(XmacTheme.blue)
            .accessibilityLabel("Dung lượng lưu trữ đang dùng")
        }
        HStack {
          Text(L10n.format("Tổng %@", diskBytes(monitor.sample?.diskTotal)))
          Spacer(minLength: 4)
          if let used = diskFraction { Text(L10n.format("%lld%% đã dùng", Int64((used * 100).rounded()))) }
        }.font(.system(size: 12)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var thermalColor: Color {
    guard let state = monitor.sample?.thermal else { return .secondary }
    switch state {
    case .nominal: return .green
    case .fair: return .orange
    case .serious, .critical: return .red
    @unknown default: return .secondary
    }
  }

  private var thermalStrip: some View {
    HStack(spacing: 12) {
      Image(systemName: "thermometer.medium").foregroundStyle(thermalColor).font(.title3)
      VStack(alignment: .leading, spacing: 3) {
        Text("Trạng thái nhiệt").font(.system(size: 13, weight: .semibold))
        Text("macOS · chưa hỗ trợ nhiệt độ °C").font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Text(monitor.sample.map { SystemMonitor.thermalTitle($0.thermal) } ?? L10n.text("Chưa có dữ liệu"))
        .font(.system(size: 13, weight: .medium)).foregroundStyle(thermalColor)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .background(XmacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(XmacTheme.cardStroke, lineWidth: 1))
  }

  private var details: some View {
    DisclosureGroup(isExpanded: $presentation.detailsExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        detail(
          "RAM",
          L10n.format("Active + wired + compressed; không phải áp lực bộ nhớ. Wired: %@. Swap dùng dung lượng ổ đĩa.", bytes(monitor.sample?.memoryWired))
        )
        detail(
          "Mạng",
          L10n.format("Giao diện: %@. Chỉ cộng en*, không cộng trùng VPN, loopback hoặc kết nối ngang hàng; gồm cả mạng nội bộ.", monitor.sample?.network?.keys.sorted().joined(separator: ", ") ?? L10n.text("Không đọc được"))
        )
        detail(
          "Lưu trữ",
          "Volume chứa thư mục người dùng; không cộng các volume APFS dùng chung dung lượng, chưa gồm phần có thể thu hồi. Thanh thể hiện dung lượng đang dùng. Các ổ khác xem tại Ổ đĩa & NTFS."
        )
        detail(
          "Nhiệt",
          "Trạng thái do macOS cung cấp, không quy đổi thành °C. Không yêu cầu quyền quản trị hoặc cài helper."
        )
        detail(
          "CPU",
          "Trung bình tất cả nhân, 0–100%; mẫu đầu cần 2 giây, tối đa 30 mẫu. Dấu — nghĩa là đang chờ mẫu hoặc chưa đọc được dữ liệu."
        )
        Text(ProcessInfo.processInfo.operatingSystemVersionString).foregroundStyle(.secondary)
      }
      .font(.system(size: 13)).padding(.top, 10)
      .fixedSize(horizontal: false, vertical: true)
    } label: {
      Text("Chi tiết & cách đo").font(.system(size: 13, weight: .medium))
    }
    .accessibilityIdentifier("monitor.details")
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: presentation.detailsExpanded)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Circle().fill(monitor.running ? XmacTheme.blue : .secondary).frame(width: 6, height: 6)
      Text(L10n.text(monitor.running ? "Đang theo dõi" : "Đã tạm dừng"))
      if let date = monitor.sample?.date {
        Text("· \(date.formatted(date: .omitted, time: .standard))").monospacedDigit()
      }
      Spacer(minLength: 0)
      Text("Không lưu / gửi dữ liệu")
    }.font(.system(size: 12)).foregroundStyle(.secondary)
  }

  private func smallMetric(_ title: String, _ value: String, prominent: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.text(title)).font(.system(size: 12)).foregroundStyle(.secondary)
      Text(value).font(.system(size: prominent ? 23 : 14, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
  }

  private func detail(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(L10n.text(title)).fontWeight(.semibold)
      Text(L10n.text(text)).foregroundStyle(.secondary)
    }
  }
}
