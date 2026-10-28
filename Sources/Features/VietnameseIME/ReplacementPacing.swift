import Darwin

/// How long a physical key waits after a synthetic replacement in a browser or
/// Electron app. Times are nanoseconds on the uptime clock, the same clock as
/// `mach_absolute_time` but already converted: raw mach ticks are 41.67 ns on
/// Apple Silicon, so treating them as nanoseconds made the old 0.6 ms window 25 ms.
enum ReplacementPacing {
    /// Lets WindowServer and the app's message loop apply the synthetic keys.
    static let nextKeyGap: UInt64 = 600_000 // 0.6 ms
    /// Return submits in chat apps (Zalo, Messenger) from editor state that
    /// React updates after the input event, about one frame later.
    static let returnGap: UInt64 = 8_000_000 // 8 ms

    static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    static func remainingWait(elapsed: UInt64, beforeReturn: Bool) -> UInt64 {
        let gap = beforeReturn ? returnGap : nextKeyGap
        return elapsed < gap ? gap - elapsed : 0
    }

    static func sleep(nanoseconds: UInt64) {
        guard nanoseconds > 0 else { return }
        usleep(useconds_t(nanoseconds / 1_000))
    }
}
