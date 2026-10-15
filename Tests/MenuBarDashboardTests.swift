import AppKit
import SwiftUI
import Testing

@testable import Xmac

@Suite(.serialized) struct MenuBarDashboardTests {
  private func download(_ status: ManagedDownloadStatus, index: Int = 0) -> ManagedDownload {
    ManagedDownload(
      id: UUID(), sourceURL: "https://example.com/\(index)",
      fileName: index == 0
        ? "bao-cao-tong-hop-thang-10-2026-ban-hoan-chinh.pdf" : "tai-lieu-\(index).zip",
      destinationDirectory: "/tmp", receivedBytes: 27_000_000, expectedBytes: 71_000_000,
      status: status, createdAt: Date())
  }
  private func disk(_ index: Int, mounted: Bool = true, external: Bool = true) -> DiskVolume {
    DiskVolume(
      name: index == 0 ? "SSD Công việc" : "Ổ lưu trữ \(index)", bsdName: "disk\(index)s1",
      mountPoint: mounted ? "/Volumes/Fixture\(index)" : nil, fileSystem: "APFS",
      totalSize: 500_000_000_000, freeSize: 182_300_000_000, isExternal: external, isWritable: true,
      isMounted: mounted)
  }
  private func busySnapshot() -> MenuBarDashboardSnapshot {
    var snapshot = MenuBarDashboardSnapshot()
    snapshot.accessibilityGranted = true
    snapshot.online = false
    snapshot.downloads = [
      download(.downloading), download(.waitingForNetwork, index: 1),
      download(.downloading, index: 2), download(.downloading, index: 3),
    ]
    snapshot.volumes = [disk(0), disk(1, mounted: false), disk(2), disk(3), disk(4)]
    return snapshot
  }

  @Test func snapshotIncludesOnlyActiveDownloadsAndExternalDisks() {
    var snapshot = MenuBarDashboardSnapshot()
    snapshot.downloads = [
      .downloading, .waitingForNetwork, .paused, .completed, .cancelled, .failed,
    ].map { download($0) }
    snapshot.volumes = [disk(0), disk(1, mounted: false), disk(2, external: false)]
    #expect(snapshot.activeDownloads.map(\.status) == [.downloading, .waitingForNetwork])
    #expect(snapshot.externalVolumes.count == 2)
    #expect(!snapshot.externalVolumes[1].isMounted)
  }

  @MainActor private func settle(_ height: () -> CGFloat) async throws -> CGFloat {
    var previous: CGFloat = 0
    var stable = 0
    for _ in 0..<100 {
      let current = height()
      if current > 100, abs(current - previous) < 0.5 { stable += 1 } else { stable = 0 }
      if stable >= 12 { return current }
      previous = current
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    throw TestFailure()
  }
  private struct TestFailure: Error {}

  @MainActor private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_MENUBAR_UI"] == "1"))
  func compactLayoutResizesForEmptyAndBusyStates() async throws {
    _ = NSApplication.shared
    let host = NSHostingView(
      rootView: MenuBarDashboardContent(snapshot: MenuBarDashboardSnapshot(), maximumHeight: 480))
    let window = NSWindow(
      contentRect: NSRect(x: 30, y: 30, width: 380, height: 480), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    var emptyHeight: CGFloat = 0
    for scenario in ["permission", "ready-dark", "busy"] {
      var snapshot = scenario == "busy" ? busySnapshot() : MenuBarDashboardSnapshot()
      if scenario != "permission" {
        snapshot.accessibilityGranted = true
        snapshot.vietnamese = false
      }
      host.appearance = NSAppearance(named: scenario == "ready-dark" ? .darkAqua : .aqua)
      host.rootView = MenuBarDashboardContent(snapshot: snapshot, maximumHeight: 480)
      let height = try await settle {
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
      }
      #expect(height <= 480)
      #expect(height > 200)
      if scenario == "permission" {
        emptyHeight = height
        #expect(height < 450)
      }
      if scenario == "busy" { #expect(height > emptyHeight) }
      window.setContentSize(NSSize(width: 380, height: height))
      host.frame = NSRect(x: 0, y: 0, width: 380, height: height)
      host.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: "/tmp/xmac-menubar-\(scenario).png"))
      print("Dashboard \(scenario): \(height)pt")
      if scenario == "busy" {
        let scroll = try #require(
          descendants(host).compactMap { $0 as? NSScrollView }.first {
            ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 1
          })
        let document = try #require(scroll.documentView)
        scroll.contentView.scroll(
          to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(nanoseconds: 30_000_000)
        host.layoutSubtreeIfNeeded()
        let bottom = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bottom)
        try #require(bottom.representation(using: .png, properties: [:])).write(
          to: URL(fileURLWithPath: "/tmp/xmac-menubar-busy-scrolled.png"))
      }
    }
  }

  @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_MENUBAR_UI"] == "1"))
  func realPopoverTracksPreferredContentSize() async throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 100, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let anchor = NSButton(frame: NSRect(x: 20, y: 20, width: 50, height: 30))
    window.contentView?.addSubview(anchor)
    window.orderFrontRegardless()
    let controller = NSHostingController(
      rootView: MenuBarDashboardContent(snapshot: MenuBarDashboardSnapshot(), maximumHeight: 480))
    controller.sizingOptions = [.preferredContentSize]
    let popover = NSPopover()
    popover.behavior = .applicationDefined
    popover.animates = false
    popover.contentViewController = controller
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    defer {
      popover.close()
      window.orderOut(nil)
      window.contentView = nil
    }
    let empty = try await settle {
      controller.view.layoutSubtreeIfNeeded()
      return popover.contentSize.height
    }
    #expect(popover.isShown)
    #expect(empty < 450)
    controller.rootView = MenuBarDashboardContent(snapshot: busySnapshot(), maximumHeight: 480)
    let busy = try await settle {
      controller.view.layoutSubtreeIfNeeded()
      return popover.contentSize.height
    }
    #expect(busy > empty)
    #expect(busy <= 480)
    controller.rootView = MenuBarDashboardContent(
      snapshot: MenuBarDashboardSnapshot(), maximumHeight: 480)
    let shrunk = try await settle {
      controller.view.layoutSubtreeIfNeeded()
      return popover.contentSize.height
    }
    #expect(abs(shrunk - empty) < 1)
  }

  @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_MENUBAR_UI"] == "1"))
  func nativeKeepAwakeSwitchUsesInjectedBindingOnly() async throws {
    _ = NSApplication.shared
    var values: [Bool] = []
    let host = NSHostingView(
      rootView: MenuBarDashboardContent(
        snapshot: MenuBarDashboardSnapshot(),
        actions: MenuBarDashboardActions(keepAwake: { values.append($0) })))
    let window = NSWindow(
      contentRect: NSRect(x: 30, y: 30, width: 380, height: 500), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    _ = try await settle {
      host.layoutSubtreeIfNeeded()
      return host.fittingSize.height
    }
    let toggle = try #require(descendants(host).compactMap { $0 as? NSSwitch }.first)
    let action = try #require(toggle.action)
    toggle.state = .off
    #expect(toggle.sendAction(action, to: toggle.target))
    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(values == [false])
  }
}
