import Foundation

/// E-book conversions through calibre's `ebook-convert` (MOBI, AZW3, FB2, comics, …).
struct CalibreConverter: FileConverter {
    let id = "calibre"
    let requiredTool: ExternalTool? = .ebookConvert
    let locator: BinaryLocator

    private static let inputs: Set<String> = [
        "epub", "mobi", "azw", "azw3", "azw4", "fb2", "fbz", "lit", "lrf", "pdb",
        "cbz", "cbr", "cb7", "htmlz", "txtz", "chm", "docx", "odt", "rtf"
    ]
    private static let outputs: [(ext: String, title: String)] = [
        ("epub", "EPUB"),
        ("mobi", "Kindle (MOBI)"),
        ("azw3", "Kindle (AZW3)"),
        ("pdf", "PDF"),
        ("docx", "Word (DOCX)"),
        ("txt", "Văn bản thuần (TXT)"),
        ("fb2", "FictionBook (FB2)")
    ]
    private static let conversionTimeout: TimeInterval = 300

    init(locator: BinaryLocator = BinaryLocator()) {
        self.locator = locator
    }

    func targets(for input: URL) -> [ConversionTarget] {
        let source = input.lowercasedExtension
        guard Self.inputs.contains(source) else { return [] }
        return Self.outputs.filter { $0.ext != source }.map {
            ConversionTarget(id: "\(id).\($0.ext)", title: $0.title, fileExtension: $0.ext, group: .document)
        }
    }

    static func arguments(input: URL, output: URL) -> [String] { [input.path, output.path] }

    /// Percentage from a calibre progress line such as "34% Running transforms", as 0...1.
    static func progressFraction(from line: String) -> Double? {
        guard let percent = line.split(separator: "%", maxSplits: 1).first,
              line.contains("%"), let value = Double(percent.trimmingCharacters(in: .whitespaces)),
              (0...100).contains(value) else { return nil }
        return value / 100
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              Self.inputs.contains(input.lowercasedExtension) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? "")
        }
        let tool = try ConverterWorkspace.requireTool(.ebookConvert, locator: locator)
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let produced = directory.appendingPathComponent("output.\(request.target.fileExtension)")
            try await ConverterWorkspace.run(
                tool, Self.arguments(input: input, output: produced),
                timeout: Self.conversionTimeout,
                onStderrLine: { line in
                    if let fraction = Self.progressFraction(from: line) { progress(fraction * 0.95) }
                })
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }
}
