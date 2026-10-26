import AppKit

/// Passive monitors (global and local, never consuming) alive only while the donut is visible: during a
/// drag the panel has no key focus, so Esc, Tab and the wheel are observed from outside.
@MainActor
final class DonutEventMonitors {
    private static let escapeKeyCode: UInt16 = 53
    private static let tabKeyCode: UInt16 = 48

    private let onEscape: () -> Void
    private let onFlip: () -> Void
    private var monitors: [Any] = []
    private var wheel = WheelTurnDebouncer()

    init(onEscape: @escaping () -> Void, onFlip: @escaping () -> Void) {
        self.onEscape = onEscape
        self.onFlip = onFlip
    }

    func start() {
        stop()
        wheel = WheelTurnDebouncer()
        let mask: NSEvent.EventTypeMask = [.keyDown, .scrollWheel]
        // Global monitors see events bound for other apps; the local one covers our own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let input = Input(event)
            MainActor.assumeIsolated { self?.handle(input) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let input = Input(event)
            MainActor.assumeIsolated { self?.handle(input) }
            return event
        }) { monitors.append(local) }
    }

    /// The event fields the donut needs, copied out so the handler is free of non-Sendable `NSEvent`.
    private struct Input {
        let isKey: Bool
        let keyCode: UInt16
        let isRepeat: Bool
        let moved: Bool
        let time: TimeInterval

        init(_ event: NSEvent) {
            isKey = event.type == .keyDown
            keyCode = isKey ? event.keyCode : 0
            isRepeat = isKey && event.isARepeat
            moved = !isKey && (event.scrollingDeltaY != 0 || event.scrollingDeltaX != 0)
            time = event.timestamp
        }
    }

    private func handle(_ input: Input) {
        if input.isKey {
            if input.keyCode == Self.escapeKeyCode {
                onEscape()
            } else if input.keyCode == Self.tabKeyCode, !input.isRepeat {
                onFlip()
            }
        } else if input.moved {
            if wheel.isNewTurn(at: input.time) { onFlip() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
