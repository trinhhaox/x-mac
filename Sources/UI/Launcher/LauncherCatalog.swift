import AppKit

struct LauncherEntry: Identifiable, Equatable {
    enum Destination: Equatable {
        case tab(NavigationTab)
        case toggleLanguage
        case convertFinderSelection
        case captureScreenText
        case application(String)
        case file(String)
        case calculation(String)
    }
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let destination: Destination

    static var commands: [LauncherEntry] {
        NavigationTab.allCases.map {
            LauncherEntry(id: "tab:\($0.rawValue)", title: $0.title,
                          subtitle: L10n.text("Mở trong Xmac"), icon: $0.iconName, destination: .tab($0))
        } + [LauncherEntry(id: "language", title: L10n.text("Chuyển Tiếng Việt / English"),
                           subtitle: L10n.text("Bật hoặc tắt bộ gõ • Cần quyền Trợ năng"),
                           icon: "character.bubble", destination: .toggleLanguage),
                LauncherEntry(id: "convert-finder-selection", title: L10n.text("Chuyển đổi tệp đang chọn trong Finder"),
                              subtitle: L10n.text("Chọn định dạng đích cho tệp đang chọn"),
                              icon: NavigationTab.converter.iconName, destination: .convertFinderSelection),
                LauncherEntry(id: "capture-screen-text", title: L10n.text("Nhận chữ từ vùng màn hình"),
                              subtitle: L10n.text("Chọn vùng, nhận dạng chữ (OCR) và chép vào bộ nhớ tạm"),
                              icon: "text.viewfinder", destination: .captureScreenText)]
    }

    static func matching(_ entries: [LauncherEntry], query: String, limit: Int = 30) -> [LauncherEntry] {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.enumerated().compactMap { index, entry -> (Int, Int, LauncherEntry)? in
            let title = normalized(entry.title)
            let searchable = title + " " + normalized(entry.subtitle)
            guard terms.allSatisfy({ searchable.contains($0) }) else { return nil }
            let score = terms.isEmpty ? 0 : (title == normalized(query) ? 0 : (title.hasPrefix(terms.joined(separator: " ")) ? 1 : 2))
            return (score, index, entry)
        }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.prefix(max(0, limit)).map { $0.2 }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applications(in roots: [URL]) -> [LauncherEntry] {
        var seen = Set<String>()
        var results: [LauncherEntry] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                let name = FileManager.default.displayName(atPath: url.path)
                results.append(LauncherEntry(id: "app:" + url.path, title: name,
                    subtitle: url.path, icon: "app", destination: .application(url.path)))
            }
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
