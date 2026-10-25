import Darwin
import Foundation

/// Low-level APFS Copy-on-Write Clone Engine.
/// Provides safe deduplication by replacing identical duplicate files with APFS clones
/// of a single keeper file, keeping permissions, metadata, and timestamps intact.
public enum APFSCloneEngine {

    /// Flags marking files that must never be altered or deduplicated.
    public static let untouchableFlags: UInt32 =
        0x4000_0000 /* SF_DATALESS */ | UInt32(UF_COMPRESSED) | UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        | UInt32(UF_APPEND) | UInt32(SF_APPEND) | UInt32(SF_RESTRICTED) | UInt32(UF_TRACKED)

    public struct FileStat: Equatable {
        public let device: dev_t
        public let inode: ino_t
        public let size: Int64
        public let links: nlink_t
        public let flags: UInt32
        public let uid: uid_t
        public let mtime: timespec
        public let ctime: timespec

        public static func == (a: FileStat, b: FileStat) -> Bool {
            a.device == b.device && a.inode == b.inode && a.size == b.size && a.links == b.links
                && a.flags == b.flags && a.uid == b.uid
                && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
                && a.ctime.tv_sec == b.ctime.tv_sec && a.ctime.tv_nsec == b.ctime.tv_nsec
        }
    }

    public struct Metadata: Equatable {
        public let mode: mode_t
        public let uid: uid_t
        public let gid: gid_t
        public let flags: UInt32
        public let mtime: timespec
        public let btime: timespec

        public static func == (a: Metadata, b: Metadata) -> Bool {
            (a.mode & 0o7777) == (b.mode & 0o7777)
                && a.uid == b.uid
                && a.flags == b.flags
                && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
                && a.btime.tv_sec == b.btime.tv_sec && a.btime.tv_nsec == b.btime.tv_nsec
        }
    }

    public enum CloneOutcome: String, Sendable, Codable {
        case cloned
        case alreadyShared
        case skipped
        case failed
        case changed
    }

    public struct CloneResult: Sendable, Codable {
        public let path: String
        public let keeper: String
        public let size: Int64
        public let outcome: CloneOutcome
        public let reason: String?

        public init(path: String, keeper: String, size: Int64, outcome: CloneOutcome, reason: String? = nil) {
            self.path = path
            self.keeper = keeper
            self.size = size
            self.outcome = outcome
            self.reason = reason
        }

        public var freedBytes: Int64 {
            outcome == .cloned ? size : 0
        }
    }

    // MARK: - Volume Capabilities

    /// Checks whether the volume hosting `path` supports APFS CoW clones.
    public static func supportsClones(at path: String) -> Bool {
        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)

        struct Reply {
            var length: UInt32 = 0
            var caps = vol_capabilities_attr_t()
        }
        var reply = Reply()
        let mount = mountPoint(of: path)
        guard getattrlist(mount, &attrs, &reply, MemoryLayout<Reply>.size, 0) == 0 else { return false }

        let bit = UInt32(VOL_CAP_INT_CLONE)
        let index = Int(VOL_CAPABILITIES_INTERFACES)
        let valid = withUnsafeBytes(of: reply.caps.valid) { $0.load(fromByteOffset: index * 4, as: UInt32.self) }
        let caps = withUnsafeBytes(of: reply.caps.capabilities) { $0.load(fromByteOffset: index * 4, as: UInt32.self) }
        return (valid & bit) != 0 && (caps & bit) != 0
    }

    public static func mountPoint(of path: String) -> String {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return "/" }
        return withUnsafeBytes(of: fs.f_mntonname) {
            String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
        }
    }

    public static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return (path as NSString).standardizingPath }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Extent Checking (Block Sharing on SSD)

    /// Fingerprint of where a file's physical data blocks live on disk.
    /// Two files with the same extent fingerprint already share storage.
    public static func extentFingerprint(_ path: String, size: Int64) -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        func physicalOffset(at byteOffset: Int64) -> Int64? {
            var l2p = log2phys(l2p_flags: 0, l2p_contigbytes: 1, l2p_devoffset: byteOffset)
            guard fcntl(fd, F_LOG2PHYS_EXT, &l2p) != -1 else { return nil }
            return l2p.l2p_devoffset
        }

        guard let first = physicalOffset(at: 0),
              let last = physicalOffset(at: max(0, (size - 1) / 4096 * 4096)) else {
            return nil
        }
        return "\(first):\(last)"
    }

    public static func lstat(_ path: String) -> FileStat? {
        var st = Darwin.stat()
        guard Darwin.lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileStat(device: st.st_dev, inode: st.st_ino, size: st.st_size, links: st.st_nlink,
                        flags: st.st_flags, uid: st.st_uid, mtime: st.st_mtimespec, ctime: st.st_ctimespec)
    }

    public static func readMetadata(_ path: String) -> Metadata? {
        var st = Darwin.stat()
        guard Darwin.lstat(path, &st) == 0 else { return nil }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_CRTIME)

        var buf = [UInt8](repeating: 0, count: 64)
        guard getattrlist(path, &attrs, &buf, buf.count, UInt32(FSOPT_NOFOLLOW)) == 0 else {
            return nil
        }

        let btime = buf.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: 4, as: timespec.self)
        }

        return Metadata(
            mode: st.st_mode,
            uid: st.st_uid,
            gid: st.st_gid,
            flags: st.st_flags,
            mtime: st.st_mtimespec,
            btime: btime
        )
    }

    public static func copyMetadata(from source: String, to target: String) -> Bool {
        guard let meta = readMetadata(source) else { return false }

        // 1. Copy security ACLs and extended attributes (xattrs)
        _ = copyfile(source, target, nil, copyfile_flags_t(COPYFILE_SECURITY | COPYFILE_XATTR | COPYFILE_NOFOLLOW))

        // 2. Preserve POSIX permissions and flags
        _ = chmod(target, meta.mode)
        _ = chflags(target, meta.flags)

        // 3. Accurately preserve timestamps (crtime/btime: 0x200 and mtime: 0x400)
        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_CRTIME) | attrgroup_t(ATTR_CMN_MODTIME)

        struct TimeData {
            var btime: timespec // CRTIME (0x200)
            var mtime: timespec // MODTIME (0x400)
        }

        var times = TimeData(btime: meta.btime, mtime: meta.mtime)
        return setattrlist(target, &attrs, &times, MemoryLayout<TimeData>.size, UInt32(FSOPT_NOFOLLOW)) == 0
    }

    /// Live byte-for-byte comparison of two files.
    public static func contentsEqual(_ pathA: String, _ pathB: String) -> Bool {
        let fdA = open(pathA, O_RDONLY | O_NOFOLLOW)
        guard fdA >= 0 else { return false }
        defer { close(fdA) }

        let fdB = open(pathB, O_RDONLY | O_NOFOLLOW)
        guard fdB >= 0 else { return false }
        defer { close(fdB) }

        let bufferSize = 128 * 1024
        let bufA = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        let bufB = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer {
            bufA.deallocate()
            bufB.deallocate()
        }

        while true {
            let readA = read(fdA, bufA, bufferSize)
            let readB = read(fdB, bufB, bufferSize)
            if readA != readB { return false }
            if readA <= 0 { return readA == 0 } // Both EOF
            if memcmp(bufA, bufB, readA) != 0 { return false }
        }
    }

    // MARK: - CoW Clone Operation

    /// Safely replaces `path` with an APFS clone of `keeper`.
    /// Preserves file attributes, permissions, timestamps, and checks byte equality.
    public static func clone(path: String, into keeper: String, expectedSize: Int64,
                             requireQuietPeriod: Bool = true, quietSeconds: Double = 300) -> CloneResult {
        guard let targetStat = lstat(path), let keeperStat = lstat(keeper) else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .skipped, reason: "Tệp không còn tồn tại")
        }

        guard targetStat.device == keeperStat.device else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .skipped, reason: "Khác phân vùng ổ đĩa")
        }

        guard targetStat.links == 1, (targetStat.flags & untouchableFlags) == 0, targetStat.uid == getuid() else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .skipped, reason: "Tệp được bảo vệ hệ thống")
        }

        guard targetStat.size == expectedSize, keeperStat.size == expectedSize else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .changed, reason: "Kích thước tệp đã thay đổi")
        }

        // Check already shared extents
        if let targetExt = extentFingerprint(path, size: expectedSize),
           let keeperExt = extentFingerprint(keeper, size: expectedSize),
           targetExt == keeperExt {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .alreadyShared, reason: "Đã chia sẻ dữ liệu CoW sẵn")
        }

        // Quiet period check
        if requireQuietPeriod {
            let settled = Date().timeIntervalSince1970 - quietSeconds
            let lastMod = Double(max(targetStat.mtime.tv_sec, targetStat.ctime.tv_sec))
            if lastMod >= settled {
                return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .skipped, reason: "Tệp vừa được sửa đổi trong 5 phút qua")
            }
        }

        guard let originalMeta = readMetadata(path) else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .failed, reason: "Không đọc được metadata")
        }

        let dir = (path as NSString).deletingLastPathComponent
        let tempClone = "\(dir)/.xmac-clone-\(UUID().uuidString.prefix(8))"

        // Step 1: Create clone next to the target file
        guard clonefile(keeper, tempClone, UInt32(CLONE_NOFOLLOW | CLONE_NOOWNERCOPY)) == 0 else {
            let err = String(cString: strerror(errno))
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .failed, reason: "Lỗi clonefile: \(err)")
        }

        var success = false
        defer {
            if !success {
                _ = unlink(tempClone)
            }
        }

        // Step 2: Copy metadata from target file to temp clone
        guard copyMetadata(from: path, to: tempClone) else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .failed, reason: "Không sao chép được metadata")
        }

        guard let copiedMeta = readMetadata(tempClone), copiedMeta == originalMeta else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .skipped, reason: "Metadata không đồng nhất")
        }

        // Step 3: Verify byte-for-byte equality before replacement
        guard contentsEqual(tempClone, path) else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .changed, reason: "Nội dung tệp có sự khác biệt")
        }

        // Step 4: Verify target file didn't change during the process
        guard lstat(path) == targetStat else {
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .changed, reason: "Tệp đích bị thay đổi trong quá trình xử lý")
        }

        // Step 5: Atomically swap temp clone over target file
        guard rename(tempClone, path) == 0 else {
            let err = String(cString: strerror(errno))
            return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .failed, reason: "Lỗi hoán đổi rename: \(err)")
        }

        success = true
        return CloneResult(path: path, keeper: keeper, size: expectedSize, outcome: .cloned)
    }

    // MARK: - Undo / Unfold

    /// Unfolds a cloned file into a completely standalone, unshared file by doing a real physical copy.
    public static func unfold(path: String) -> Bool {
        guard let targetStat = lstat(path), let originalMeta = readMetadata(path) else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        let tempFile = "\(dir)/.xmac-unfold-\(UUID().uuidString.prefix(8))"

        defer { _ = unlink(tempFile) }

        // COPYFILE_DATA without COPYFILE_CLONE writes unshared blocks
        guard copyfile(path, tempFile, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_NOFOLLOW)) == 0 else {
            return false
        }

        guard copyMetadata(from: path, to: tempFile),
              readMetadata(tempFile) == originalMeta,
              contentsEqual(tempFile, path),
              lstat(path) == targetStat else {
            return false
        }

        return rename(tempFile, path) == 0
    }
}
