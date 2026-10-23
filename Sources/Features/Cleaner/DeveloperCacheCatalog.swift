import Foundation

/// Caches of developer tools that live outside ~/Library/Caches (those are already listed
/// under User Caches). Each is regenerated on demand by its tool.
///
/// Deliberately absent: Go's module cache (read-only files the Trash cannot empty),
/// ~/.m2 (may hold locally installed artifacts) and model caches such as Hugging Face
/// (large downloads users expect to keep).
enum DeveloperCacheCatalog {
    struct Entry {
        let name: String
        let relativePath: String
    }

    /// Removed as one item; a tool holding any file open inside keeps it (open-file check).
    static let wholeFolderCaches = [
        Entry(name: "npm", relativePath: ".npm/_cacache"),
        Entry(name: "pnpm store", relativePath: "Library/pnpm/store"),
        Entry(name: "Bun", relativePath: ".bun/install/cache"),
        Entry(name: "uv", relativePath: ".cache/uv"),
        Entry(name: "Gradle", relativePath: ".gradle/caches"),
        Entry(name: "Cargo registry", relativePath: ".cargo/registry/cache")
    ]

    /// Listed per child so old versions can be picked individually.
    static let childScannedFolders = [
        Entry(name: "iOS DeviceSupport", relativePath: "Library/Developer/Xcode/iOS DeviceSupport"),
        Entry(name: "CoreSimulator", relativePath: "Library/Developer/CoreSimulator/Caches")
    ]
}
