import Compression
import Foundation

/// WOFF 1.0 ↔ sfnt (TTF/OTF). Pure byte work; WOFF tables are zlib streams (RFC 1950).
enum FontWoffCodec {
    struct CodecError: Error { let message: String }

    private static let woffSignature: UInt32 = 0x774F_4646
    private static let maxTableBytes = 128 << 20
    private static let maxTotalBytes = 128 << 20
    private static let supportedFlavors: Set<UInt32> = [0x0001_0000, 0x4F54_544F, 0x7472_7565]

    private struct Table { let tag: UInt32, checksum: UInt32, data: [UInt8] }

    static func sfntExtension(forFlavorOf woff: Data) -> String? {
        let bytes = [UInt8](woff.prefix(8))
        guard bytes.count == 8, be32(bytes, 0) == woffSignature else { return nil }
        return be32(bytes, 4) == 0x4F54_544F ? "otf" : "ttf"
    }

    static func encode(sfnt: Data) throws -> Data {
        let src = [UInt8](sfnt)
        guard src.count >= 12 else { throw CodecError(message: "Tệp quá ngắn") }
        guard src.count <= maxTotalBytes else { throw CodecError(message: "Phông quá lớn") }
        let flavor = be32(src, 0)
        guard supportedFlavors.contains(flavor) else { throw CodecError(message: "Không phải TTF/OTF đơn (không hỗ trợ TTC)") }
        let count = Int(be16(src, 4))
        guard count > 0, src.count >= 12 + count * 16 else { throw CodecError(message: "Bảng thư mục hỏng") }

        var tables: [Table] = []
        var totalSfnt = 12 + count * 16
        for index in 0..<count {
            let entry = 12 + index * 16
            let offset = Int(be32(src, entry + 8)), length = Int(be32(src, entry + 12))
            guard offset <= src.count, length <= src.count - offset else { throw CodecError(message: "Bảng nằm ngoài tệp") }
            tables.append(Table(tag: be32(src, entry), checksum: be32(src, entry + 4), data: Array(src[offset..<offset + length])))
            totalSfnt += padded(length)
        }

        let packed = tables.map { deflated($0.data) ?? $0.data }
        var body: [UInt8] = []
        var directory: [UInt8] = []
        let bodyStart = 44 + count * 20
        for (table, payload) in zip(tables, packed) {
            directory += be32Bytes(table.tag) + be32Bytes(UInt32(bodyStart + body.count)) + be32Bytes(UInt32(payload.count))
                + be32Bytes(UInt32(table.data.count)) + be32Bytes(table.checksum)
            body += payload + [UInt8](repeating: 0, count: padded(payload.count) - payload.count)
        }
        let total = bodyStart + body.count
        var header = be32Bytes(woffSignature) + be32Bytes(flavor) + be32Bytes(UInt32(total))
        header += be16Bytes(UInt16(count)) + be16Bytes(0) + be32Bytes(UInt32(totalSfnt))
        header += be16Bytes(1) + be16Bytes(0) + [UInt8](repeating: 0, count: 20)
        return Data(header + directory + body)
    }

    static func decode(woff: Data) throws -> Data {
        let src = [UInt8](woff)
        guard src.count >= 44, be32(src, 0) == woffSignature else { throw CodecError(message: "Không phải WOFF 1.0") }
        let flavor = be32(src, 4)
        guard supportedFlavors.contains(flavor) else { throw CodecError(message: "Kiểu phông không hỗ trợ") }
        let count = Int(be16(src, 12))
        guard count > 0, src.count >= 44 + count * 20 else { throw CodecError(message: "Bảng thư mục hỏng") }

        let tables = try readTables(src, count: count)

        var power = 0
        while 1 << (power + 1) <= count { power += 1 }
        let searchRange = 16 << power
        var out = be32Bytes(flavor) + be16Bytes(UInt16(count)) + be16Bytes(UInt16(searchRange))
        out += be16Bytes(UInt16(power)) + be16Bytes(UInt16(count * 16 - searchRange))
        var offset = 12 + count * 16
        var body: [UInt8] = []
        for table in tables {
            out += be32Bytes(table.tag) + be32Bytes(table.checksum) + be32Bytes(UInt32(offset)) + be32Bytes(UInt32(table.data.count))
            body += table.data + [UInt8](repeating: 0, count: padded(table.data.count) - table.data.count)
            offset += padded(table.data.count)
        }
        return Data(out + body)
    }

    /// Validates the whole directory (caps, duplicates, overlapping slices, header size) before inflating anything.
    private static func readTables(_ src: [UInt8], count: Int) throws -> [Table] {
        struct Entry { let tag: UInt32, checksum: UInt32, offset: Int, compressed: Int, original: Int }
        let bad = CodecError(message: "Bảng nằm ngoài tệp")
        let dataStart = 44 + count * 20
        var entries: [Entry] = []
        var tags = Set<UInt32>()
        var total = 12 + count * 16
        for index in 0..<count {
            let at = 44 + index * 20
            let entry = Entry(tag: be32(src, at), checksum: be32(src, at + 16), offset: Int(be32(src, at + 4)),
                              compressed: Int(be32(src, at + 8)), original: Int(be32(src, at + 12)))
            guard entry.offset >= dataStart, entry.offset <= src.count, entry.compressed <= src.count - entry.offset,
                  entry.compressed <= entry.original, entry.original <= maxTableBytes, tags.insert(entry.tag).inserted else { throw bad }
            total += padded(entry.original)
            guard total <= maxTotalBytes else { throw bad }
            entries.append(entry)
        }
        guard total <= Int(be32(src, 16)) + 3 * count else { throw CodecError(message: "Kích thước sfnt không khớp tiêu đề") }
        var previousEnd = 0
        for entry in entries.filter({ $0.compressed > 0 }).sorted(by: { $0.offset < $1.offset }) {
            guard entry.offset >= previousEnd else { throw bad }
            previousEnd = entry.offset + entry.compressed
        }
        return try entries.map { entry in
            let slice = Array(src[entry.offset..<entry.offset + entry.compressed])
            guard let data = entry.compressed == entry.original ? slice : inflated(slice, originalLength: entry.original) else {
                throw CodecError(message: "Giải nén bảng thất bại")
            }
            return Table(tag: entry.tag, checksum: entry.checksum, data: data)
        }
    }

    // MARK: zlib

    /// nil when compression would not shrink the table (WOFF then stores it raw).
    private static func deflated(_ data: [UInt8]) -> [UInt8]? {
        guard data.count > 7 else { return nil }
        var dst = [UInt8](repeating: 0, count: data.count - 7)
        let written = compression_encode_buffer(&dst, dst.count, data, data.count, nil, COMPRESSION_ZLIB)
        guard written > 0 else { return nil }
        return [0x78, 0x9C] + dst[0..<written] + be32Bytes(adler32(data))
    }

    private static func inflated(_ stream: [UInt8], originalLength: Int) -> [UInt8]? {
        guard stream.count >= 6, stream[0] & 0x0F == 8, stream[1] & 0x20 == 0,
              (Int(stream[0]) << 8 | Int(stream[1])) % 31 == 0 else { return nil }
        let raw = Array(stream[2..<stream.count - 4])
        var dst = [UInt8](repeating: 0, count: originalLength)
        let written = compression_decode_buffer(&dst, originalLength, raw, raw.count, nil, COMPRESSION_ZLIB)
        guard written == originalLength, adler32(dst) == be32(stream, stream.count - 4) else { return nil }
        return dst
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    // MARK: big-endian helpers

    private static func padded(_ length: Int) -> Int { (length + 3) & ~3 }
    private static func be16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i + 1]) }
    private static func be32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(be16(b, i)) << 16 | UInt32(be16(b, i + 2)) }
    private static func be16Bytes(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    private static func be32Bytes(_ v: UInt32) -> [UInt8] { be16Bytes(UInt16(v >> 16)) + be16Bytes(UInt16(v & 0xFFFF)) }
}
