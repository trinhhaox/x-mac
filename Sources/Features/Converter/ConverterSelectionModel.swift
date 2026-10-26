import Foundation

extension ConversionGroup {
    var title: String {
        switch self {
        case .image: return "Ảnh"
        case .pdf: return "PDF"
        case .document: return "Tài liệu"
        case .office: return "Office"
        case .media: return "Âm thanh & video"
        case .archive: return "Nén & giải nén"
        case .subtitle: return "Phụ đề"
        }
    }
}

extension ExternalTool {
    /// Vietnamese hint (also its L10n key) shown when this tool would unlock more targets.
    var installHint: String {
        switch self {
        case .ffmpeg, .ffprobe: return "Cài ffmpeg: brew install ffmpeg"
        case .soffice: return "Cài LibreOffice để chuyển đổi thêm định dạng Office"
        case .ebookConvert: return "Cài calibre: brew install --cask calibre"
        }
    }
}

/// What can be done with a set of files: valid targets grouped by kind, plus install hints.
/// Shared by the converter tab, the target panel and (later) the donut.
struct ConverterSelectionModel {
    struct Section: Identifiable, Equatable {
        let group: ConversionGroup
        let targets: [ConversionTarget]
        var id: ConversionGroup { group }
    }

    static let empty = ConverterSelectionModel(inputs: [], sections: [], missingToolHints: [])

    let inputs: [URL]
    let sections: [Section]
    let missingToolHints: [String]

    private init(inputs: [URL], sections: [Section], missingToolHints: [String]) {
        self.inputs = inputs
        self.sections = sections
        self.missingToolHints = missingToolHints
    }

    init(inputs: [URL], registry: ConverterRegistry) {
        var seen = Set<URL>()
        let unique = inputs.filter { seen.insert($0.standardizedFileURL).inserted }
        self.inputs = unique
        let targets = registry.targets(for: unique)
        sections = ConversionGroup.allCases.compactMap { group in
            let inGroup = targets.filter { $0.group == group }
            return inGroup.isEmpty ? nil : Section(group: group, targets: inGroup)
        }
        var hints: [String] = []
        for tool in registry.missingTools(for: unique).sorted(by: { $0.rawValue < $1.rawValue })
        where !hints.contains(tool.installHint) {
            hints.append(tool.installHint)
        }
        missingToolHints = hints
    }

    var hasTargets: Bool { !sections.isEmpty }

    var summary: String {
        inputs.count == 1 ? inputs[0].lastPathComponent : L10n.format("%d tệp", inputs.count)
    }
}
