import Foundation

/// DOCX → DOCX: text typed in legacy ".Vn*" (TCVN3) or "VNI-*" fonts becomes real Unicode.
struct DocxLegacyFontConverter: FileConverter {
    let id = "vn-legacy-docx"
    let requiredTool: ExternalTool? = nil

    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private static let docxTarget = ConversionTarget(
        id: "vn-legacy-docx.docx", title: "DOCX Unicode (sửa phông VNI/TCVN3)", fileExtension: "docx", group: .document)

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        input.lowercasedExtension == "docx" ? [Self.docxTarget] : []
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              input.lowercasedExtension == "docx", request.target.id == Self.docxTarget.id else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? request.target.id)
        }
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let package = directory.appendingPathComponent("package", isDirectory: true)
            try await ConverterWorkspace.run(Self.ditto, ["-x", "-k", input.path, package.path], timeout: 120)
            progress(0.3)
            let changes = try await BlockingWork.run { check in
                try LegacyVietnameseDocxRewriter.rewrite(package: package, checkCancellation: check)
            }
            guard changes > 0 else {
                throw ConversionError.unsupportedInput(L10n.text("Không tìm thấy phông VNI/TCVN3 trong tệp"))
            }
            progress(0.7)
            let produced = directory.appendingPathComponent("output.docx")
            // Without --keepParent ditto stores the folder's contents at the zip root, as OPC requires.
            try await ConverterWorkspace.run(Self.ditto, ["-c", "-k", "--norsrc", package.path, produced.path], timeout: 120)
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }
}
