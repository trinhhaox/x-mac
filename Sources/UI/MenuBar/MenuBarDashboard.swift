import SwiftUI

private final class MenuBarDashboardState: ObservableObject {
  @Published var ejectCandidate: DiskVolume?
  @Published var message = ""
  @Published var ejecting = false
}

struct MenuBarDashboardSnapshot {
  var vietnamese = true
  var typingMethod = "Telex"
  var accessibilityGranted = false
  var online = true
  var keepAwake = true
  var shortcut = "⌥⇧Space"
  var downloads: [ManagedDownload] = []
  var volumes: [DiskVolume] = []
  var disksLoading = false
  var ejecting = false
  var message = ""

  var activeDownloads: [ManagedDownload] {
    downloads.filter { $0.status == .downloading || $0.status == .waitingForNetwork }
  }
  var externalVolumes: [DiskVolume] { volumes.filter(\.isExternal) }
}

struct MenuBarDashboardActions {
  var open: (NavigationTab) -> Void = { _ in }
  var launcher: () -> Void = {}
  var language: (Bool) -> Void = { _ in }
  var permission: () -> Void = {}
  var keepAwake: (Bool) -> Void = { _ in }
  var pause: (UUID) -> Void = { _ in }
  var finder: (DiskVolume) -> Void = { _ in }
  var eject: (DiskVolume) -> Void = { _ in }
}

private final class DashboardHeight: ObservableObject {
  @Published var measured: CGFloat = 260
}

/// Only the middle scrolls. The popover shrinks to the measured content when empty.
struct MenuBarDashboardViewport<Content: View>: View {
  let maximumHeight: CGFloat
  @ViewBuilder var content: () -> Content
  @StateObject private var height = DashboardHeight()

  var body: some View {
    ScrollView {
      content()
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(
          GeometryReader { proxy in
            Color.clear
              .onAppear { updateHeight(proxy.size.height) }
              .onChange(of: proxy.size.height) { updateHeight($0) }
          })
    }
    .frame(width: 380, height: min(max(1, height.measured), max(80, maximumHeight)))
  }

  private func updateHeight(_ value: CGFloat) {
    if value.isFinite, value > 0, abs(value - height.measured) > 0.5 { height.measured = value }
  }
}

struct MenuBarDashboardContent: View {
  let snapshot: MenuBarDashboardSnapshot
  var actions = MenuBarDashboardActions()
  var maximumHeight: CGFloat = 620

  var body: some View {
    VStack(spacing: 0) {
      header.padding(16)
      MenuBarDashboardViewport(maximumHeight: maximumHeight - 160) {
        VStack(alignment: .leading, spacing: 10) {
          languageSection
          downloadsSection
          disksSection
          if !snapshot.message.isEmpty {
            Text(L10n.text(snapshot.message)).font(.system(size: 12)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
      }
      Divider()
      HStack(spacing: 8) {
        shortcut("Hệ thống", icon: "waveform.path.ecg", tab: .systemMonitor)
        shortcut("Tìm tệp", icon: "doc.text.magnifyingglass", tab: .fileSearch)
        shortcut("Cài đặt", icon: "gearshape", tab: .settings)
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
    }
    .frame(width: 380)
    .background(XmacTheme.workspaceBackground)
    .environment(\.controlActiveState, .active)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Button {
        actions.open(.overview)
      } label: {
        HStack(spacing: 9) {
          BrandIconTile(iconName: "square.grid.2x2.fill", color: XmacTheme.blue, size: 32)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
              Text("Xmac").font(.system(size: 17, weight: .bold, design: .rounded))
              Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Label(
              L10n.text(snapshot.online ? "Có kết nối mạng" : "Ngoại tuyến"),
              systemImage: snapshot.online ? "wifi" : "wifi.slash"
            )
            .font(.system(size: 11)).foregroundStyle(.secondary)
          }
        }
      }
      .buttonStyle(.plain).help(L10n.text("Mở bảng điều khiển Xmac"))
      .accessibilityIdentifier("dashboard.overview")
      .accessibilityLabel("Mở bảng điều khiển Xmac")
      Spacer(minLength: 8)
      Button(action: actions.launcher) {
        VStack(spacing: 2) {
          Label("Mở nhanh", systemImage: "magnifyingglass").font(
            .system(size: 12, weight: .semibold))
          Text(snapshot.shortcut).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(XmacTheme.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain).foregroundStyle(XmacTheme.blue)
      .accessibilityIdentifier("dashboard.launcher")
    }
  }

  private var languageSection: some View {
    group {
      HStack {
        Label("Bộ gõ", systemImage: "character.bubble").font(.system(size: 13, weight: .semibold))
        Spacer()
        Text(snapshot.typingMethod).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      if snapshot.accessibilityGranted {
        HStack(spacing: 4) {
          languageButton("Tiếng Việt", vietnamese: true)
          languageButton("English", vietnamese: false)
        }
        .padding(3).background(XmacTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
      } else {
        HStack(spacing: 6) {
          Image(systemName: "lock.shield").foregroundStyle(.orange)
          Text("Cần quyền Trợ năng").font(.system(size: 12))
          Spacer(minLength: 4)
          Button("Cấp quyền", action: actions.permission)
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(
              XmacTheme.blue
            )
            .padding(.vertical, 5).padding(.horizontal, 8)
            .background(XmacTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityIdentifier("dashboard.permission")
        }
      }
    }
  }

  private func languageButton(_ title: String, vietnamese: Bool) -> some View {
    let selected = snapshot.vietnamese == vietnamese
    return Button {
      actions.language(vietnamese)
    } label: {
      HStack(spacing: 5) {
        if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
        Text(L10n.text(title)).font(.system(size: 12, weight: selected ? .semibold : .regular))
      }
      .frame(maxWidth: .infinity).padding(.vertical, 6)
      .foregroundStyle(selected ? XmacTheme.blue : Color.secondary)
      .background(
        selected ? XmacTheme.cardBackground : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(vietnamese ? "dashboard.vietnamese" : "dashboard.english")
  }

  private var downloadsSection: some View {
    group {
      sectionTitle(
        "Tải xuống", icon: "arrow.down.circle", count: snapshot.activeDownloads.count,
        action: "Xem tất cả", tab: .downloads)
      if snapshot.activeDownloads.isEmpty {
        empty(L10n.text("Không có tác vụ đang tải"), icon: "tray")
      }
      ForEach(snapshot.activeDownloads.prefix(3)) { item in
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 8) {
            Text(item.fileName).font(.system(size: 12, weight: .medium)).lineLimit(1)
              .truncationMode(.middle)
              .help(item.fileName)
            Spacer(minLength: 0)
            Button {
              actions.pause(item.id)
            } label: {
              Image(systemName: "pause.fill")
            }
            .buttonStyle(.plain).foregroundStyle(XmacTheme.blue)
            .padding(5).background(
              XmacTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6)
            )
            .accessibilityLabel(L10n.format("Tạm dừng tải %@", item.fileName))
            .accessibilityIdentifier("dashboard.pause.\(item.id.uuidString)")
          }
          if item.expectedBytes > 0 { ProgressView(value: item.progress).tint(XmacTheme.blue) }
          Text(
            item.status == .waitingForNetwork
              ? "Chờ kết nối mạng"
              : (item.expectedBytes > 0
                ? L10n.format("%lld%% đã tải", Int64(item.progress * 100)) : L10n.text("Đang tải · chưa rõ tổng dung lượng"))
          )
          .font(.system(size: 11)).foregroundStyle(
            item.status == .waitingForNetwork ? Color.orange : Color.secondary)
        }
      }
      HStack {
        Label("Giữ máy thức khi tải", systemImage: "moon.zzz").font(.system(size: 12))
        Spacer(minLength: 8)
        Toggle(
          "Giữ máy thức khi tải", isOn: Binding(get: { snapshot.keepAwake }, set: actions.keepAwake)
        )
        .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(XmacTheme.blue)
        .accessibilityIdentifier("dashboard.keepAwake")
      }
      .help("Chỉ giữ máy thức khi có tác vụ đang tải; màn hình vẫn được phép tắt.")
    }
  }

  private var disksSection: some View {
    group {
      sectionTitle(
        "Ổ đĩa ngoài", icon: "externaldrive", count: snapshot.externalVolumes.count,
        action: "Quản lý", tab: .diskNTFS)
      if snapshot.externalVolumes.isEmpty {
        empty(
          snapshot.disksLoading ? "Đang đọc ổ đĩa…" : "Chưa có ổ đĩa ngoài", icon: "externaldrive")
      }
      ForEach(snapshot.externalVolumes.prefix(4)) { disk in
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 3) {
            Text(disk.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(
              .middle
            ).help(disk.name).foregroundStyle(Color.primary)
            Text(
              disk.hasReliableCapacity
                ? L10n.format("%@ trống · %@", disk.formattedFreeSize, disk.fileSystem) : L10n.text("Chưa gắn kết")
            )
            .font(.system(size: 11)).foregroundStyle(Color.secondary)
          }
          Spacer(minLength: 0)
          Button {
            actions.finder(disk)
          } label: {
            Image(systemName: "folder")
          }
          .buttonStyle(.plain).disabled(!disk.isMounted || snapshot.ejecting)
          .help(L10n.format("Mở %@ trong Finder", disk.name)).accessibilityLabel(L10n.format("Mở %@ trong Finder", disk.name))
          .accessibilityIdentifier("dashboard.finder.\(disk.id)")
          Button {
            actions.eject(disk)
          } label: {
            Image(systemName: "eject")
          }
          .buttonStyle(.plain).disabled(!disk.isMounted || snapshot.ejecting)
          .help(L10n.format("Ngắt kết nối %@", disk.name)).accessibilityLabel(L10n.format("Ngắt kết nối %@", disk.name))
          .accessibilityIdentifier("dashboard.eject.\(disk.id)")
        }
        .foregroundStyle(XmacTheme.blue)
      }
    }
  }

  private func sectionTitle(
    _ title: String, icon: String, count: Int, action: String, tab: NavigationTab
  ) -> some View {
    HStack(spacing: 5) {
      Label(L10n.text(title), systemImage: icon).font(.system(size: 13, weight: .semibold))
      if count > 0 {
        Text("\(count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      Button {
        actions.open(tab)
      } label: {
        HStack(spacing: 3) {
          Text(L10n.text(action))
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
        }
      }
      .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(XmacTheme.blue)
      .padding(.vertical, 3)
      .accessibilityIdentifier("dashboard.open.\(tab.rawValue)")
    }
  }

  private func empty(_ text: String, icon: String) -> some View {
    Label(L10n.text(text), systemImage: icon).font(.system(size: 12)).foregroundStyle(.secondary).padding(
      .vertical, 3)
  }

  private func shortcut(_ title: String, icon: String, tab: NavigationTab) -> some View {
    Button {
      actions.open(tab)
    } label: {
      VStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 15))
        Text(L10n.text(title)).font(.system(size: 12, weight: .medium))
      }
      .frame(maxWidth: .infinity).padding(.vertical, 5).contentShape(Rectangle())
    }
    .buttonStyle(.plain).foregroundStyle(XmacTheme.blue)
    .accessibilityIdentifier("dashboard.open.\(tab.rawValue)")
  }

  private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10, content: content)
      .padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(XmacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(XmacTheme.cardStroke, lineWidth: 1))
  }
}

struct MenuBarDashboard: View {
  @ObservedObject private var localization = LocalizationManager.shared
  @ObservedObject private var downloads = DownloadManager.shared
  @ObservedObject private var disks = DiskManager.shared
  @ObservedObject private var ime = InputHookManager.shared
  @ObservedObject private var permissions = PermissionsManager.shared
  @ObservedObject private var environment = DownloadEnvironment.shared
  @ObservedObject private var launcher = QuickLauncher.shared
  @StateObject private var state = MenuBarDashboardState()

  var body: some View {
    MenuBarDashboardContent(
      snapshot: MenuBarDashboardSnapshot(
        vietnamese: ime.isVietnameseMode, typingMethod: ime.typingMethod.rawValue,
        accessibilityGranted: permissions.isAccessibilityGranted, online: environment.online,
        keepAwake: environment.keepAwake, shortcut: launcher.shortcut.title,
        downloads: downloads.items,
        volumes: disks.volumes, disksLoading: disks.isLoading, ejecting: state.ejecting,
        message: state.message),
      actions: MenuBarDashboardActions(
        open: open, launcher: { launcher.show() },
        language: { vietnamese in
          guard permissions.isAccessibilityGranted, vietnamese != ime.isVietnameseMode else {
            return
          }
          ime.toggleLanguage()
        },
        permission: {
          StatusBarController.shared.closeDashboard()
          permissions.openAccessibilitySettings()
        }, keepAwake: { environment.keepAwake = $0 }, pause: { downloads.pause($0) },
        finder: { disk in
          guard disk.isMounted, !state.ejecting else { return }
          NTFSMountHelper.shared.openInFinder(volume: disk)
        },
        eject: { disk in
          guard disk.isMounted, !state.ejecting else { return }
          state.ejectCandidate = disk
        }),
      maximumHeight: max(240, min(620, (NSScreen.main?.visibleFrame.height ?? 720) - 100))
    )
    .environment(\.locale, localization.language.locale)
    .id(localization.language)
    .alert(item: $state.ejectCandidate) { volume in
      Alert(
        title: Text(L10n.format("Ngắt kết nối %@?", volume.name)),
        message: Text("Hãy hoàn tất các thao tác đọc/ghi trên ổ đĩa trước khi tiếp tục."),
        primaryButton: .destructive(Text("Ngắt kết nối")) {
          state.ejecting = true
          NTFSMountHelper.shared.ejectVolume(volume: volume) { success in
            DispatchQueue.main.async {
              state.ejecting = false
              state.message =
                success
                ? L10n.format("Đã ngắt kết nối %@.", volume.name)
                : "Chưa thể ngắt kết nối; ổ có thể đang được sử dụng."
              disks.refreshVolumes()
            }
          }
        }, secondaryButton: .cancel(Text("Hủy")))
    }
  }

  private func open(_ tab: NavigationTab) {
    StatusBarController.shared.closeDashboard()
    AppState.shared.selectedTab = tab
    AppDelegate.shared.createMainWindow()
  }
}
