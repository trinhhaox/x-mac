import Cocoa
import os

/// Measures how fast the IME event tap answers keystrokes, so typing lag can
/// be attributed to queueing (busy tap thread), handler work, spell lookups
/// or the tap being disabled by macOS. Logs numbers and bundle IDs only,
/// never typed text.
///
/// Read with: `log stream --level info --predicate 'subsystem == "vn.xmac.app" AND category == "IME"'`
/// or `Scripts/ime-latency.sh`. Intervals also show up in Instruments
/// (os_signpost, subsystem vn.xmac.app).
///
/// All methods are called from the event tap thread only.
final class TypingLatencyMonitor {
    static let shared = TypingLatencyMonitor()

    private static let summaryEveryKeys = 200
    private static let summaryEverySeconds: TimeInterval = 60
    private static let slowQueueNs: UInt64 = 50_000_000
    private static let slowHandlerNs: UInt64 = 16_000_000

    private let logger = Logger(subsystem: "vn.xmac.app", category: "IME")
    let signposter = OSSignposter(subsystem: "vn.xmac.app", category: "IME")
    private let timebase: mach_timebase_info_data_t
    private var stats = TypingLatencyStats()
    private var windowStart = Date()

    private init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = info
    }

    func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    /// Wraps the keyDown handler: measures queue delay and handler time.
    func measureKeyDown<T>(_ event: CGEvent, _ handler: () -> T) -> T {
        let start = mach_absolute_time()
        let queueDelay = TypingLatencyStats.eventAgeNs(
            eventTimestamp: event.timestamp,
            nowTicks: start,
            timebaseNumer: timebase.numer,
            timebaseDenom: timebase.denom
        )
        let state = signposter.beginInterval("keyDown")
        let result = handler()
        signposter.endInterval("keyDown", state)
        let handlerNs = nanoseconds(fromTicks: mach_absolute_time() - start)

        stats.recordKey(queueDelayNs: queueDelay, handlerNs: handlerNs)
        if (queueDelay ?? 0) >= Self.slowQueueNs || handlerNs >= Self.slowHandlerNs {
            logSlowKey(queueDelayNs: queueDelay ?? 0, handlerNs: handlerNs)
        }
        flushIfDue()
        return result
    }

    func recordReplacement(syntheticEvents: Int) {
        stats.replacements += 1
        stats.syntheticEvents += syntheticEvents
    }

    /// Times how long the tap thread waited for a main-thread spell lookup.
    func measureSpellWait(_ wait: () -> DispatchTimeoutResult) -> DispatchTimeoutResult {
        let start = mach_absolute_time()
        let state = signposter.beginInterval("spellCheck")
        let result = wait()
        signposter.endInterval("spellCheck", state)
        stats.recordSpellLookup(
            durationNs: nanoseconds(fromTicks: mach_absolute_time() - start),
            timedOut: result == .timedOut
        )
        return result
    }

    func recordTapDisabled(_ type: CGEventType) {
        if type == .tapDisabledByTimeout {
            stats.tapTimeouts += 1
        } else {
            stats.tapUserDisables += 1
        }
        signposter.emitEvent("tapDisabled")
        logger.error("tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public); keys typed meanwhile bypassed the IME")
    }

    private func logSlowKey(queueDelayNs: UInt64, handlerNs: UInt64) {
        let app = IMEConfigurationStore.shared.snapshot.bundleIdentifier ?? "?"
        logger.notice("slow key app=\(app, privacy: .public) queue=\(TypingLatencyStats.ms(queueDelayNs), privacy: .public)ms handler=\(TypingLatencyStats.ms(handlerNs), privacy: .public)ms")
    }

    private func flushIfDue() {
        guard stats.keyCount >= Self.summaryEveryKeys
            || Date().timeIntervalSince(windowStart) >= Self.summaryEverySeconds else { return }
        let s = stats.summary()
        logger.notice("summary keys=\(s.keyCount, privacy: .public) queue p50/p95/max=\(s.queueP50Ms, privacy: .public)/\(s.queueP95Ms, privacy: .public)/\(s.queueMaxMs, privacy: .public)ms handler p50/p95/max=\(s.handlerP50Ms, privacy: .public)/\(s.handlerP95Ms, privacy: .public)/\(s.handlerMaxMs, privacy: .public)ms replacements=\(s.replacements, privacy: .public) synthetic=\(s.syntheticEvents, privacy: .public) spell=\(s.spellLookups, privacy: .public) spellMax=\(s.spellMaxMs, privacy: .public)ms spellTimeouts=\(s.spellTimeouts, privacy: .public) tapTimeouts=\(s.tapTimeouts, privacy: .public) tapUserDisables=\(s.tapUserDisables, privacy: .public)")
        stats = TypingLatencyStats()
        windowStart = Date()
    }
}
