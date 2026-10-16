import AppKit
import Darwin

struct OrganizationRule: Identifiable, Equatable {
    let folder: String
    let extensions: Set<String>
    var enabled = true
    var id: String { folder }
    static let defaults: [OrganizationRule] = [
        .init(folder: "Tài liệu", extensions: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv"]),
        .init(folder: "Hình ảnh", extensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"]),
        .init(folder: "Video", extensions: ["mp4", "mov", "mkv", "webm"]),
        .init(folder: "Âm thanh", extensions: ["mp3", "wav", "m4a", "flac"]),
        .init(folder: "File nén", extensions: ["zip", "7z", "rar", "gz", "tar"]),
        .init(folder: "Bộ cài", extensions: ["dmg", "pkg"])
    ]
}

struct OrganizationIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let size: UInt64
    let modified: Date
    static func read(_ url: URL) throws -> Self {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              let inode = attrs[.systemFileNumber] as? NSNumber,
              let device = attrs[.systemNumber] as? NSNumber,
              let size = attrs[.size] as? NSNumber, let date = attrs[.modificationDate] as? Date else {
            throw UpdateFailure("Chỉ xử lý tệp thường, không xử lý thư mục hoặc liên kết.")
        }
        return Self(device: device.uint64Value, inode: inode.uint64Value, size: size.uint64Value, modified: date)
    }
}

struct OrganizationPreview: Identifiable {
    let source: URL
    let folder: String
    let identity: OrganizationIdentity
    var id: String { source.path }
}

struct OrganizationJournal: Codable {
    struct Move: Codable {
        let source: URL
        let destination: URL
        let identity: OrganizationIdentity
    }
    let root: URL
    var moves: [Move]
}

enum OrganizationEngine {
    static func validFolder(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }
    static func preview(root: URL, rules: [OrganizationRule], now: Date = Date()) throws -> [OrganizationPreview] {
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { url in
            guard let rule = rules.first(where: { $0.enabled && $0.extensions.contains(url.pathExtension.lowercased()) }), validFolder(rule.folder),
                  let identity = try? OrganizationIdentity.read(url), now.timeIntervalSince(identity.modified) >= 5 else { return nil }
            return OrganizationPreview(source: url, folder: rule.folder, identity: identity)
        }.prefix(500).map { $0 }
    }

    static func load(_ store: URL) throws -> OrganizationJournal? {
        guard FileManager.default.fileExists(atPath: store.path) else { return nil }
        return try JSONDecoder().decode(OrganizationJournal.self, from: Data(contentsOf: store))
    }
    static func save(_ journal: OrganizationJournal, to store: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(journal).write(to: store, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)
    }

    static func apply(root: URL, preview: [OrganizationPreview], store: URL) throws -> [String] {
        guard try load(store)?.moves.isEmpty != false else { throw UpdateFailure("Hãy hoàn tác hoặc giữ thay đổi trước khi sắp xếp lần mới.") }
        let fm = FileManager.default
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        var journal = OrganizationJournal(root: root, moves: [])
        var errors: [String] = []
        for entry in preview {
            let directory = root.appendingPathComponent(entry.folder, isDirectory: true)
            do {
                guard validFolder(entry.folder), entry.source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == root.path,
                      try OrganizationIdentity.read(entry.source) == entry.identity else { throw UpdateFailure("Tệp đã thay đổi sau khi xem trước.") }
                if fm.fileExists(atPath: directory.path) {
                    let attrs = try fm.attributesOfItem(atPath: directory.path)
                    guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw UpdateFailure("Thư mục đích không hợp lệ hoặc là liên kết.") }
                } else {
                    try fm.createDirectory(at: directory, withIntermediateDirectories: false)
                }
                let targetAttributes = try fm.attributesOfItem(atPath: directory.path)
                guard (targetAttributes[.systemNumber] as? NSNumber)?.uint64Value == entry.identity.device else {
                    throw UpdateFailure("Không di chuyển sang hệ thống tệp khác để bảo đảm hoàn tác.")
                }
            } catch { errors.append("\(entry.source.lastPathComponent): \(error.localizedDescription)"); continue }
            let destination = DownloadManager.uniqueDestination(for: entry.source.lastPathComponent, in: directory)
            journal.moves.append(.init(source: entry.source, destination: destination, identity: entry.identity))
            // Write ahead: a crash cannot silently lose the undo record.
            try save(journal, to: store)
            do {
                guard try OrganizationIdentity.read(entry.source) == entry.identity else { throw UpdateFailure("Tệp đã thay đổi trong lúc chuẩn bị di chuyển.") }
                try fm.moveItem(at: entry.source, to: destination)
            }
            catch {
                journal.moves.removeLast()
                try save(journal, to: store)
                errors.append("\(entry.source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return errors
    }

    static func undo(store: URL) throws -> [String] {
        guard var journal = try load(store) else { return [] }
        let fm = FileManager.default
        var errors: [String] = []
        for index in journal.moves.indices.reversed() {
            let move = journal.moves[index]
            do {
                guard move.source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == journal.root.path,
                      move.destination.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == journal.root.path,
                      move.destination.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == move.destination.deletingLastPathComponent().standardizedFileURL.path else {
                    throw UpdateFailure("Đường dẫn đã thay đổi hoặc đi qua liên kết.")
                }
                if !fm.fileExists(atPath: move.destination.path), (try? OrganizationIdentity.read(move.source)) == move.identity {
                    journal.moves.remove(at: index)
                    try save(journal, to: store)
                    continue
                }
                guard !fm.fileExists(atPath: move.source.path), try OrganizationIdentity.read(move.destination) == move.identity else {
                    throw UpdateFailure("Tệp đã sửa hoặc tên gốc đã tồn tại; không ghi đè.")
                }
                try fm.moveItem(at: move.destination, to: move.source)
            } catch { errors.append("\(move.source.lastPathComponent): \(error.localizedDescription)"); continue }
            journal.moves.remove(at: index)
            try save(journal, to: store)
        }
        return errors
    }
}

final class DownloadsOrganizer: ObservableObject {
    static let shared = DownloadsOrganizer()
    @Published private(set) var root: URL
    @Published var rules = OrganizationRule.defaults {
        didSet { defaults.set(rules.filter { !$0.enabled }.map(\.folder), forKey: "Organizer.DisabledFolders") }
    }
    @Published private(set) var preview: [OrganizationPreview] = []
    @Published private(set) var busy = false
    @Published private(set) var message = L10n.text("Xem trước trước khi di chuyển tệp.")
    @Published private(set) var undoCount = 0
    @Published private(set) var undoRoot = ""
    @Published var confirmation = false
    @Published var keepConfirmation = false
    private let queue = DispatchQueue(label: "vn.xmac.organizer", qos: .utility)
    private let store: URL
    private let defaults: UserDefaults
    private var watcher: DispatchSourceFileSystemObject?
    private var refreshWork: DispatchWorkItem?
    private var generation = UUID()
    private var requestedPlan: (root: URL, entries: [OrganizationPreview])?
    init(root: URL? = nil, store: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.root = (root ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser).resolvingSymlinksInPath().standardizedFileURL
        self.store = store ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Xmac/Organizer/undo.json")
        let saved = try? OrganizationEngine.load(self.store)
        undoCount = saved?.moves.count ?? 0
        undoRoot = saved?.root.path ?? ""
        let disabled = Set(defaults.stringArray(forKey: "Organizer.DisabledFolders") ?? [])
        rules = OrganizationRule.defaults.map { var rule = $0; rule.enabled = !disabled.contains(rule.folder); return rule }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url {
            root = url.resolvingSymlinksInPath().standardizedFileURL
            startWatching()
        }
    }
    func startWatching() {
        stopWatching()
        let descriptor = open(root.path, O_EVTONLY)
        guard descriptor >= 0 else { message = L10n.text("Không thể theo dõi thư mục. Kiểm tra quyền truy cập."); return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            self.refreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        watcher = source; source.resume()
        refresh()
    }
    func stopWatching() { watcher?.cancel(); watcher = nil; refreshWork?.cancel(); generation = UUID() }
    func refresh() {
        guard !busy else { return }
        preview = []
        let token = UUID(); generation = token
        let folder = root, rules = self.rules
        queue.async {
            let result = Result { try OrganizationEngine.preview(root: folder, rules: rules) }
            DispatchQueue.main.async {
                guard self.generation == token, !self.busy else { return }
                switch result {
                case .success(let entries): self.preview = entries; self.message = L10n.format("Xem trước: %lld tệp sẵn sàng (tối đa 500). Chỉ di chuyển khi xác nhận.", Int64(entries.count))
                case .failure(let error): self.preview = []; self.message = error.localizedDescription
                }
            }
        }
    }
    func requestApply() {
        guard !busy, !preview.isEmpty, undoCount == 0 else { return }
        requestedPlan = (root, preview)
        confirmation = true
    }
    func cancelApply() { requestedPlan = nil; confirmation = false }
    func apply() {
        confirmation = false
        let plan = requestedPlan ?? (root: root, entries: preview)
        requestedPlan = nil
        perform { try OrganizationEngine.apply(root: plan.root, preview: plan.entries, store: self.store) }
    }
    func undo() { perform { try OrganizationEngine.undo(store: self.store) } }
    func keepChanges() {
        guard !busy else { return }
        perform {
            if var journal = try OrganizationEngine.load(self.store) { journal.moves = []; try OrganizationEngine.save(journal, to: self.store) }
            return []
        }
    }
    private func perform(_ operation: @escaping () throws -> [String]) {
        guard !busy else { return }
        busy = true; generation = UUID()
        queue.async {
            let result = Result { try operation() }
            let journal = try? OrganizationEngine.load(self.store)
            let count = journal?.moves.count ?? 0
            DispatchQueue.main.async {
                self.busy = false; self.undoCount = count; self.preview = []
                self.undoRoot = journal?.root.path ?? ""
                switch result {
                case .success(let errors): self.message = errors.isEmpty ? L10n.format("Đã hoàn tất. %lld tệp còn có thể hoàn tác.", Int64(count)) : errors.prefix(5).joined(separator: "\n")
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
}
