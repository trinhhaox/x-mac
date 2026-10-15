import AppKit
import Darwin
import SwiftUI
import Testing

@testable import Xmac

struct SystemMonitorTests {
  @Test func shortRouteAddressRecordsDoNotHideLaterPhysicalInterfaces() {
    var record = if_msghdr2()
    record.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
    record.ifm_type = UInt8(RTM_IFINFO2)
    record.ifm_flags = IFF_UP
    record.ifm_index = 1
    record.ifm_data.ifi_ibytes = 9_000_000_000
    record.ifm_data.ifi_obytes = 8_000_000_000
    var data = Data([8, 0, 5, 12, 0, 0, 0, 0])  // Short RTM_NEWADDR before the interface record.
    withUnsafeBytes(of: &record) { data.append(contentsOf: $0) }
    #expect(
      SystemProbe.decodeNetworkCounters(data, interfaceName: { _ in "en0" }) == [
        "en0": NetworkCounter(received: 9_000_000_000, sent: 8_000_000_000)
      ])
    #expect(SystemProbe.decodeNetworkCounters(data, interfaceName: { _ in "utun0" }) == [:])
    #expect(
      SystemProbe.decodeNetworkCounters(Data([0, 0, 5, 12]), interfaceName: { _ in "en0" }) == nil)
    #expect(
      SystemProbe.decodeNetworkCounters(Data(data.dropLast()), interfaceName: { _ in "en0" }) == nil
    )
  }

  @Test func cpuUsesIntervalAndHandlesTickWrap() throws {
    let previous = CPUTicks(user: 100, system: 50, idle: 100, nice: 0)
    let next = CPUTicks(user: 120, system: 60, idle: 170, nice: 0)
    #expect(try #require(next.usage(since: previous)) == 30)
    #expect(previous.usage(since: previous) == nil)
    let wrapped = CPUTicks(user: 4, system: 0, idle: 10, nice: 0)
    let before = CPUTicks(user: UInt32.max - 5, system: 0, idle: 0, nice: 0)
    #expect(wrapped.usage(since: before) == 50)
  }

  @Test func networkRejectsResetsNewInterfacesAndLongGaps() throws {
    let old = ["en0": NetworkCounter(received: 1_000, sent: 2_000)]
    let next = [
      "en0": NetworkCounter(received: 3_000, sent: 3_000),
      "en9": NetworkCounter(received: 99_999, sent: 99_999),
    ]
    let rate = try #require(NetworkRate.calculate(previous: old, current: next, elapsed: 2))
    #expect(rate == NetworkRate(received: 1_000, sent: 500))
    for interval in [0.0, -1, 11, .infinity, .nan] {
      #expect(NetworkRate.calculate(previous: old, current: next, elapsed: interval) == nil)
    }
    #expect(NetworkRate.calculate(previous: next, current: old, elapsed: 2) == nil)
    #expect(NetworkRate.calculate(previous: old, current: [:], elapsed: 2) == nil)
    #expect(
      NetworkRate.calculate(previous: old, current: old, elapsed: 2)
        == NetworkRate(received: 0, sent: 0))
  }

  @MainActor @Test func missingDataNeverBecomesZeroAndHistoryIsBounded() {
    let monitor = SystemMonitor()
    var sample = SystemSample()
    sample.uptime = 10
    monitor.accept(sample)
    #expect(monitor.cpuUsage == nil)
    #expect(monitor.networkRate == nil)
    for index in 1...40 {
      sample.uptime += 2
      sample.cpu = CPUTicks(user: UInt32(index * 10), system: 0, idle: UInt32(index * 10), nice: 0)
      monitor.accept(sample)
    }
    #expect(monitor.cpuHistory.count == 30)
    #expect(monitor.cpuUsage == 50)
    sample.uptime += 30
    monitor.accept(sample)
    #expect(monitor.cpuUsage == nil)
    #expect(SystemMonitor.thermalTitle(.critical).contains("Rất nóng"))
  }

  @MainActor @Test func startIsIdempotentAndStopCancelsSampling() async throws {
    var calls = 0
    let monitor = SystemMonitor(probe: {
      calls += 1
      return SystemSample()
    })
    monitor.start()
    monitor.start()
    for _ in 0..<100 {
      if calls > 0 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(calls == 1)
    monitor.stop()
    #expect(!monitor.running)
    try await Task.sleep(nanoseconds: 2_100_000_000)
    #expect(calls == 1)
    monitor.start()
    for _ in 0..<100 {
      if calls > 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    monitor.stop()
    #expect(calls == 2)
  }

  @Test func liveProbeReadsActualMacWithoutPrivileges() async throws {
    let first = SystemProbe.read()
    #expect(first.cpu != nil)
    #expect(first.memoryUsed != nil)
    #expect(try #require(first.memoryUsed) <= ProcessInfo.processInfo.physicalMemory)
    #expect(try #require(first.diskTotal) > 0)
    #expect(try #require(first.diskAvailable) >= 0)
    #expect(first.network != nil)
    var addresses: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&addresses) == 0 {
      defer { freeifaddrs(addresses) }
      var cursor = addresses
      while let item = cursor {
        let entry = item.pointee
        let name = String(cString: entry.ifa_name)
        if name.hasPrefix("en"), entry.ifa_flags & UInt32(IFF_UP) != 0 {
          #expect(first.network?[name] != nil)
        }
        cursor = entry.ifa_next
      }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    let next = SystemProbe.read()
    let initialCPU = try #require(first.cpu)
    let cpu = try #require(next.cpu?.usage(since: initialCPU))
    #expect((0...100).contains(cpu))
    print(
      "System monitor live: CPU \(cpu)%, RAM \(first.memoryUsed ?? 0), network interfaces \(first.network?.keys.sorted() ?? [])"
    )
  }

  @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_MONITOR_UI"] == "1"))
  func renderSystemMonitorAtMinimumPaneWidthAndDarkMode() async throws {
    _ = NSApplication.shared
    for (name, width, height, appearance) in [
      ("full", 900.0, 700.0, NSAppearance.Name.aqua),
      ("compact", 672.0, 600.0, NSAppearance.Name.darkAqua),
    ] {
      let monitor = SystemMonitor()
      let host = NSHostingView(rootView: SystemMonitorView(monitor: monitor))
      host.appearance = NSAppearance(named: appearance)
      let window = NSWindow(
        contentRect: NSRect(x: 30, y: 30, width: width, height: height), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.orderFrontRegardless()
      host.frame = NSRect(x: 0, y: 0, width: width, height: height)
      for _ in 0..<250 {
        if monitor.cpuUsage != nil { break }
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      #expect(monitor.cpuUsage != nil)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: "/tmp/xmac-system-monitor-\(name).png"))
      window.orderOut(nil)
      window.contentView = nil
      monitor.stop()
    }
  }

  @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_MONITOR_UI"] == "1"))
  func renderCompactPausedDetailsAndMissingData() async throws {
    _ = NSApplication.shared
    let monitor = SystemMonitor(probe: { SystemSample() })
    let presentation = SystemMonitorPresentation()
    let host = NSHostingView(
      rootView: SystemMonitorView(monitor: monitor, presentation: presentation)
        .transaction { $0.disablesAnimations = true })
    let window = NSWindow(
      contentRect: NSRect(x: 30, y: 30, width: 672, height: 1100), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    host.frame = NSRect(x: 0, y: 0, width: 672, height: 1100)
    defer {
      monitor.stop()
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<100 {
      if monitor.sample != nil { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    monitor.stop()
    var sample = SystemSample()
    sample.uptime = 100
    sample.memoryUsed = ProcessInfo.processInfo.physicalMemory * 73 / 100
    sample.memoryCompressed = 3_452_000_000
    sample.memoryWired = 2_751_000_000
    sample.swapUsed = 0
    sample.diskTotal = 500_000_000_000
    sample.diskAvailable = 71_300_000_000
    sample.thermal = .serious
    var busy: UInt32 = 0
    var idle: UInt32 = 0
    for index in 0..<31 {
      let usage = UInt32(20 + (index * 13) % 47)
      busy += usage
      idle += 100 - usage
      sample.cpu = CPUTicks(user: busy, system: 0, idle: idle, nice: 0)
      sample.uptime += 2
      sample.network = [
        "en0": NetworkCounter(received: UInt64(index) * 2_744_000, sent: UInt64(index) * 231_000)
      ]
      monitor.accept(sample)
    }
    #expect(monitor.cpuHistory.count == 30)
    #expect(monitor.networkRate != nil)
    presentation.detailsExpanded = true
    try await Task.sleep(nanoseconds: 50_000_000)
    func capture(_ suffix: String) throws {
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: "/tmp/xmac-system-monitor-\(suffix).png"))
    }
    try capture("details-paused")
    presentation.detailsExpanded = false
    host.frame.size.height = 600
    window.setContentSize(NSSize(width: 672, height: 600))
    try await Task.sleep(nanoseconds: 50_000_000)
    try capture("compact-populated")
    sample.uptime += 2
    sample.cpu = nil
    sample.network = nil
    sample.memoryUsed = nil
    sample.memoryCompressed = nil
    sample.memoryWired = nil
    sample.swapUsed = nil
    sample.diskTotal = nil
    sample.diskAvailable = nil
    monitor.accept(sample)
    #expect(monitor.cpuUsage == nil)
    #expect(monitor.networkRate == nil)
    try await Task.sleep(nanoseconds: 50_000_000)
    try capture("missing-data")
  }
}
