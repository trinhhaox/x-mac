import Foundation

/// ZIP compression and archive extraction with the system's ditto / tar / zipinfo.
struct ArchiveConverter: FileConverter {
    let id = "archive"
    let requiredTool: ExternalTool? = nil

    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private static let tar = URL(fileURLWithPath: "/usr/bin/tar")
    private static let zipinfo = URL(fileURLWithPath: "/usr/bin/zipinfo")
    private static let tarSuffixes = [".tar", ".tgz", ".tar.gz", ".tbz2", ".tar.bz2", ".txz", ".tar.xz", ".7z", ".iso", ".cab", ".xar"]

    private static let zipTarget = ConversionTarget(
        id: "archive.zip", title: "Nén ZIP", fileExtension: "zip", group: .archive, combinesInputs: true)
    private static let extractTarget = ConversionTarget(
        id: "archive.extract", title: "Giải nén", fileExtension: "", group: .archive)

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        Self.isExtractable(input) ? [Self.extractTarget, Self.zipTarget] : [Self.zipTarget]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard !request.inputs.isEmpty else { throw ConversionError.unsupportedInput("") }
        switch request.target.id {
        case Self.zipTarget.id: try await compress(request)
        case Self.extractTarget.id: try await extract(request)
        default: throw ConversionError.unsupportedInput(request.target.id)
        }
        progress(1)
    }

    private static func isExtractable(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".zip") || tarSuffixes.contains { name.hasSuffix($0) }
    }

    // MARK: Compress

    private func compress(_ request: ConversionRequest) async throws {
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let produced = directory.appendingPathComponent("output.zip")
            let flags = ["-c", "-k", "--sequesterRsrc"]
            if request.inputs.count == 1, let only = request.inputs.first {
                try await ConverterWorkspace.run(Self.ditto, flags + ["--keepParent", only.path, produced.path])
            } else {
                // ditto accepts one source only, so merge inputs into a staging folder (APFS clones, no data copy).
                let staging = try Self.stage(request.inputs, in: directory)
                try await ConverterWorkspace.run(Self.ditto, flags + [staging.path, produced.path])
            }
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
    }

    private static func stage(_ inputs: [URL], in directory: URL) throws -> URL {
        let staging = directory.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var used = Set<String>()
        for input in inputs {
            try Task.checkCancellation()
            let name = uniqueName(input.lastPathComponent, used: &used)
            try FileManager.default.copyItem(at: input, to: staging.appendingPathComponent(name))
        }
        return staging
    }

    private static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        var candidate = name
        var counter = 1
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while !used.insert(candidate).inserted {
            counter += 1
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        }
        return candidate
    }

    // MARK: Extract

    private func extract(_ request: ConversionRequest) async throws {
        guard request.inputs.count == 1, let input = request.inputs.first, Self.isExtractable(input) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? "")
        }
        let isZip = input.lowercasedExtension == "zip"
        let listing = try await ConverterWorkspace.run(
            isZip ? Self.zipinfo : Self.tar, isZip ? ["-1", input.path] : ["-tf", input.path], timeout: 120)
        let unsafe = Self.unsafeEntries(in: String(decoding: listing.stdout, as: UTF8.self))
        guard unsafe.isEmpty else {
            throw ConversionError.failed("Unsafe archive entry: \(unsafe[0])")
        }
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let extracted = directory.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            if isZip {
                try await ConverterWorkspace.run(Self.ditto, ["-x", "-k", input.path, extracted.path])
            } else {
                try await ConverterWorkspace.run(Self.tar, ["-xf", input.path, "-C", extracted.path])
            }
            try ConverterWorkspace.publish(extracted, to: request.outputURL)
        }
    }

    /// Entries that are absolute or climb out of the destination with `..`.
    static func unsafeEntries(in listing: String) -> [String] {
        listing.split(whereSeparator: \.isNewline).map(String.init).filter { entry in
            entry.hasPrefix("/") || entry.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        }
    }
}
