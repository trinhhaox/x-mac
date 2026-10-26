import AppKit
import SwiftUI

private final class ConverterPanelWindow: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }
    }
}

private struct ConverterTargetPanelContent: View {
    static let width: CGFloat = 320
    static let maxGridHeight: CGFloat = 360
    static let columnCount = 3

    let model: ConverterSelectionModel
    let onPick: (ConversionTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.summary, systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            if model.hasTargets {
                ScrollView {
                    ConverterTargetGrid(model: model, columnCount: Self.columnCount, onPick: onPick)
                }
                .frame(height: min(
                    ConverterTargetGrid.estimatedHeight(for: model, columnCount: Self.columnCount),
                    Self.maxGridHeight
                ))
            } else {
                Text(L10n.text("Không có định dạng đích phù hợp cho các tệp này."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ForEach(model.missingToolHints, id: \.self) { hint in
                    Text(L10n.text(hint)).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
    }
}

/// Small floating chooser shared by Finder Services, the Quick Launcher and the menu bar drop.
@MainActor
final class ConverterTargetPanel: NSObject, NSWindowDelegate {
    static let shared = ConverterTargetPanel()

    private var window: ConverterPanelWindow?
    /// Scratch copies shown in the panel; deleted if it closes (or is replaced) without a format being chosen.
    private var unclaimed: [URL] = []

    private override init() { super.init() }

    /// Shows the panel centred just below `point` (screen coordinates), kept inside the visible screen.
    func show(urls: [URL], near point: NSPoint) {
        show(inputs: BrowserDropInputs(urls: urls), near: point)
    }

    func show(inputs: BrowserDropInputs, near point: NSPoint) {
        close()
        let manager = ConverterManager.shared
        let model = ConverterSelectionModel(inputs: inputs.urls, registry: manager.registry)
        guard !model.inputs.isEmpty else {
            if inputs.disposable { BrowserDropCoordinator.dispose(inputs.urls) }
            return
        }
        if inputs.disposable { unclaimed = inputs.urls }
        let content = ConverterTargetPanelContent(model: model) { [weak self] target in
            self?.unclaimed = []
            manager.enqueue(
                inputs: model.inputs, target: target,
                outputDirectory: inputs.outputDirectory, disposeInputs: inputs.disposable
            )
            self?.close()
        }
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize

        let window = ConverterPanelWindow(
            contentRect: NSRect(origin: Self.origin(for: size, near: point), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.delegate = self
        window.onDismiss = { [weak self] in self?.close() }

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        window.contentView = background

        self.window = window
        window.orderFrontRegardless()
        window.makeKey()
    }

    func close() {
        BrowserDropCoordinator.dispose(unclaimed)
        unclaimed = []
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private static func origin(for size: NSSize, near point: NSPoint) -> NSPoint {
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 8)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        return origin
    }
}
