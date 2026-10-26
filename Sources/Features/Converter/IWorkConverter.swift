import AppKit

/// Pages / Numbers / Keynote export through the installed app, driven by AppleScript over `osascript`.
/// Paths travel as `on run argv` arguments, never inside the script text.
struct IWorkConverter: FileConverter {
    struct App: Equatable {
        let name: String
        let bundleID: String
        /// Output extension to the AppleScript export-format constant.
        let formats: [(ext: String, constant: String)]

        static func == (lhs: App, rhs: App) -> Bool { lhs.bundleID == rhs.bundleID }
    }

    let id = "iwork"
    let requiredTool: ExternalTool? = nil
    /// Decides whether an app is installed; injectable so tests do not depend on the machine.
    let isInstalled: (String) -> Bool

    static let apps: [String: App] = [
        "pages": App(name: "Pages", bundleID: "com.apple.iWork.Pages", formats: [
            ("pdf", "PDF"), ("docx", "Microsoft Word"), ("rtf", "formatted text"), ("txt", "unformatted text"), ("epub", "EPUB")]),
        "numbers": App(name: "Numbers", bundleID: "com.apple.iWork.Numbers", formats: [
            ("pdf", "PDF"), ("xlsx", "Microsoft Excel"), ("csv", "CSV")]),
        "key": App(name: "Keynote", bundleID: "com.apple.iWork.Keynote", formats: [
            ("pdf", "PDF"), ("pptx", "Microsoft PowerPoint")])
    ]
    private static let titles = [
        "pdf": "PDF", "docx": "Word (DOCX)", "xlsx": "Excel (XLSX)", "pptx": "PowerPoint (PPTX)",
        "rtf": "RTF", "txt": "Văn bản thuần (TXT)", "epub": "EPUB", "csv": "CSV"
    ]
    private static let scriptTimeoutSeconds = 170
    private static let conversionTimeout: TimeInterval = 180
    private static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    init(isInstalled: @escaping (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
        self.isInstalled = isInstalled
    }

    func targets(for input: URL) -> [ConversionTarget] {
        guard let app = Self.apps[input.lowercasedExtension], isInstalled(app.bundleID) else { return [] }
        return app.formats.compactMap { format in
            Self.titles[format.ext].map {
                ConversionTarget(id: "\(id).\(format.ext)", title: $0, fileExtension: format.ext, group: .office)
            }
        }
    }

    /// argv: input path, output path, "1" when we launched the app. An already-open document is exported
    /// and left open; only documents the script opened are closed, and the app quits only if we launched
    /// it and nothing else is open.
    static func script(for app: App, exportConstant: String) -> String {
        """
        on run argv
            set inPath to item 1 of argv
            set outPath to item 2 of argv
            set weLaunched to (item 3 of argv) is "1"
            with timeout of \(scriptTimeoutSeconds) seconds
                tell application id "\(app.bundleID)"
                    set theDoc to missing value
                    set wasOpen to false
                    try
                        repeat with i from 1 to (count of documents)
                            try
                                if (POSIX path of ((file of document i) as alias)) is inPath then
                                    set theDoc to document i
                                    set wasOpen to true
                                    exit repeat
                                end if
                            end try
                        end repeat
                        if theDoc is missing value then set theDoc to open (POSIX file inPath)
                        export theDoc to (POSIX file outPath) as \(exportConstant)
                        if not wasOpen then close theDoc saving no
                        if weLaunched and (count of documents) is 0 then quit saving no
                    on error errText number errNum
                        try
                            if theDoc is not missing value and not wasOpen then close theDoc saving no
                        end try
                        try
                            if weLaunched and (count of documents) is 0 then quit saving no
                        end try
                        error errText number errNum
                    end try
                end tell
            end timeout
        end run
        """
    }

    static func arguments(script: String, input: URL, output: URL, quitAfter: Bool) -> [String] {
        ["-e", script, input.path, output.path, quitAfter ? "1" : "0"]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              let app = Self.apps[input.lowercasedExtension],
              let format = app.formats.first(where: { $0.ext == request.target.fileExtension }) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? "")
        }
        guard isInstalled(app.bundleID) else { throw ConversionError.failed(L10n.format("Chưa cài %@", app.name)) }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
        let script = Self.script(for: app, exportConstant: format.constant)

        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let exported = directory.appendingPathComponent("export.\(format.ext)")
            do {
                try await ConverterWorkspace.run(
                    Self.osascript,
                    Self.arguments(script: script, input: input.resolvingSymlinksInPath(), output: exported, quitAfter: !wasRunning),
                    timeout: Self.conversionTimeout)
            } catch ConversionError.failed(let message) where message.contains("-1743") {
                throw ConversionError.failed(L10n.format("Chưa cấp quyền Tự động hoá cho %@ trong Cài đặt hệ thống", app.name))
            } catch where !wasRunning && (error is CancellationError || error as? ConversionError == .failed("Timed out")) {
                NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
                throw error
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: exported.path, isDirectory: &isDirectory), isDirectory.boolValue {
                throw ConversionError.failed(L10n.text("Tệp xuất ra gồm nhiều tệp, chưa hỗ trợ"))
            }
            try ConverterWorkspace.publish(exported, to: request.outputURL)
        }
        progress(1)
    }
}
