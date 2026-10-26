import Foundation

/// Knows every converter and answers "what can I turn these files into?".
public struct ConverterRegistry {
    /// Targets that only make sense with enough inputs (targets(for:) is asked per file).
    private static let minimumInputCounts = [PDFConverter.mergeTargetID: 2]

    public let converters: [FileConverter]
    private let locator: BinaryLocator

    public init(converters: [FileConverter], locator: BinaryLocator) {
        self.converters = converters
        self.locator = locator
    }

    public static func standard(locator: BinaryLocator = BinaryLocator()) -> ConverterRegistry {
        // Single wiring point: add new converters to this list. Native converters come
        // first so they win when an external tool offers the same output.
        let converters: [FileConverter] = [
            ImageConverter(),
            ImagesToPDFConverter(),
            PDFConverter(),
            PDFPagesConverter(),
            OCRConverter(),
            SubtitleConverter(),
            LegacyVietnameseConverter(),
            DocxLegacyFontConverter(),
            DocumentConverter(),
            MediaConverter(),
            ArchiveConverter(),
            OfficeConverter(locator: locator),
            FFmpegConverter(locator: locator)
        ]
        return ConverterRegistry(converters: converters, locator: locator)
    }

    public func isAvailable(_ tool: ExternalTool) -> Bool { locator.locate(tool) != nil }

    /// Targets valid for every input, from converters whose tool (if any) is installed.
    public func targets(for inputs: [URL]) -> [ConversionTarget] {
        let available = commonTargets(for: inputs, converters: converters.filter { $0.requiredTool.map(isAvailable) ?? true })
        var seenTitles = Set<String>()
        return available.filter { seenTitles.insert($0.title).inserted }
    }

    /// Tools that are not installed but would unlock targets for these inputs.
    public func missingTools(for inputs: [URL]) -> Set<ExternalTool> {
        Set(converters.compactMap { converter in
            guard let tool = converter.requiredTool, !isAvailable(tool),
                  !commonTargets(for: inputs, converters: [converter]).isEmpty else { return nil }
            return tool
        })
    }

    /// Target ids are "<converterID>.<name>", so the prefix identifies the owner.
    public func converter(for target: ConversionTarget) -> FileConverter? {
        converters.first { target.id.hasPrefix($0.id + ".") }
    }

    private func commonTargets(for inputs: [URL], converters: [FileConverter]) -> [ConversionTarget] {
        guard !inputs.isEmpty else { return [] }
        return converters.flatMap { converter -> [ConversionTarget] in
            let perInput = inputs.map { converter.targets(for: $0) }
            let sharedIDs = perInput.dropFirst().reduce(Set(perInput[0].map(\.id))) { $0.intersection($1.map(\.id)) }
            return perInput[0].filter { sharedIDs.contains($0.id) && inputs.count >= (Self.minimumInputCounts[$0.id] ?? 1) }
        }
    }
}
