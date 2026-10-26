import Foundation

/// EPUB → TXT / HTML / DOCX / RTF without external tools. PDF is left to calibre.
struct EPUBConverter: FileConverter {
    let id = "epub"
    let requiredTool: ExternalTool? = nil

    private static let textutil = URL(fileURLWithPath: "/usr/bin/textutil")
    private static let formats: [(ext: String, title: String)] = [
        ("txt", "Văn bản thuần (TXT)"),
        ("html", "HTML"),
        ("docx", "Word (DOCX)"),
        ("rtf", "RTF")
    ]

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        guard input.lowercasedExtension == "epub" else { return [] }
        return Self.formats.map {
            ConversionTarget(id: "\(id).\($0.ext)", title: $0.title, fileExtension: $0.ext, group: .document)
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              input.lowercasedExtension == "epub",
              Self.formats.contains(where: { $0.ext == request.target.fileExtension }) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? "")
        }
        let format = request.target.fileExtension
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let unpacked = directory.appendingPathComponent("epub", isDirectory: true)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let package = try await EPUBPackage.load(input, extractingInto: unpacked)
            progress(0.4)
            let html = try EPUBHTMLBuilder.html(for: package)
            let source = directory.appendingPathComponent("book.html")
            try Data(html.utf8).write(to: source)
            progress(0.7)
            if format == "html" {
                try ConverterWorkspace.publish(source, to: request.outputURL)
            } else {
                let produced = directory.appendingPathComponent("output.\(format)")
                try await ConverterWorkspace.run(
                    Self.textutil, ["-convert", format, "-output", produced.path, source.path], timeout: 180)
                try ConverterWorkspace.publish(produced, to: request.outputURL)
            }
        }
        progress(1)
    }
}
