import AppKit
import os

/// Lets the keyboard hook ask, from its own thread, whether the donut is on screen.
enum DonutActivity {
    static let isVisible = OSAllocatedUnfairLock(initialState: false)
}

/// Owns the experimental "⌃ while dragging" donut: monitor, panel and the on/off setting.
@MainActor
final class DonutController: ObservableObject {
    static let shared = DonutController()
    static let enabledKey = "Converter.DonutEnabled"
    private static let escapeKeyCode: UInt16 = 53
    private static let dragEndGrace: UInt64 = 300_000_000

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { monitor.start() } else { monitor.stop(); close() }
        }
    }

    private let defaults: UserDefaults
    private let recents: DonutRecentTargets
    private var panel: DonutPanel?
    private var escapeMonitor: Any?
    private lazy var monitor = DragMonitor(
        onArm: { [weak self] urls, point in MainActor.assumeIsolated { self?.show(urls: urls, at: point) } },
        onDisarm: { [weak self] in MainActor.assumeIsolated { self?.close() } },
        onMouseUp: { [weak self] in MainActor.assumeIsolated { self?.closeAfterDragEnd() } }
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = DonutRecentTargets(defaults: defaults)
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func start() {
        if isEnabled { monitor.start() }
    }

    func stop() {
        monitor.stop()
        close()
    }

    private func show(urls: [URL], at point: NSPoint) {
        close()
        let model = ConverterSelectionModel(inputs: urls, registry: ConverterManager.shared.registry)
        let slots = DonutSlot.make(targets: model.sections.flatMap(\.targets), recentIDs: recents.ids)
        guard !slots.isEmpty else { return }
        let geometry = DonutGeometry(slotCount: slots.count)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let centre = DonutGeometry.clampedCentre(point, in: screen?.visibleFrame ?? .zero, radius: geometry.windowSide / 2)
        let view = DonutView(
            slots: slots, geometry: geometry, summary: model.summary,
            onPick: { [weak self] slot, payload in self?.pick(slot, payload: payload) }, onLeave: { [weak self] in self?.close() }
        )
        let panel = DonutPanel(centre: centre, side: geometry.windowSide, view: view)
        self.panel = panel
        DonutActivity.isVisible.withLock { $0 = true }
        panel.orderFrontRegardless()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Browser drops are fetched only now; the ring was built from the type the browser announced.
    private func pick(_ slot: DonutSlot, payload: BrowserDragPayload) {
        let point = NSEvent.mouseLocation
        close()
        Task {
            let drops = BrowserDropCoordinator.shared
            let registry = ConverterManager.shared.registry
            guard let files = await drops.fetch(payload) else { return }
            drops.deliver(files, registry: registry) { files in
                // The real file can differ from the announced type, so the chosen format is re-checked.
                guard case .target(let target) = slot, registry.targets(for: files.urls).contains(where: { $0.id == target.id }) else {
                    return ConverterTargetPanel.shared.show(inputs: files, near: point)
                }
                recents.record(target.id)
                ConverterManager.shared.enqueue(
                    inputs: files.urls, target: target, outputDirectory: files.outputDirectory, disposeInputs: files.disposable
                )
            }
        }
    }

    /// A drop on a slice arrives right after the global mouse-up, so closing must wait a moment.
    private func closeAfterDragEnd() {
        guard let shown = panel else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.dragEndGrace)
            if self?.panel === shown { self?.close() }
        }
    }

    private func close() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        DonutActivity.isVisible.withLock { $0 = false }
    }
}
