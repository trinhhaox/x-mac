import Foundation
import Testing
@testable import Xmac

@Suite struct FontWoffCodecHardeningTests {
    private func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }

    /// Raw-stored WOFF: each entry is (tag, offset into `body`, length). `total` is the claimed totalSfntSize.
    private func woff(entries: [(tag: Int, offset: Int, length: Int)], body: [UInt8], total: Int) -> Data {
        let dataStart = 44 + entries.count * 20
        var out = be32(0x774F_4646) + be32(0x0001_0000) + be32(dataStart + body.count)
        out += [UInt8(entries.count >> 8), UInt8(entries.count & 255), 0, 0] + be32(total) + [UInt8](repeating: 0, count: 24)
        for e in entries { out += be32(e.tag) + be32(dataStart + e.offset) + be32(e.length) + be32(e.length) + be32(0) }
        return Data(out + body)
    }

    private func honestTotal(_ count: Int, perTable: Int) -> Int { 12 + 16 * count + count * ((perTable + 3) & ~3) }

    @Test func wellFormedRawTableDecodes() throws {
        let data = woff(entries: [(0x6865_6164, 0, 4)], body: [1, 2, 3, 4], total: 32)
        #expect(try FontWoffCodec.decode(woff: data).count == 32)
    }

    @Test func manyEntriesSharingOneSliceAreRejected() {
        let entries = (0..<50).map { (tag: 0x6100_0000 + $0, offset: 0, length: 100) }
        let data = woff(entries: entries, body: [UInt8](repeating: 7, count: 100), total: honestTotal(50, perTable: 100))
        #expect(throws: FontWoffCodec.CodecError.self) { try FontWoffCodec.decode(woff: data) }
    }

    @Test func duplicateTagsAreRejected() {
        let data = woff(entries: [(0x6865_6164, 0, 4), (0x6865_6164, 4, 4)], body: [UInt8](repeating: 1, count: 8), total: 12 + 32 + 8)
        #expect(throws: FontWoffCodec.CodecError.self) { try FontWoffCodec.decode(woff: data) }
    }

    @Test func headerSizeSmallerThanTablesIsRejected() {
        let data = woff(entries: [(0x6865_6164, 0, 400)], body: [UInt8](repeating: 1, count: 400), total: 20)
        #expect(throws: FontWoffCodec.CodecError.self) { try FontWoffCodec.decode(woff: data) }
    }

    @Test func zeroLengthTableOutsideFileIsRejected() {
        var data = [UInt8](woff(entries: [(0x6865_6164, 0, 0)], body: [], total: 28))
        data.replaceSubrange(48..<52, with: be32(1_000_000))
        #expect(throws: FontWoffCodec.CodecError.self) { try FontWoffCodec.decode(woff: Data(data)) }
    }

    @Test func storedRawWheneverCompressionDoesNotShrink() throws {
        for length in 1...40 {
            var seed: UInt32 = UInt32(length) &* 2_654_435_761
            let table = (0..<length).map { _ -> UInt8 in seed = seed &* 1_664_525 &+ 1_013_904_223; return UInt8(seed >> 24) }
            let sfnt = Data(be32(0x0001_0000) + [0, 1, 0, 16, 0, 0, 0, 0] + be32(0x6865_6164) + be32(0) + be32(28) + be32(length) + table)
            let packed = [UInt8](try FontWoffCodec.encode(sfnt: sfnt))
            let compressed = packed[52..<56].reduce(0) { $0 << 8 | Int($1) }
            let original = packed[56..<60].reduce(0) { $0 << 8 | Int($1) }
            #expect(compressed == original || compressed < original)
            if compressed != original { #expect(compressed < original) }
            let restored = [UInt8](try FontWoffCodec.decode(woff: Data(packed)))
            #expect(Array(restored[28..<28 + length]) == table)
        }
    }
}
