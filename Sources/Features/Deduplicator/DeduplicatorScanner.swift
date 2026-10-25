import CryptoKit
import Darwin
import Foundation

/// Coordinates the 4-tier filtering pipeline to discover duplicate files quickly and safely:
/// 1. Directory Walk & Size/Device Bucket
/// 2. Head+Tail Edge Hashing (4KB head + 4KB tail)
/// 3. Full SHA-256 Hashing
/// 4. Live Byte-for-byte Verification
public final class DeduplicatorScanner: @unchecked Sendable {
    public typealias ProgressCallback = @Sendable (DeduplicatorPhase) -> Void

    private let options: DeduplicatorScanOptions
    private let progress: ProgressCallback?
    private var isCancelled = false

    public init(options: DeduplicatorScanOptions, progress: ProgressCallback? = nil) {
        self.options = options
        self.progress = progress
    }

    public func cancel() {
        isCancelled = true
    }

    private final class FoundState: @unchecked Sendable {
        let lock = NSLock()
        var buckets: [String: [FastDirectoryWalker.FileEntry]] = [:]
        var seenInodes = Set<String>()
        var filesCount = 0
        var totalBytes: Int64 = 0
    }

    public func scan() -> DeduplicatorScanReport {
        let startTime = Date()
        let found = FoundState()
        let walker = FastDirectoryWalker(skipPaths: options.skipPaths)

        // Tier 1: Directory Walk & Size Bucketing
        for root in options.rootPaths {
            guard !isCancelled else { break }
            let realRoot = APFSCloneEngine.realPath(root)
            guard APFSCloneEngine.supportsClones(at: realRoot) else { continue }

            walker.walk(rootPath: realRoot) { file in
                guard !self.isCancelled else { return }
                guard file.size >= self.options.minSizeBytes else { return }
                guard file.links == 1, (file.flags & APFSCloneEngine.untouchableFlags) == 0 else { return }
                guard self.options.category.matches(path: file.path) else { return }

                found.lock.lock()
                defer { found.lock.unlock() }

                found.filesCount += 1
                found.totalBytes += file.size

                if found.filesCount % 2000 == 0 {
                    self.progress?(.scanningDirectories(scannedFiles: found.filesCount))
                }

                let inodeKey = "\(file.device):\(file.inode)"
                guard found.seenInodes.insert(inodeKey).inserted else { return }

                let bucketKey = "\(file.device):\(file.size)"
                found.buckets[bucketKey, default: []].append(file)
            }
        }

        self.progress?(.scanningDirectories(scannedFiles: found.filesCount))
        guard !isCancelled else {
            return DeduplicatorScanReport(filesScanned: found.filesCount, bytesScanned: found.totalBytes)
        }

        // Candidates having 2 or more files with the exact same size on the same volume
        let sizeCandidates = found.buckets.values.filter { $0.count >= 2 }

        // Tier 2: Edge Hashing (Head + Tail 4KB)
        var edgeCandidates: [[FastDirectoryWalker.FileEntry]] = []
        var edgeProcessed = 0
        let totalToEdgeHash = sizeCandidates.reduce(0) { $0 + $1.count }

        for bucket in sizeCandidates {
            guard !isCancelled else { break }
            var subBuckets: [String: [FastDirectoryWalker.FileEntry]] = [:]

            for file in bucket {
                guard !isCancelled else { break }
                edgeProcessed += 1
                if edgeProcessed % 100 == 0 || edgeProcessed == totalToEdgeHash {
                    progress?(.edgeHashing(done: edgeProcessed, total: totalToEdgeHash))
                }

                if let hash = computeEdgeHash(file.path, size: file.size) {
                    subBuckets[hash, default: []].append(file)
                }
            }

            for group in subBuckets.values where group.count >= 2 {
                edgeCandidates.append(group)
            }
        }

        guard !isCancelled else {
            return DeduplicatorScanReport(filesScanned: found.filesCount, bytesScanned: found.totalBytes)
        }

        // Tier 3: Full SHA-256 Hashing
        var fullCandidates: [[FastDirectoryWalker.FileEntry]] = []
        var fullProcessed = 0
        let totalToFullHash = edgeCandidates.reduce(0) { $0 + $1.count }

        for bucket in edgeCandidates {
            guard !isCancelled else { break }
            var subBuckets: [String: [FastDirectoryWalker.FileEntry]] = [:]

            for file in bucket {
                guard !isCancelled else { break }
                fullProcessed += 1
                if fullProcessed % 20 == 0 || fullProcessed == totalToFullHash {
                    progress?(.fullHashing(done: fullProcessed, total: totalToFullHash))
                }

                if let hash = computeFullHash(file.path) {
                    subBuckets[hash, default: []].append(file)
                }
            }

            for group in subBuckets.values where group.count >= 2 {
                fullCandidates.append(group)
            }
        }

        guard !isCancelled else {
            return DeduplicatorScanReport(filesScanned: found.filesCount, bytesScanned: found.totalBytes)
        }

        // Tier 4: Live Byte-for-byte Verification & DuplicateGroup Construction
        var finalGroups: [DuplicateGroup] = []
        var verifyProcessed = 0
        let totalToVerify = fullCandidates.count

        for bucket in fullCandidates {
            guard !isCancelled else { break }
            verifyProcessed += 1
            progress?(.byteVerifying(done: verifyProcessed, total: totalToVerify))

            // Select first as keeper, verify others against keeper
            let keeper = bucket[0]
            var verifiedDuplicates: [String] = []

            for candidate in bucket.dropFirst() {
                if APFSCloneEngine.contentsEqual(keeper.path, candidate.path) {
                    // Check if already sharing blocks
                    let isAlreadyShared: Bool
                    if let kExt = APFSCloneEngine.extentFingerprint(keeper.path, size: keeper.size),
                       let cExt = APFSCloneEngine.extentFingerprint(candidate.path, size: candidate.size),
                       kExt == cExt {
                        isAlreadyShared = true
                    } else {
                        isAlreadyShared = false
                    }

                    if !isAlreadyShared {
                        verifiedDuplicates.append(candidate.path)
                    }
                }
            }

            if !verifiedDuplicates.isEmpty {
                finalGroups.append(DuplicateGroup(
                    size: keeper.size,
                    keeper: keeper.path,
                    duplicates: verifiedDuplicates,
                    isSelected: true
                ))
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        progress?(.done)

        return DeduplicatorScanReport(
            groups: finalGroups.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            filesScanned: found.filesCount,
            bytesScanned: found.totalBytes,
            durationSeconds: duration
        )
    }

    // MARK: - Hashing Helpers

    private func computeEdgeHash(_ path: String, size: Int64) -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var hasher = SHA256()
        let chunkSize = 4096
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        // Read head
        let headRead = read(fd, &buffer, min(chunkSize, Int(size)))
        guard headRead > 0 else { return nil }
        hasher.update(data: Data(buffer[0..<headRead]))

        // Read tail if large enough
        if size > Int64(chunkSize * 2) {
            let tailOffset = off_t(size - Int64(chunkSize))
            if lseek(fd, tailOffset, SEEK_SET) != -1 {
                let tailRead = read(fd, &buffer, chunkSize)
                if tailRead > 0 {
                    hasher.update(data: Data(buffer[0..<tailRead]))
                }
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func computeFullHash(_ path: String) -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var hasher = SHA256()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            let bytesRead = read(fd, &buffer, bufferSize)
            if bytesRead < 0 { return nil }
            if bytesRead == 0 { break }
            hasher.update(data: Data(buffer[0..<bytesRead]))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
