import SwiftUI

enum MonitorFormat {
  static func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    if value < 1 { return "0 B/s" }
    return ByteCountFormatter.string(
      fromByteCount: Int64(min(value, Double(Int64.max / 2))), countStyle: .file) + "/s"
  }

  static func memory(_ value: UInt64) -> String {
    ByteSize.string(Int64(clamping: value), countStyle: .memory)
  }
}

private struct MonitorCardTitle: View {
  let title: String
  let icon: String
  let caption: String

  var body: some View {
    HStack {
      Label(L10n.text(title), systemImage: icon).font(.system(size: 14, weight: .semibold))
      Spacer(minLength: 4)
      Text(L10n.text(caption)).font(.system(size: 12)).foregroundStyle(.secondary)
    }
  }
}

private struct MonitorMetric: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(L10n.text(title)).font(.system(size: 12)).foregroundStyle(.secondary)
      Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
    }
  }
}

struct DiskActivityCard: View {
  let rate: DiskIORate?
  let available: Bool

  var body: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 14) {
        MonitorCardTitle(title: "Đọc/ghi ổ đĩa", icon: "externaldrive.badge.timemachine", caption: "Mọi ổ đang gắn")
        HStack(alignment: .top, spacing: 12) {
          MonitorMetric(title: "Đọc", value: MonitorFormat.rate(rate?.read))
          Spacer(minLength: 0)
          MonitorMetric(title: "Ghi", value: MonitorFormat.rate(rate?.write))
        }
        Text(L10n.text(available ? (rate == nil ? "Đang chờ mẫu kế tiếp…" : "Tổng của các ổ, kể cả ổ ngoài") : "Không đọc được bộ đếm ổ đĩa"))
          .font(.system(size: 12)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

struct BatteryCard: View {
  let info: BatteryInfo

  var body: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 14) {
        MonitorCardTitle(
          title: "Pin", icon: info.isCharging ? "battery.100.bolt" : "battery.75",
          caption: info.isCharging ? "Đang sạc" : (info.isExternalPowerConnected ? "Đang cắm nguồn" : "Dùng pin"))
        HStack(alignment: .top, spacing: 12) {
          MonitorMetric(title: "Mức pin", value: info.chargePercent.map { "\($0)%" } ?? "—")
          Spacer(minLength: 0)
          MonitorMetric(title: "Tình trạng", value: info.healthPercent.map { "\($0)%" } ?? "—")
          Spacer(minLength: 0)
          MonitorMetric(title: "Số lần sạc", value: info.cycleCount.map(String.init) ?? "—")
        }
        Text("Tình trạng = dung lượng sạc đầy hiện tại so với dung lượng thiết kế")
          .font(.system(size: 12)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

struct TopProcessesCard: View {
  let processes: [ProcessUsage]

  var body: some View {
    ModernCard {
      VStack(alignment: .leading, spacing: 10) {
        MonitorCardTitle(title: "Tiến trình dùng CPU nhiều nhất", icon: "list.number", caption: "Tiến trình của bạn")
        if processes.isEmpty {
          Text("Đang chờ mẫu kế tiếp…").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
          ForEach(processes) { process in
            HStack {
              Text(process.name).font(.system(size: 13)).lineLimit(1)
              Spacer()
              Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .frame(width: 70, alignment: .trailing)
              Text(MonitorFormat.memory(process.memoryBytes))
                .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            }
          }
        }
        Text("Tính theo một nhân CPU như Activity Monitor; không hiển thị tiến trình hệ thống và của người dùng khác")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
