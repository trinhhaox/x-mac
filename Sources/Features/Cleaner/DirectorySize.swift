import Foundation

enum DirectorySize {
    /// Total size of a file, or of every regular file below a directory.
    static func bytes(atPath path: String, fileManager: FileManager = .default) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let attr = try? fileManager.attributesOfItem(atPath: path)
            return (attr?[.size] as? Int64) ?? 0
        }

        var totalSize: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                   values.isDirectory == false,
                   let fileSize = values.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        return totalSize
    }
}
