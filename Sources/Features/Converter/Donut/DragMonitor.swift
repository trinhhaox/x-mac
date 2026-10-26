import AppKit

/// Passive global observer of a file drag in another app. Feeds `DragGestureDetector` and reports
/// when ⌃ arms/disarms it. Never touches the event tap: a mouse hook there once froze the system.
/// Handlers run on the main thread.
final class DragMonitor {
    private var detector = DragGestureDetector()
    private var monitor: Any?
    private var baselineChangeCount = 0
    private let pasteboard = NSPasteboard(name: .drag)

    private let onArm: (_ urls: [URL], _ point: NSPoint) -> Void
    private let onDisarm: () -> Void
    private let onMouseUp: () -> Void

    init(
        onArm: @escaping (_ urls: [URL], _ point: NSPoint) -> Void,
        onDisarm: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        self.onArm = onArm
        self.onDisarm = onDisarm
        self.onMouseUp = onMouseUp
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in self?.handle(event) }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        detector = DragGestureDetector()
    }

    private func handle(_ event: NSEvent) {
        let wasArmed = detector.state == .armed
        switch event.type {
        case .leftMouseDown:
            baselineChangeCount = pasteboard.changeCount
            detector.mouseDown(at: NSEvent.mouseLocation, controlDown: event.modifierFlags.contains(.control))
        case .leftMouseDragged:
            detector.mouseDragged(to: NSEvent.mouseLocation)
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            detector.flagsChanged(control: flags.contains(.control), others: !flags.isDisjoint(with: [.command, .option, .shift]))
        case .leftMouseUp:
            detector.mouseUp()
            onMouseUp()
            return
        default:
            return
        }
        switch (wasArmed, detector.state == .armed) {
        case (false, true): arm()
        case (true, false): onDisarm()
        default: break
        }
    }

    /// Only a drag that put files, or a browser link/image with a known type, on the drag pasteboard
    /// counts; window drags and rubber-band selections leave its change count untouched.
    /// Runs on the main thread, so it looks at types and link text only, never at image bytes.
    private func arm() {
        guard pasteboard.changeCount != baselineChangeCount,
              let inputs = BrowserDragPayload.peekInputs(BrowserDragSnapshot(pasteboard: pasteboard)) else { return }
        onArm(inputs, NSEvent.mouseLocation)
    }
}
