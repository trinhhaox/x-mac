import Testing
@testable import Xmac

@Suite struct TypingLatencyStatsTests {
    // Apple Silicon timebase: 1 tick = 125/3 ns.
    private let numer: UInt32 = 125
    private let denom: UInt32 = 3

    @Test func eventAgeAcceptsMachTickTimestamps() {
        let now: UInt64 = 516_000_000_000
        let tenMsInTicks: UInt64 = 240_000
        let age = TypingLatencyStats.eventAgeNs(
            eventTimestamp: now - tenMsInTicks, nowTicks: now, timebaseNumer: numer, timebaseDenom: denom
        )
        #expect(age == 10_000_000)
    }

    @Test func eventAgeAcceptsNanosecondTimestamps() {
        let now: UInt64 = 516_000_000_000
        let nowNs = now * 125 / 3
        let age = TypingLatencyStats.eventAgeNs(
            eventTimestamp: nowNs - 7_000_000, nowTicks: now, timebaseNumer: numer, timebaseDenom: denom
        )
        #expect(age == 7_000_000)
    }

    @Test func eventAgeIgnoresMissingOrFutureTimestamps() {
        #expect(TypingLatencyStats.eventAgeNs(eventTimestamp: 0, nowTicks: 100, timebaseNumer: 1, timebaseDenom: 1) == nil)
        #expect(TypingLatencyStats.eventAgeNs(eventTimestamp: 500, nowTicks: 100, timebaseNumer: 1, timebaseDenom: 1) == nil)
    }

    @Test func percentilesUseNearestRank() {
        let sorted: [UInt64] = Array(1...100)
        #expect(TypingLatencyStats.percentile(sorted, 0.50) == 50)
        #expect(TypingLatencyStats.percentile(sorted, 0.95) == 95)
        #expect(TypingLatencyStats.percentile([], 0.95) == 0)
        #expect(TypingLatencyStats.percentile([42], 0.50) == 42)
    }

    @Test func summaryReportsMillisecondsAndCounters() {
        var stats = TypingLatencyStats()
        stats.recordKey(queueDelayNs: 2_000_000, handlerNs: 100_000)
        stats.recordKey(queueDelayNs: nil, handlerNs: 300_000)
        stats.recordKey(queueDelayNs: 80_000_000, handlerNs: 20_000_000)
        stats.recordSpellLookup(durationNs: 12_345_678)
        stats.tapTimeouts = 1

        let summary = stats.summary()
        #expect(summary.keyCount == 3)
        #expect(summary.queueMaxMs == 80)
        #expect(summary.handlerMaxMs == 20)
        #expect(summary.handlerP50Ms == 0.3)
        #expect(summary.spellLookups == 1)
        #expect(summary.spellMaxMs == 12.35)
        #expect(summary.tapTimeouts == 1)
    }
}
