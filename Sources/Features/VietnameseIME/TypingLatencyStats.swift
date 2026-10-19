import Foundation

/// Rolling window of typing-latency samples. Pure value type so the
/// percentile and clock math can be tested without a live event tap.
struct TypingLatencyStats {
    struct Summary: Equatable {
        let keyCount: Int
        let queueP50Ms: Double
        let queueP95Ms: Double
        let queueMaxMs: Double
        let handlerP50Ms: Double
        let handlerP95Ms: Double
        let handlerMaxMs: Double
        let replacements: Int
        let syntheticEvents: Int
        let spellLookups: Int
        let spellMaxMs: Double
        let spellTimeouts: Int
        let tapTimeouts: Int
        let tapUserDisables: Int
    }

    private(set) var queueDelaysNs: [UInt64] = []
    private(set) var handlerDurationsNs: [UInt64] = []
    var replacements = 0
    var syntheticEvents = 0
    var spellLookups = 0
    var spellMaxNs: UInt64 = 0
    var spellTimeouts = 0
    var tapTimeouts = 0
    var tapUserDisables = 0

    var keyCount: Int { handlerDurationsNs.count }

    mutating func recordKey(queueDelayNs: UInt64?, handlerNs: UInt64) {
        handlerDurationsNs.append(handlerNs)
        if let queueDelayNs { queueDelaysNs.append(queueDelayNs) }
    }

    mutating func recordSpellLookup(durationNs: UInt64, timedOut: Bool = false) {
        spellLookups += 1
        spellMaxNs = max(spellMaxNs, durationNs)
        if timedOut { spellTimeouts += 1 }
    }

    func summary() -> Summary {
        let queue = queueDelaysNs.sorted()
        let handler = handlerDurationsNs.sorted()
        return Summary(
            keyCount: keyCount,
            queueP50Ms: Self.ms(Self.percentile(queue, 0.50)),
            queueP95Ms: Self.ms(Self.percentile(queue, 0.95)),
            queueMaxMs: Self.ms(queue.last ?? 0),
            handlerP50Ms: Self.ms(Self.percentile(handler, 0.50)),
            handlerP95Ms: Self.ms(Self.percentile(handler, 0.95)),
            handlerMaxMs: Self.ms(handler.last ?? 0),
            replacements: replacements,
            syntheticEvents: syntheticEvents,
            spellLookups: spellLookups,
            spellMaxMs: Self.ms(spellMaxNs),
            spellTimeouts: spellTimeouts,
            tapTimeouts: tapTimeouts,
            tapUserDisables: tapUserDisables
        )
    }

    /// Nearest-rank percentile over an already sorted array.
    static func percentile(_ sorted: [UInt64], _ fraction: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    static func ms(_ nanoseconds: UInt64) -> Double {
        (Double(nanoseconds) / 1_000_000 * 100).rounded() / 100
    }

    /// How long a hardware event waited before reaching the tap callback.
    ///
    /// CGEvent timestamps are documented as nanoseconds, but on Apple Silicon
    /// they are raw mach ticks. The two scales differ by ~24x, so only one
    /// interpretation yields a plausible age; that one is used. Returns nil
    /// for events without a timestamp (synthetic events from other apps).
    static func eventAgeNs(
        eventTimestamp: UInt64,
        nowTicks: UInt64,
        timebaseNumer: UInt32,
        timebaseDenom: UInt32
    ) -> UInt64? {
        guard eventTimestamp > 0, timebaseDenom > 0 else { return nil }
        let plausibleLimitNs: UInt64 = 60_000_000_000
        let toNs = { (ticks: UInt64) in ticks * UInt64(timebaseNumer) / UInt64(timebaseDenom) }

        let candidates = [
            eventTimestamp <= nowTicks ? toNs(nowTicks - eventTimestamp) : nil,
            eventTimestamp <= toNs(nowTicks) ? toNs(nowTicks) - eventTimestamp : nil
        ]
        return candidates.compactMap { $0 }.filter { $0 < plausibleLimitNs }.min()
    }
}
