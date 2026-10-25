import Darwin
import Foundation

/// Fast directory walker built on Darwin `getattrlistbulk(2)`.
/// Reads attributes of dozens to hundreds of directory entries in a single syscall into a 256KB buffer,
/// avoiding millions of separate `lstat` calls.
public struct FastDirectoryWalker: Sendable {
    public struct FileEntry: Sendable, Equatable {
        public let path: String
        public let device: dev_t
        public let inode: ino_t
        public let size: Int64
        public let links: nlink_t
        public let flags: UInt32
        public let uid: uid_t
        public let mtime: timespec
        public let ctime: timespec

        public init(path: String, device: dev_t, inode: ino_t, size: Int64, links: nlink_t,
                    flags: UInt32, uid: uid_t, mtime: timespec, ctime: timespec) {
            self.path = path
            self.device = device
            self.inode = inode
            self.size = size
            self.links = links
            self.flags = flags
            self.uid = uid
            self.mtime = mtime
            self.ctime = ctime
        }

        public static func == (a: FileEntry, b: FileEntry) -> Bool {
            a.device == b.device && a.inode == b.inode && a.size == b.size && a.links == b.links
                && a.flags == b.flags && a.uid == b.uid
                && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
                && a.ctime.tv_sec == b.ctime.tv_sec && a.ctime.tv_nsec == b.ctime.tv_nsec
        }
    }

    private let skipPaths: Set<String>
    private let threadCount: Int

    public init(skipPaths: Set<String> = [], threadCount: Int = max(2, ProcessInfo.processInfo.activeProcessorCount)) {
        self.skipPaths = skipPaths
        self.threadCount = threadCount
    }

    /// Recursively walks `rootPath` and invokes `onFile` for every regular file found on the same volume.
    public func walk(rootPath: String, onFile: @escaping @Sendable (FileEntry) -> Void) {
        var rootStat = Darwin.stat()
        guard Darwin.lstat(rootPath, &rootStat) == 0 else { return }

        // If root is a single regular file
        if (rootStat.st_mode & S_IFMT) == S_IFREG {
            let entry = FileEntry(path: rootPath, device: rootStat.st_dev, inode: rootStat.st_ino,
                                  size: rootStat.st_size, links: rootStat.st_nlink, flags: rootStat.st_flags,
                                  uid: rootStat.st_uid, mtime: rootStat.st_mtimespec, ctime: rootStat.st_ctimespec)
            onFile(entry)
            return
        }

        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else { return }

        let queue = WalkerWorkQueue(first: rootPath)
        let rootDevice = Int32(rootStat.st_dev)

        DispatchQueue.concurrentPerform(iterations: threadCount) { _ in
            let bufferSize = 256 * 1024
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
            defer { buffer.deallocate() }

            while let dir = queue.next() {
                var subdirs: [String] = []
                listDirectory(dir, targetDevice: rootDevice, buffer: buffer, bufferSize: bufferSize,
                              onFile: onFile, onSubdir: { subdirs.append($0) })
                queue.finish(adding: subdirs)
            }
        }
    }

    private func listDirectory(_ dir: String, targetDevice: Int32, buffer: UnsafeMutableRawPointer, bufferSize: Int,
                               onFile: (FileEntry) -> Void, onSubdir: (String) -> Void) {
        let fd = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_CHGTIME) | attrgroup_t(ATTR_CMN_OWNERID) | attrgroup_t(ATTR_CMN_FLAGS)
            | attrgroup_t(ATTR_CMN_FILEID)
        attrs.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_DATALENGTH)
        let options = UInt64(FSOPT_PACK_INVAL_ATTRS) | UInt64(FSOPT_NOFOLLOW)
        let prefix = (dir == "/") ? "" : dir

        while true {
            let count = getattrlistbulk(fd, &attrs, buffer, bufferSize, options)
            if count <= 0 { break }

            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }

                var p = entry + 4 + MemoryLayout<attribute_set_t>.size
                let nameRef = p
                let nameOffset = Int(p.loadUnaligned(as: Int32.self))
                let nameLength = Int(p.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
                p += 8

                let devid = p.loadUnaligned(as: Int32.self); p += 4
                let type = p.loadUnaligned(as: UInt32.self); p += 4
                let mtime = p.loadUnaligned(as: timespec.self); p += MemoryLayout<timespec>.size
                let ctime = p.loadUnaligned(as: timespec.self); p += MemoryLayout<timespec>.size
                let uid = p.loadUnaligned(as: UInt32.self); p += 4
                let flags = p.loadUnaligned(as: UInt32.self); p += 4
                let inode = p.loadUnaligned(as: UInt64.self); p += 8
                let links = p.loadUnaligned(as: UInt32.self); p += 4
                let size = p.loadUnaligned(as: Int64.self)

                let namePtr = (nameRef + nameOffset).assumingMemoryBound(to: CChar.self)
                let name = String(decoding: UnsafeRawBufferPointer(start: namePtr, count: max(0, nameLength - 1)), as: UTF8.self)
                let fullPath = prefix + "/" + name

                switch type {
                case UInt32(VDIR.rawValue):
                    if devid == targetDevice, !skipPaths.contains(fullPath) {
                        onSubdir(fullPath)
                    }
                case UInt32(VREG.rawValue):
                    if name.hasPrefix(".xmac-clone-") || name.hasPrefix(".twinfold-") { continue }
                    let fileEntry = FileEntry(
                        path: fullPath,
                        device: dev_t(devid),
                        inode: ino_t(inode),
                        size: size,
                        links: nlink_t(links),
                        flags: flags,
                        uid: uid_t(uid),
                        mtime: mtime,
                        ctime: ctime
                    )
                    onFile(fileEntry)
                default:
                    continue
                }
            }
        }
    }
}

/// Thread-safe queue of directories to visit with termination condition.
final class WalkerWorkQueue: @unchecked Sendable {
    private var stack: [String]
    private var busyCount = 0
    private let condition = NSCondition()

    init(first: String) {
        self.stack = [first]
    }

    func next() -> String? {
        condition.lock()
        defer { condition.unlock() }

        while stack.isEmpty {
            if busyCount == 0 {
                condition.broadcast()
                return nil
            }
            condition.wait()
        }
        busyCount += 1
        return stack.removeLast()
    }

    func finish(adding subdirs: [String]) {
        condition.lock()
        stack.append(contentsOf: subdirs)
        busyCount -= 1
        condition.broadcast()
        condition.unlock()
    }
}
