import AppKit
import Carbon
import Combine

enum LauncherShortcut: String, CaseIterable, Identifiable {
    case optionShiftSpace, controlOptionSpace, commandOptionK
    var id: String { rawValue }
    var title: String {
        switch self {
        case .optionShiftSpace: return "⌥⇧Space"
        case .controlOptionSpace: return "⌃⌥Space"
        case .commandOptionK: return "⌘⌥K"
        }
    }
    var keyCode: UInt32 { self == .commandOptionK ? 40 : 49 }
    var modifiers: UInt32 {
        switch self {
        case .optionShiftSpace: return UInt32(optionKey | shiftKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .commandOptionK: return UInt32(cmdKey | optionKey)
        }
    }
}

private final class LauncherPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

private final class LauncherTable: NSTableView {
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()
        case 53: onDismiss?()
        default: super.keyDown(with: event)
        }
    }
}

final class QuickLauncher: NSObject, ObservableObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = QuickLauncher()
    @Published private(set) var shortcut = LauncherShortcut(rawValue: UserDefaults.standard.string(forKey: "Launcher.Shortcut") ?? "") ?? .optionShiftSpace
    @Published private(set) var shortcutMessage = ""
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registrationID: UInt32 = 0
    private var panel: NSPanel?
    private let search = NSSearchField()
    private let table = LauncherTable()
    private let footer = NSTextField(labelWithString: L10n.text("↑↓ Chọn • Enter Mở • Esc Đóng"))
    private let files = FileSearchEngine()
    private var subscription: AnyCancellable?
    private var applications: [LauncherEntry] = []
    private var results: [LauncherEntry] = []
    private var indexingApps = false
    private var didLoadApps = false
    private var lastAppScan = Date.distantPast
    private static let signature: OSType = 0x584D514C

    private override init() { super.init() }

    func start() {
        guard handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == QuickLauncher.signature else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<QuickLauncher>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.toggle() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { shortcutMessage = L10n.format("Không thể khởi tạo phím tắt (%d).", status); return }
        setShortcut(shortcut)
    }

    func setShortcut(_ choice: LauncherShortcut) {
        if hotKey != nil, choice == shortcut { return }
        var replacement: EventHotKeyRef?
        let nextID = registrationID &+ 1
        let status = RegisterEventHotKey(choice.keyCode, choice.modifiers,
                                        EventHotKeyID(signature: Self.signature, id: nextID), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else {
            shortcutMessage = L10n.format("Không thể dùng %@, có thể đang bị ứng dụng khác chiếm (%d).", choice.title, status)
            return
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        registrationID = nextID
        shortcut = choice
        UserDefaults.standard.set(choice.rawValue, forKey: "Launcher.Shortcut")
        shortcutMessage = L10n.format("Mở nhanh bằng %@. Không cần quyền Trợ năng.", choice.title)
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        hide()
    }

    func toggle() { panel?.isVisible == true ? hide() : show() }

    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        refreshLocalizedChrome()
        StatusBarController.shared.closeDashboard()
        search.stringValue = ""
        reloadResults(resetSelection: true)
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY + frame.height / 8 - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(search)
        if !indexingApps && (!didLoadApps || Date().timeIntervalSince(lastAppScan) > 60) {
            indexingApps = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                             FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
                let entries = LauncherEntry.applications(in: roots)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.applications = entries
                    self.indexingApps = false
                    self.didLoadApps = true
                    self.lastAppScan = Date()
                    self.reloadResults()
                }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        files.cancelSearch()
    }

    private func createPanel() {
        let window = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = L10n.text("Mở nhanh Xmac")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onDismiss = { [weak self] in self?.hide() }
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root
        search.placeholderString = L10n.text("Tìm lệnh, ứng dụng, tệp hoặc tính: = (12 + 3) / 5")
        search.font = .systemFont(ofSize: 21)
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel(L10n.text("Tìm lệnh, ứng dụng hoặc tệp"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 48
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(openSelection)
        table.onOpen = { [weak self] in self?.openSelection() }
        table.onDismiss = { [weak self] in self?.hide() }
        table.setAccessibilityLabel(L10n.text("Kết quả mở nhanh"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [search, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 25),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        panel = window
        subscription = files.$results.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reloadResults() }
    }

    func controlTextDidChange(_ notification: Notification) {
        files.cancelSearch()
        reloadResults(resetSelection: true)
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count >= 2 && !query.hasPrefix("=") && LauncherCalculator.result(for: query) == nil {
            files.scheduleSearch(text: search.stringValue, scope: .home, kind: .all, includeContents: false)
        } else { files.cancelSearch() }
    }

    private func reloadResults(resetSelection: Bool = false) {
        let selectedID = results.indices.contains(table.selectedRow) ? results[table.selectedRow].id : nil
        let entries = LauncherEntry.commands + applications
        let primary = LauncherEntry.matching(entries, query: search.stringValue, limit: 20)
        let fileEntries = search.stringValue.count >= 2 ? files.results.prefix(10).map {
            LauncherEntry(id: "file:" + $0.path, title: $0.name, subtitle: $0.path,
                          icon: "doc", destination: .file($0.path))
        } : []
        if let value = LauncherCalculator.result(for: search.stringValue) {
            results = [LauncherEntry(id: "calculation:" + value, title: "= " + value,
                subtitle: L10n.text("Enter để chép kết quả • Phép tính gần đúng, tối đa 12 chữ số có nghĩa"),
                icon: "calculator", destination: .calculation(value))]
        } else { results = primary + fileEntries }
        table.reloadData()
        if !results.isEmpty {
            let selected = resetSelection ? 0 : (results.firstIndex { $0.id == selectedID } ?? 0)
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        }
        footer.stringValue = results.isEmpty ? L10n.text("Không có kết quả • Esc Đóng") : L10n.text("↑↓ Chọn • Enter Mở / Chép kết quả • Esc Đóng")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = results[row]
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: entry.subtitle)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let image: NSImage?
        switch entry.destination {
        case .application(let path), .file(let path): image = NSWorkspace.shared.icon(forFile: path)
        default: image = NSImage(systemSymbolName: entry.icon, accessibilityDescription: nil)
        }
        let icon = NSImageView()
        icon.image = image
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let rowView = NSStackView(views: [icon, text])
        rowView.orientation = .horizontal
        rowView.spacing = 12
        return rowView
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Do not swallow candidate selection/commit keys of a system IME.
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
            guard !results.isEmpty else { return true }
            let delta = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = min(max(0, table.selectedRow + delta), results.count - 1)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) { openSelection(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { hide(); return true }
        return false
    }

    @objc private func openSelection() {
        guard results.indices.contains(table.selectedRow) else { return }
        let entry = results[table.selectedRow]
        hide()
        switch entry.destination {
        case .tab(let tab):
            AppState.shared.selectedTab = tab
            AppDelegate.shared.createMainWindow()
        case .toggleLanguage:
            if PermissionsManager.shared.isAccessibilityGranted { InputHookManager.shared.toggleLanguage() }
            else {
                AppState.shared.selectedTab = .settings
                AppDelegate.shared.createMainWindow()
            }
        case .application(let path), .file(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .calculation(let value):
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(value, forType: .string) {
                FinderCutPasteManager.shared.handleCopy()
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func refreshLocalizedChrome() {
        panel?.title = L10n.text("Mở nhanh Xmac")
        search.placeholderString = L10n.text("Tìm lệnh, ứng dụng, tệp hoặc tính: = (12 + 3) / 5")
        search.setAccessibilityLabel(L10n.text("Tìm lệnh, ứng dụng hoặc tệp"))
        table.setAccessibilityLabel(L10n.text("Kết quả mở nhanh"))
    }
}
