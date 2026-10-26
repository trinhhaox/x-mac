import Foundation

/// Word-processing conversions through macOS's built-in `textutil`.
struct DocumentConverter: FileConverter {
    let id = "document"
    let requiredTool: ExternalTool? = nil

    private static let textutil = URL(fileURLWithPath: "/usr/bin/textutil")
    private static let inputs: Set<String> = ["docx", "rtf", "rtfd", "odt", "html", "htm", "txt", "webarchive", "doc"]
    private static let formats: [(ext: String, title: String)] = [
        ("docx", "Word (DOCX)"),
        ("rtf", "RTF"),
        ("odt", "OpenDocument (ODT)"),
        ("html", "HTML"),
        ("txt", "Văn bản thuần (TXT)")
    ]

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        let source = Self.canonical(input.lowercasedExtension)
        guard Self.inputs.contains(input.lowercasedExtension) else { return [] }
        return Self.formats.filter { $0.ext != source }.map {
            ConversionTarget(id: "\(id).\($0.ext)", title: $0.title, fileExtension: $0.ext, group: .document)
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              Self.inputs.contains(input.lowercasedExtension) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? "")
        }
        let format = request.target.fileExtension
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let produced = directory.appendingPathComponent("output.\(format)")
            try await ConverterWorkspace.run(
                Self.textutil, ["-convert", format, "-output", produced.path, input.path], timeout: 120
            )
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }

    private static func canonical(_ ext: String) -> String { ext == "htm" ? "html" : ext }
}
