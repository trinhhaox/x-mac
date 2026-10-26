import Foundation

/// File kinds a watch rule can listen for. `sampleExtensions` are only used to list the
/// targets the converters offer for the group.
enum WatchInputGroup: String, CaseIterable, Identifiable {
    case image, pdf, video, audio, document, subtitle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: return "Ảnh"
        case .pdf: return "PDF"
        case .video: return "Video"
        case .audio: return "Âm thanh"
        case .document: return "Tài liệu"
        case .subtitle: return "Phụ đề"
        }
    }

    var extensions: [String] {
        switch self {
        case .image: return ["jpg", "jpeg", "png", "heic", "tiff", "tif", "gif", "bmp", "webp"]
        case .pdf: return ["pdf"]
        case .video: return ["mp4", "mov", "mkv", "webm", "avi", "m4v"]
        case .audio: return ["mp3", "wav", "m4a", "flac", "aac", "ogg"]
        case .document: return ["txt", "rtf", "html", "docx", "doc", "odt", "xlsx", "pptx"]
        case .subtitle: return ["srt", "vtt", "ass"]
        }
    }

    private var sampleExtensions: [String] {
        switch self {
        case .image: return ["jpg", "heic"]
        case .pdf: return ["pdf"]
        case .video: return ["mp4"]
        case .audio: return ["m4a", "wav"]
        case .document: return ["docx", "rtf"]
        case .subtitle: return ["srt", "vtt"]
        }
    }

    /// Union of the targets offered for each sample extension (a format is never offered for itself).
    /// Page extraction is left out: it needs the global page range, which a background rule cannot ask for.
    func targets(in registry: ConverterRegistry) -> [ConversionTarget] {
        var seen = Set<String>()
        return sampleExtensions
            .flatMap { registry.targets(for: [URL(fileURLWithPath: "/watch/sample.\($0)")]) }
            .filter { $0.id != PDFPagesConverter.extractTargetID && seen.insert($0.id).inserted }
    }
}

/// "Convert files of these types that appear in this folder into that target."
struct WatchFolderRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var folderPath: String
    /// Lowercase, no dot.
    var extensions: [String]
    var targetID: String
    /// Display only; conversion resolves the target by `targetID`.
    var targetTitle: String
    /// Folder inside the watched folder that receives the results; nil saves next to the original.
    var outputSubfolder: String?
    var enabled = true

    var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }

    /// Stored values are re-validated, so a tampered default cannot point outside the watched folder.
    var outputDirectory: URL? { outputSubfolder.flatMap(Self.normalizedSubfolder).map { folderURL.appendingPathComponent($0, isDirectory: true) } }

    /// Direct children only; files inside sub-folders (including the output subfolder) never match.
    func accepts(_ file: URL) -> Bool {
        extensions.contains(file.pathExtension.lowercased())
            && file.deletingLastPathComponent().resolvingSymlinksInPath().path == folderURL.resolvingSymlinksInPath().path
    }

    /// Trimmed subfolder name, or nil when blank or not a plain folder name.
    static func normalizedSubfolder(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return OrganizationEngine.validFolder(name) ? name : nil
    }
}

enum WatchCandidateFilter {
    private static let ignoredSuffixes = [".xmac-partial", ".download", ".crdownload", ".part"]

    /// Hidden files, Xmac's own partial files and unfinished browser downloads.
    static func isIgnored(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix(".") || name.contains(".xmac-partial") || ignoredSuffixes.contains { name.hasSuffix($0) }
    }
}
