import Cocoa

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
        DispatchQueue.global(qos: .userInitiated).async {
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

            self.executeCommand("/usr/sbin/diskutil", arguments: ["unmount", deviceNode])
            try? FileManager.default.createDirectory(
                atPath: targetMountPoint,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let innerCommand: String
            switch backend {
            case .anylinuxfs:
                innerCommand = POSIXShell.join([
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
                DispatchQueue.main.async {
                    completion(.failure(error: "Không tạo được lệnh mount."))
                }
                return
            }

            _ = appleScript.executeAndReturnError(&error)
            if let err = error {
                let errMsg = err["NSAppleScriptErrorMessage"] as? String ?? "Lỗi không xác định"
                DispatchQueue.main.async {
                    completion(.failure(error: errMsg))
                }
                return
            }

            if FileManager.default.fileExists(atPath: targetMountPoint) {
                SoundEffectManager.shared.play(.mount)
                NSWorkspace.shared.open(URL(fileURLWithPath: targetMountPoint))
                DispatchQueue.main.async {
                    DiskManager.shared.refreshVolumes()
                    completion(.success(mountPath: targetMountPoint))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(error: "Không tìm thấy điểm mount sau khi chạy helper."))
                }
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

    @discardableResult
    private func executeCommand(_ launchPath: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
