import Cocoa

/// Single session event tap for Finder Cut/Paste and Vietnamese IME.
/// Owning one tap avoids two head-insert taps racing on the same key events.
///
/// The tap runs on its own thread with its own run loop. On the main run loop
/// every busy UI moment delayed keystrokes, and a long stall made macOS disable
/// the tap, so keys typed meanwhile bypassed the IME and desynced its buffer.
public final class GlobalEventTap {
    public static let shared = GlobalEventTap()

    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var tapRunLoop: CFRunLoop?

    private init() {}

    public var isRunning: Bool { lock.withLock { eventTap != nil } }

    @discardableResult
    public func start() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        lock.lock()
        defer { lock.unlock() }
        guard eventTap == nil else { return true }

        IMEConfigurationStore.shared.start()

        // Only hook keyboard events in the active CGEventTap.
        // Mouse events are monitored passively via NSEvent to prevent system-wide mouse freezes.
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let tap = Unmanaged<GlobalEventTap>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                TypingLatencyMonitor.shared.recordTapDisabled(type)
                tap.reenableTap()
                // Keys typed while disabled reached the app unseen.
                InputHookManager.shared.handleTapReenabled()
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown, !InputHookManager.isSimulatedEvent(event) else {
                return tap.route(type: type, event: event, proxy: proxy)
            }
            return TypingLatencyMonitor.shared.measureKeyDown(event) {
                tap.route(type: type, event: event, proxy: proxy)
            }
        }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            NSLog("Xmac: Không thể tạo CGEvent tap. Cần cấp quyền Accessibility.")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        final class RunLoopBox { var runLoop: CFRunLoop? }
        let box = RunLoopBox()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            box.runLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "vn.xmac.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + .milliseconds(500))

        eventTap = tap
        tapRunLoop = box.runLoop
        return true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let tapRunLoop {
            CFRunLoopStop(tapRunLoop)
        }
        eventTap = nil
        tapRunLoop = nil
    }

    /// Runs on the tap thread.
    private func route(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        // Finder shortcuts touch AppleScript, AX and @Published state: run them
        // on main with a strict timeout to prevent deadlocks from freezing the system.
        if IMEConfigurationStore.shared.snapshot.handlesFinderShortcuts,
           EventTapManager.isShortcutCandidate(type: type, event: event) {
            var consumed = false
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                consumed = EventTapManager.handleIfNeeded(type: type, event: event)
                semaphore.signal()
            }
            let waitResult = semaphore.wait(timeout: .now() + .milliseconds(25))
            if waitResult == .success && consumed {
                return nil
            }
        }
        return InputHookManager.shared.handleEvent(type: type, event: event, proxy: proxy)
    }

    private func reenableTap() {
        lock.withLock {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }
}
