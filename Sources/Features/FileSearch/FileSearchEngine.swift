import AppKit
import Combine
import Foundation

public enum FileSearchScope: String, CaseIterable, Identifiable {
    case home = "Thư mục người dùng"
    case downloads = "Downloads"
    case documents = "Documents"
    case desktop = "Desktop"
    case applications = "Applications"
    case custom = "Thư mục đã chọn"

    public var id: String { rawValue }
    public var title: String { L10n.text(rawValue) }
}

public enum FileSearchKind: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case files = "Tệp"
    case folders = "Thư mục"
    case documents = "Tài liệu"
    case images = "Hình ảnh"
    case video = "Video"
    case audio = "Âm thanh"
    case archives = "Tệp nén"

    public var id: String { rawValue }
    public var title: String { L10n.text(rawValue) }

    fileprivate var metadataType: String? {
        switch self {
        case .all, .files, .folders: return nil
        case .documents: return "public.content"
        case .images: return "public.image"
        case .video: return "public.movie"
        case .audio: return "public.audio"
        case .archives: return "public.archive"
        }
    }

    public static func parse(_ value: String) -> FileSearchKind? {
        switch value.lowercased() {
        case "file", "files", "tep": return .files
        case "folder", "folders", "dir", "directory", "thu-muc": return .folders
        case "document", "documents", "doc", "tai-lieu": return .documents
        case "image", "images", "photo", "hinh-anh": return .images
        case "video", "movie": return .video
        case "audio", "music": return .audio
        case "archive", "archives", "zip", "compressed": return .archives
        default: return nil
        }
    }
}

public enum FileSearchMatchMode: Equatable {
    case contains
    case exact
    case prefix
    case suffix
}

public struct FileSearchTerm: Equatable {
    public let value: String
    public let mode: FileSearchMatchMode
    public let excluded: Bool
}

public struct FileSearchExpression: Equatable {
    public let terms: [FileSearchTerm]
    public let extensions: [String]
    public let kind: FileSearchKind?
    public let modifiedWithinDays: Int?

    public var isEmpty: Bool {
        terms.isEmpty && extensions.isEmpty && kind == nil && modifiedWithinDays == nil
    }

    public static func parse(_ input: String) -> FileSearchExpression {
        var terms: [FileSearchTerm] = []
        var extensions: [String] = []
        var kind: FileSearchKind?
        var modifiedWithinDays: Int?

        for rawToken in tokenize(input) {
            var token = rawToken
            let excluded = token.hasPrefix("!")
            if excluded { token.removeFirst() }
            guard !token.isEmpty else { continue }

            if !excluded, token.lowercased().hasPrefix("ext:") {
                extensions.append(contentsOf: token.dropFirst(4)
                    .split(separator: ",")
                    .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                    .filter { !$0.isEmpty })
                continue
            }
            if !excluded, token.lowercased().hasPrefix("type:") {
                kind = FileSearchKind.parse(String(token.dropFirst(5))) ?? kind
                continue
            }
            if !excluded, token.lowercased().hasPrefix("mtime:<") {
                let value = token.dropFirst(7).lowercased()
                if value.hasSuffix("d"), let days = Int(value.dropLast()), days > 0 {
                    modifiedWithinDays = min(days, 3650)
                    continue
                }
            }

            var mode: FileSearchMatchMode = .contains
            if token.hasPrefix("'") {
                token.removeFirst()
                mode = .exact
            } else if token.hasPrefix("^") {
                token.removeFirst()
                mode = .prefix
            } else if token.hasSuffix("$") {
                token.removeLast()
                mode = .suffix
            }
            if !token.isEmpty {
                terms.append(FileSearchTerm(value: token, mode: mode, excluded: excluded))
            }
        }

        return FileSearchExpression(
            terms: terms,
            extensions: Array(Set(extensions)).sorted(),
            kind: kind,
            modifiedWithinDays: modifiedWithinDays
        )
    }

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in input {
            if character == "\"" || character == "“" || character == "”" {
                if quote == nil {
                    quote = character
                } else {
                    quote = nil
                }
            } else if character.isWhitespace && quote == nil {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

public struct FileSearchResult: Identifiable, Equatable {
    public let path: String
    public let name: String
    public let kind: String
    public let size: Int64
    public let modifiedAt: Date?
    public let isDirectory: Bool

    public var id: String { path }
}

public final class FileSearchEngine: NSObject, ObservableObject {
    public static let shared = FileSearchEngine()

    @Published public private(set) var results: [FileSearchResult] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var statusMessage = L10n.text("Nhập từ khóa để bắt đầu")
    @Published public private(set) var customScopeURL: URL?

    private var metadataQuery: NSMetadataQuery?
    private var debounceWorkItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var activeExpression = FileSearchExpression.parse("")
    private let maximumResults = 200

    override init() {
        super.init()
    }

    deinit {
        stopQuery()
    }

    public func chooseCustomScope() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Chọn thư mục")
        if panel.runModal() == .OK, let url = panel.url {
            customScopeURL = url
        }
    }

    public func cancelSearch() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        stopQuery()
        results = []
        isSearching = false
        statusMessage = L10n.text("Nhập từ khóa để bắt đầu")
    }

    public func scheduleSearch(
        text: String,
        scope: FileSearchScope,
        kind: FileSearchKind,
        includeContents: Bool,
        delay: TimeInterval = 0.24
    ) {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.search(text: text, scope: scope, kind: kind, includeContents: includeContents)
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func search(text: String, scope: FileSearchScope, kind: FileSearchKind, includeContents: Bool) {
        precondition(Thread.isMainThread)
        stopQuery()

        let expression = FileSearchExpression.parse(text)
        activeExpression = expression
        guard !expression.isEmpty else {
            results = []
            statusMessage = L10n.text("Nhập từ khóa, ext:pdf hoặc type:image")
            isSearching = false
            return
        }

        let query = NSMetadataQuery()
        query.predicate = Self.predicate(for: expression, selectedKind: kind, includeContents: includeContents)
        query.searchScopes = [resolvedScope(scope)]
        query.sortDescriptors = [
            NSSortDescriptor(key: kMDItemFSContentChangeDate as String, ascending: false),
            NSSortDescriptor(key: kMDItemFSName as String, ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        ]

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                self?.consumeResults(from: query, finished: true)
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
                self?.consumeResults(from: query, finished: false)
            }
        ]
        metadataQuery = query
        results = []
        isSearching = true
        statusMessage = L10n.text("Đang hỏi chỉ mục Spotlight…")
        if !query.start() {
            isSearching = false
            statusMessage = L10n.text("Không thể khởi động Spotlight")
        }
    }

    public func open(_ result: FileSearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
    }

    public func reveal(_ result: FileSearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.path)])
    }

    public func copyPath(_ result: FileSearchResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.path, forType: .string)
        statusMessage = L10n.format("Đã sao chép: %@", result.name)
    }

    public static func predicate(
        for expression: FileSearchExpression,
        selectedKind: FileSearchKind,
        includeContents: Bool,
        now: Date = Date()
    ) -> NSPredicate {
        var predicates: [NSPredicate] = []
        let nameKey = kMDItemFSName as String

        for term in expression.terms {
            let value = term.value
            let namePredicate: NSPredicate
            switch term.mode {
            case .contains:
                namePredicate = NSPredicate(format: "%K CONTAINS[cd] %@", nameKey, value)
            case .exact:
                namePredicate = NSPredicate(format: "%K ==[cd] %@", nameKey, value)
            case .prefix:
                namePredicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", nameKey, value)
            case .suffix:
                namePredicate = NSPredicate(format: "%K ENDSWITH[cd] %@", nameKey, value)
            }

            let matchingPredicate: NSPredicate
            if includeContents, term.mode == .contains {
                matchingPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                    namePredicate,
                    NSPredicate(format: "%K CONTAINS[cd] %@", kMDItemTextContent as String, value)
                ])
            } else {
                matchingPredicate = namePredicate
            }
            predicates.append(term.excluded
                ? NSCompoundPredicate(notPredicateWithSubpredicate: matchingPredicate)
                : matchingPredicate)
        }

        if !expression.extensions.isEmpty {
            let extensionPredicates = expression.extensions.map {
                NSPredicate(format: "%K ENDSWITH[cd] %@", nameKey, ".\($0)")
            }
            predicates.append(extensionPredicates.count == 1
                ? extensionPredicates[0]
                : NSCompoundPredicate(orPredicateWithSubpredicates: extensionPredicates))
        }

        let effectiveKind = selectedKind == .all ? (expression.kind ?? .all) : selectedKind
        switch effectiveKind {
        case .all:
            break
        case .files:
            predicates.append(NSPredicate(format: "%K != %@", kMDItemContentType as String, "public.folder"))
        case .folders:
            predicates.append(NSPredicate(format: "%K == %@", kMDItemContentType as String, "public.folder"))
        default:
            if let type = effectiveKind.metadataType {
                predicates.append(NSPredicate(format: "%K == %@", kMDItemContentTypeTree as String, type))
            }
        }

        if let days = expression.modifiedWithinDays,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) {
            predicates.append(NSPredicate(format: "%K >= %@", kMDItemFSContentChangeDate as String, cutoff as NSDate))
        }
        if predicates.isEmpty {
            return NSPredicate(format: "%K LIKE[cd] %@", nameKey, "*")
        }
        if predicates.count == 1 { return predicates[0] }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func resolvedScope(_ scope: FileSearchScope) -> Any {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch scope {
        case .home: return NSMetadataQueryUserHomeScope
        case .downloads: return home.appendingPathComponent("Downloads").path
        case .documents: return home.appendingPathComponent("Documents").path
        case .desktop: return home.appendingPathComponent("Desktop").path
        case .applications: return "/Applications"
        case .custom: return customScopeURL?.path ?? home.path
        }
    }

    private func consumeResults(from query: NSMetadataQuery, finished: Bool) {
        guard query === metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var items: [FileSearchResult] = []
        let count = min(query.resultCount, maximumResults)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            items.append(FileSearchResult(
                path: path,
                name: (item.value(forAttribute: kMDItemFSName as String) as? String) ?? url.lastPathComponent,
                kind: (item.value(forAttribute: kMDItemKind as String) as? String) ?? L10n.text(values?.isDirectory == true ? "Thư mục" : "Tệp"),
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate,
                isDirectory: values?.isDirectory == true
            ))
        }

        results = Self.rank(items, expression: activeExpression)
        isSearching = !finished
        statusMessage = finished
            ? (results.isEmpty ? L10n.text("Không tìm thấy kết quả phù hợp") : L10n.format("%lld kết quả từ Spotlight", Int64(results.count)))
            : L10n.format("Đang cập nhật %lld kết quả…", Int64(results.count))
    }

    private static func rank(_ results: [FileSearchResult], expression: FileSearchExpression) -> [FileSearchResult] {
        let positive = expression.terms.filter { !$0.excluded }.map { $0.value.lowercased() }
        func score(_ item: FileSearchResult) -> Int {
            let name = item.name.lowercased()
            var value = 0
            for term in positive {
                if name == term { value += 100 }
                else if name.hasPrefix(term) { value += 60 }
                else if name.contains(term) { value += 35 }
            }
            if let modified = item.modifiedAt {
                value += max(0, 20 - Int(Date().timeIntervalSince(modified) / 86_400))
            }
            return value
        }
        return results.sorted {
            let left = score($0), right = score($1)
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left > right
        }
    }

    private func stopQuery() {
        debounceWorkItem?.cancel()
        if let query = metadataQuery { query.stop() }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        metadataQuery = nil
    }
}
