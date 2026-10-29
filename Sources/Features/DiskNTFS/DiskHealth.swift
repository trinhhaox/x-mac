import Foundation

/// Hardware facts about the device behind a volume. SMART is usually "Not Supported" over USB
/// because most USB bridges do not pass SMART commands through.
public struct DiskHealthInfo: Equatable {
    public enum SMART: Equatable {
        case verified
        case failing
        case unsupported
    }

    public let model: String
    public let connection: String
    public let isSolidState: Bool?
    public let smart: SMART

    static func from(volumeInfo: [String: Any], wholeDiskInfo: [String: Any]?) -> DiskHealthInfo {
        let whole = wholeDiskInfo ?? volumeInfo
        let model = [whole["MediaName"], volumeInfo["MediaName"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? L10n.text("Không rõ")
        let smartRaw = (whole["SMARTStatus"] as? String) ?? (volumeInfo["SMARTStatus"] as? String) ?? ""
        let smart: SMART
        switch smartRaw.lowercased() {
        case "verified": smart = .verified
        case "failing": smart = .failing
        default: smart = .unsupported
        }
        return DiskHealthInfo(
            model: model,
            connection: (whole["BusProtocol"] as? String) ?? (volumeInfo["BusProtocol"] as? String) ?? L10n.text("Không rõ"),
            isSolidState: (whole["SolidState"] as? Bool) ?? (volumeInfo["SolidState"] as? Bool),
            smart: smart
        )
    }

    static func load(for volume: DiskVolume) async -> DiskHealthInfo? {
        guard let info = await DiskUtil.infoPlist(volume.bsdName) else { return nil }
        let whole = (info["ParentWholeDisk"] as? String).flatMap { BSDDeviceName.isValid($0) ? $0 : nil }
        var wholeInfo: [String: Any]?
        if let whole { wholeInfo = await DiskUtil.infoPlist(whole) }
        return from(volumeInfo: info, wholeDiskInfo: wholeInfo)
    }
}

/// Sequential write-then-read throughput with the page cache bypassed, so the numbers reflect the drive.
enum DiskSpeedTest {
    struct Result: Equatable {
        let writeMBps: Double
        let readMBps: Double
    }

    enum Failure: Error, Equatable {
        case notEnoughSpace
        case io(String)
    }

    static let defaultSizeMB = 256
    private static let chunkBytes = 8 * 1024 * 1024
    static let filePrefix = ".xmac-speedtest-"

    /// A test interrupted by unplugging or quitting leaves its 256 MB file behind; clear it next time.
    static func removeLeftovers(in mountPoint: String) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint)) ?? []
        for name in names where name.hasPrefix(filePrefix) {
            try? FileManager.default.removeItem(atPath: (mountPoint as NSString).appendingPathComponent(name))
        }
    }

    static func run(at mountPoint: String, sizeMB: Int = defaultSizeMB) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            try measure(at: mountPoint, sizeMB: sizeMB)
        }.value
    }

    static func megabytesPerSecond(bytes: Int, seconds: TimeInterval) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) / 1_048_576 / seconds
    }

    private static func measure(at mountPoint: String, sizeMB: Int) throws -> Result {
        let totalBytes = sizeMB * 1_048_576
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: mountPoint)
        let free = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free > Int64(totalBytes) * 2 else { throw Failure.notEnoughSpace }

        removeLeftovers(in: mountPoint)
        let path = (mountPoint as NSString).appendingPathComponent("\(filePrefix)\(UUID().uuidString)")
        defer { unlink(path) }
        var buffer = [UInt8](repeating: 0, count: chunkBytes)
        for index in stride(from: 0, to: chunkBytes, by: 4096) { buffer[index] = UInt8.random(in: 0...255) }

        let writeFD = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        guard writeFD >= 0 else { throw Failure.io(String(cString: strerror(errno))) }
        _ = fcntl(writeFD, F_NOCACHE, 1)
        let writeStart = Date()
        var written = 0
        while written < totalBytes {
            let count = buffer.withUnsafeBytes { Darwin.write(writeFD, $0.baseAddress, min(chunkBytes, totalBytes - written)) }
            guard count > 0 else { close(writeFD); throw Failure.io(String(cString: strerror(errno))) }
            written += count
        }
        _ = fcntl(writeFD, F_FULLFSYNC)
        let writeSeconds = Date().timeIntervalSince(writeStart)
        close(writeFD)

        let readFD = open(path, O_RDONLY)
        guard readFD >= 0 else { throw Failure.io(String(cString: strerror(errno))) }
        _ = fcntl(readFD, F_NOCACHE, 1)
        let readStart = Date()
        var read = 0
        while read < totalBytes {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(readFD, $0.baseAddress, chunkBytes) }
            if count == 0 { break }
            guard count > 0 else { close(readFD); throw Failure.io(String(cString: strerror(errno))) }
            read += count
        }
        let readSeconds = Date().timeIntervalSince(readStart)
        close(readFD)

        return Result(
            writeMBps: megabytesPerSecond(bytes: written, seconds: writeSeconds),
            readMBps: megabytesPerSecond(bytes: read, seconds: readSeconds)
        )
    }
}
