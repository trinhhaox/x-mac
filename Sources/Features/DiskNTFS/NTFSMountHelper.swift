import Cocoa

public class NTFSMountHelper {
    public static let shared = NTFSMountHelper()
    
    private init() {}
    
    public enum MountResult {
        case success(mountPath: String)
        case requiresSudo(command: String)
        case failure(error: String)
    }
    
    public func mountNTFSReadWrite(volume: DiskVolume, completion: @escaping (MountResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bsd = volume.bsdName
            let deviceNode = "/dev/\(bsd)"
            let safeName = volume.name.replacingOccurrences(of: " ", with: "_")
            let targetMountPoint = "/Volumes/Xmac_\(safeName)"
            
            // 1. Kiểm tra AnyLinuxFS (microVM NFS)
            let anylinuxfsPath = "/opt/homebrew/bin/anylinuxfs"
            let hasAnyLinuxFS = FileManager.default.fileExists(atPath: anylinuxfsPath)
            
            // 2. Chạy kịch bản mount
            // Unmount read-only trước
            self.executeCommand("/usr/sbin/diskutil", arguments: ["unmount", deviceNode])
            
            // Tạo thư mục mount point nếu chưa có
            try? FileManager.default.createDirectory(atPath: targetMountPoint, withIntermediateDirectories: true, attributes: nil)
            
            // Thử mount native read-write qua mount_ntfs (hoặc mount -o rw)
            let script: String
            if hasAnyLinuxFS {
                script = "\(anylinuxfsPath) mount \(deviceNode) \(targetMountPoint)"
            } else {
                // macOS native remount script với quyền admin
                script = "mkdir -p '\(targetMountPoint)' && mount -t ntfs -o rw,nobrowse \(deviceNode) '\(targetMountPoint)'"
            }
            
            let appleScriptSource = """
            do shell script "\(script)" with administrator privileges
            """
            
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: appleScriptSource) {
                _ = appleScript.executeAndReturnError(&error)
                if let err = error {
                    let errMsg = err["NSAppleScriptErrorMessage"] as? String ?? "Lỗi không xác định"
                    DispatchQueue.main.async {
                        completion(.failure(error: errMsg))
                    }
                    return
                }
            }
            
            // Kiểm tra xem đã mount thành công chưa
            if FileManager.default.fileExists(atPath: targetMountPoint) {
                SoundEffectManager.shared.play(.mount)
                // Mở Finder đến thư mục vừa mount
                NSWorkspace.shared.open(URL(fileURLWithPath: targetMountPoint))
                DispatchQueue.main.async {
                    DiskManager.shared.refreshVolumes()
                    completion(.success(mountPath: targetMountPoint))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(error: "Không thể tạo điểm mount tại \(targetMountPoint)"))
                }
            }
        }
    }
    
    public func ejectVolume(volume: DiskVolume, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
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
