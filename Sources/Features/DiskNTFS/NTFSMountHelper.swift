import Cocoa

struct DiskCommandResult {
    let status: Int32
    let output: String
}

enum MountOutputVerifier {
    static func isReadWriteMount(output: String, mountPoint: String) -> Bool {
        output.split(separator: "\n").contains { rawLine in
            let line = String(rawLine)
            guard line.contains(" on \(mountPoint) (") else { return false }
            let lowercased = line.lowercased()
            return !lowercased.contains("read-only") && !lowercased.contains("rdonly")
        }
    }
}

public protocol DiskMounter {
    var canEnableNTFSWrite: Bool { get }
    var writeHelperDescription: String { get }
    func mountNTFSReadWrite(volume: DiskVolume, completion: @escaping (NTFSMountHelper.MountResult) -> Void)
    func ejectVolume(volume: DiskVolume, completion: @escaping (Bool) -> Void)
    func openInFinder(volume: DiskVolume)
}

public class NTFSMountHelper: DiskMounter {
    public static let shared = NTFSMountHelper()

    public enum MountResult {
        case success(mountPath: String)
        case requiresSudo(command: String)
        case failure(error: String)
        case helperMissing(message: String)
    }

    private enum WriteBackend {
        case anylinuxfs(URL)
        case ntfs3g(URL)
        case unavailable
    }

    private enum RollbackOutcome {
        case notNeeded
        case restored
        case failed(String)
    }

    private let operationQueue = DispatchQueue(label: "vn.xmac.ntfs-mount", qos: .userInitiated)

    private init() {}

    public var canEnableNTFSWrite: Bool {
        if case .unavailable = detectWriteBackend() { return false }
        return true
    }

    public var writeHelperDescription: String {
        switch detectWriteBackend() {
        case .anylinuxfs(let url):
            return "AnyLinuxFS (\(url.path))"
        case .ntfs3g(let url):
            return "ntfs-3g / macFUSE (\(url.path))"
        case .unavailable:
            return "Chưa cài AnyLinuxFS hoặc ntfs-3g/macFUSE"
        }
    }

    public func mountNTFSReadWrite(volume: DiskVolume, completion: @escaping (MountResult) -> Void) {
        operationQueue.async {
            guard volume.isNTFS else {
                DispatchQueue.main.async {
                    completion(.failure(error: "Phân vùng không phải NTFS."))
                }
                return
            }
            guard BSDDeviceName.isValid(volume.bsdName) else {
                DispatchQueue.main.async {
                    completion(.failure(error: "Định danh thiết bị không hợp lệ."))
                }
                return
            }

            let backend = self.detectWriteBackend()
            let mountBinary: URL
            switch backend {
            case .anylinuxfs(let url), .ntfs3g(let url):
                mountBinary = url
            case .unavailable:
                DispatchQueue.main.async {
                    completion(.helperMissing(message: """
                    Không thể bật ghi NTFS: macOS không hỗ trợ ghi NTFS gốc.
                    Cài AnyLinuxFS (Homebrew) hoặc macFUSE + ntfs-3g rồi thử lại.
                    """))
                }
                return
            }

            let deviceNode = "/dev/\(volume.bsdName)"
            let targetMountPoint = "/Volumes/Xmac_\(volume.bsdName)"

            var didUnmountOriginalVolume = false
            let isCurrentlyMounted = self.currentMountState(bsdName: volume.bsdName)
                ?? volume.isMounted
            if isCurrentlyMounted {
                let unmount = self.executeCommand(
                    "/usr/sbin/diskutil",
                    arguments: ["unmount", deviceNode]
                )
                if unmount.status == 0 {
                    didUnmountOriginalVolume = true
                } else if !Self.canContinueAfterUnmountFailure(
                    currentlyMounted: self.currentMountState(bsdName: volume.bsdName)
                ) {
                    self.complete(
                        .failure(error: "Không thể unmount phân vùng an toàn: \(unmount.output)"),
                        completion: completion
                    )
                    return
                }
            }

            let innerCommand: String
            switch backend {
            case .anylinuxfs:
                innerCommand = POSIXShell.join([
                    "/bin/mkdir", "-p", targetMountPoint
                ]) + " && " + POSIXShell.join([
                    mountBinary.path, "mount", deviceNode, targetMountPoint
                ])
            case .ntfs3g:
                innerCommand = POSIXShell.join([
                    "/bin/mkdir", "-p", targetMountPoint
                ]) + " && " + POSIXShell.join([
                    mountBinary.path, deviceNode, targetMountPoint
                ])
            case .unavailable:
                return
            }

            let appleScriptSource = "do shell script \(self.appleScriptStringLiteral(innerCommand)) with administrator privileges"
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: appleScriptSource) else {
                let rollback = self.rollbackReadOnlyIfNeeded(
                    deviceNode: deviceNode,
                    targetMountPoint: targetMountPoint,
                    shouldRollback: didUnmountOriginalVolume
                )
                self.complete(
                    .failure(error: self.failureMessage("Không tạo được lệnh mount.", rollback: rollback)),
                    completion: completion
                )
                return
            }

            _ = appleScript.executeAndReturnError(&error)
            if let err = error {
                let errMsg = err["NSAppleScriptErrorMessage"] as? String ?? "Lỗi không xác định"
                let rollback = self.rollbackReadOnlyIfNeeded(
                    deviceNode: deviceNode,
                    targetMountPoint: targetMountPoint,
                    shouldRollback: didUnmountOriginalVolume
                )
                self.complete(
                    .failure(error: self.failureMessage(errMsg, rollback: rollback)),
                    completion: completion
                )
                return
            }

            if self.verifyReadWriteMount(targetMountPoint: targetMountPoint) {
                SoundEffectManager.shared.play(.mount)
                NSWorkspace.shared.open(URL(fileURLWithPath: targetMountPoint))
                DispatchQueue.main.async {
                    DiskManager.shared.refreshVolumes()
                    completion(.success(mountPath: targetMountPoint))
                }
            } else {
                let rollback = self.rollbackReadOnlyIfNeeded(
                    deviceNode: deviceNode,
                    targetMountPoint: targetMountPoint,
                    shouldRollback: didUnmountOriginalVolume
                )
                self.complete(
                    .failure(error: self.failureMessage(
                        "Helper đã chạy nhưng phân vùng chưa được xác minh ở chế độ đọc-ghi.",
                        rollback: rollback
                    )),
                    completion: completion
                )
            }
        }
    }

    public func ejectVolume(volume: DiskVolume, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard BSDDeviceName.isValid(volume.bsdName) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["eject", volume.bsdName]

            do {
                try process.run()
                process.waitUntilExit()
                let success = process.terminationStatus == 0
                if success {
                    SoundEffectManager.shared.play(.eject)
                }
                DispatchQueue.main.async {
                    DiskManager.shared.refreshVolumes()
                    completion(success)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    public func openInFinder(volume: DiskVolume) {
        if let path = volume.mountPoint, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func detectWriteBackend() -> WriteBackend {
        let anylinuxfsCandidates = [
            "/opt/homebrew/bin/anylinuxfs",
            "/usr/local/bin/anylinuxfs"
        ]
        for path in anylinuxfsCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return .anylinuxfs(URL(fileURLWithPath: path))
        }

        let ntfs3gCandidates = [
            "/opt/homebrew/bin/ntfs-3g",
            "/usr/local/bin/ntfs-3g",
            "/opt/homebrew/sbin/mount_ntfs",
            "/usr/local/sbin/mount_ntfs"
        ]
        for path in ntfs3gCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return .ntfs3g(URL(fileURLWithPath: path))
        }
        return .unavailable
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func verifyReadWriteMount(targetMountPoint: String) -> Bool {
        let mountResult = executeCommand("/sbin/mount", arguments: [])
        guard mountResult.status == 0 else { return false }
        return MountOutputVerifier.isReadWriteMount(
            output: mountResult.output,
            mountPoint: targetMountPoint
        )
    }

    static func canContinueAfterUnmountFailure(currentlyMounted: Bool?) -> Bool {
        currentlyMounted == false
    }

    private func currentMountState(bsdName: String) -> Bool? {
        let info = executeCommand(
            "/usr/sbin/diskutil",
            arguments: ["info", "-plist", bsdName]
        )
        guard info.status == 0,
              let data = info.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return plist["Mounted"] as? Bool
    }

    private func rollbackReadOnlyIfNeeded(
        deviceNode: String,
        targetMountPoint: String,
        shouldRollback: Bool
    ) -> RollbackOutcome {
        _ = executeCommand("/usr/sbin/diskutil", arguments: ["unmount", targetMountPoint])
        cleanupEmptyMountPoint(targetMountPoint)
        guard shouldRollback else { return .notNeeded }

        let remount = executeCommand("/usr/sbin/diskutil", arguments: ["mount", deviceNode])
        return remount.status == 0 ? .restored : .failed(remount.output)
    }

    private func cleanupEmptyMountPoint(_ path: String) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path),
              contents.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func failureMessage(_ message: String, rollback: RollbackOutcome) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rollback {
        case .notNeeded:
            return trimmedMessage
        case .restored:
            return "\(trimmedMessage) Ổ đĩa đã được khôi phục về chế độ mặc định."
        case .failed(let details):
            let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedDetails.isEmpty
                ? "\(trimmedMessage) Không thể tự khôi phục ổ đĩa."
                : "\(trimmedMessage) Không thể tự khôi phục ổ đĩa: \(trimmedDetails)"
        }
    }

    private func complete(_ result: MountResult, completion: @escaping (MountResult) -> Void) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    @discardableResult
    private func executeCommand(_ launchPath: String, arguments: [String]) -> DiskCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return DiskCommandResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return DiskCommandResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
