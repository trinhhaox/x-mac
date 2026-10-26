import Foundation

/// LibreOffice (`soffice --headless`) conversions: office files to PDF and between MS / OpenDocument formats.
struct OfficeConverter: FileConverter {
    let id = "office"
    let requiredTool: ExternalTool? = .soffice
    let locator: BinaryLocator

    private static let titles: [String: String] = [
        "pdf": "PDF",
        "docx": "Word (DOCX)", "doc": "Word 97-2003 (DOC)",
        "xlsx": "Excel (XLSX)", "xls": "Excel 97-2003 (XLS)",
        "pptx": "PowerPoint (PPTX)", "ppt": "PowerPoint 97-2003 (PPT)"
    ]
    /// Extra targets per input; every input also gets PDF.
    private static let extraTargets: [String: [String]] = [
        "doc": ["docx"], "docx": ["doc"], "odt": ["docx"], "rtf": ["docx"],
        "xls": ["xlsx"], "xlsx": ["xls"], "ods": ["xlsx"], "csv": ["xlsx"],
        "ppt": ["pptx"], "pptx": ["ppt"], "odp": ["pptx"],
        "pages": [], "numbers": [], "key": []
    ]
    private static let conversionTimeout: TimeInterval = 180

    init(locator: BinaryLocator = BinaryLocator()) {
        self.locator = locator
    }

    func targets(for input: URL) -> [ConversionTarget] {
        guard let extras = Self.extraTargets[input.lowercasedExtension] else { return [] }
        return (["pdf"] + extras).compactMap { ext in
            Self.titles[ext].map { ConversionTarget(id: "\(id).\(ext)", title: $0, fileExtension: ext, group: .office) }
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              Self.extraTargets[input.lowercasedExtension] != nil else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? "")
        }
        let soffice = try ConverterWorkspace.requireTool(.soffice, locator: locator)
        let format = request.target.fileExtension

        // The queue runs soffice jobs one at a time; each run uses a private profile.
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let profile = directory.appendingPathComponent("profile", isDirectory: true)
            let outDirectory = directory.appendingPathComponent("out", isDirectory: true)
            try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
            try await ConverterWorkspace.run(soffice, [
                "--headless", "--norestore",
                "-env:UserInstallation=\(profile.absoluteString)",
                "--convert-to", format,
                "--outdir", outDirectory.path,
                input.path
            ], timeout: Self.conversionTimeout)
            let produced = try FileManager.default.contentsOfDirectory(at: outDirectory, includingPropertiesForKeys: nil)
                .first { $0.lowercasedExtension == format }
            guard let produced else { throw ConversionError.failed("LibreOffice produced no output") }
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }
}
