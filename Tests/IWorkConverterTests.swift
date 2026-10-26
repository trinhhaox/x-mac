import AppKit
import Foundation
import Testing
@testable import Xmac

@Suite struct IWorkConverterTests {
    private let all = IWorkConverter(isInstalled: { _ in true })
    private let none = IWorkConverter(isInstalled: { _ in false })

    private func ids(_ converter: IWorkConverter, _ name: String) -> [String] {
        converter.targets(for: URL(fileURLWithPath: "/x/\(name)")).map(\.id)
    }

    @Test func offersTargetsPerInstalledApp() {
        #expect(ids(all, "a.pages") == ["iwork.pdf", "iwork.docx", "iwork.rtf", "iwork.txt", "iwork.epub"])
        #expect(ids(all, "a.NUMBERS") == ["iwork.pdf", "iwork.xlsx", "iwork.csv"])
        #expect(ids(all, "a.key") == ["iwork.pdf", "iwork.pptx"])
        #expect(ids(all, "a.docx").isEmpty)
        #expect(all.requiredTool == nil)
    }

    @Test func offersNothingWhenAppMissing() {
        #expect(ids(none, "a.pages").isEmpty)
        let onlyKeynote = IWorkConverter(isInstalled: { $0 == "com.apple.iWork.Keynote" })
        #expect(ids(onlyKeynote, "a.key") == ["iwork.pdf", "iwork.pptx"])
        #expect(ids(onlyKeynote, "a.numbers").isEmpty)
    }

    @Test func targetsUseOfficeGroupSoQueueRunsThemSerially() {
        let groups = all.targets(for: URL(fileURLWithPath: "/x/a.pages")).map(\.group)
        #expect(Set(groups) == [.office])
    }

    @Test func scriptKeepsPathsOutOfScriptText() throws {
        let app = try #require(IWorkConverter.apps["pages"])
        let script = IWorkConverter.script(for: app, exportConstant: "PDF")
        #expect(script.contains("on run argv"))
        #expect(script.contains("application id \"com.apple.iWork.Pages\""))
        #expect(script.contains("as PDF"))
        let input = URL(fileURLWithPath: "/tmp/it's \"odd\".pages")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let arguments = IWorkConverter.arguments(script: script, input: input, output: output, quitAfter: true)
        #expect(arguments == ["-e", script, input.path, output.path, "1"])
        #expect(!script.contains("odd"))
    }

    @Test func scriptUsesDictionaryConstantsAndNeverClosesOrQuitsUnconditionally() throws {
        let formats = IWorkConverter.apps.values.flatMap { $0.formats.map(\.constant) }
        #expect(Set(formats) == ["PDF", "Microsoft Word", "formatted text", "unformatted text", "EPUB",
                                 "Microsoft Excel", "CSV", "Microsoft PowerPoint"])
        let script = IWorkConverter.script(for: try #require(IWorkConverter.apps["key"]), exportConstant: "PDF")
        #expect(script.contains("with timeout of 170 seconds"))
        #expect(script.contains("if not wasOpen then close theDoc saving no"))
        #expect(script.contains("if weLaunched and (count of documents) is 0 then quit saving no"))
        #expect(!script.contains("if shouldQuit"))
    }

    @Test func rejectsUnsupportedFormatForInput() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = ConversionTarget(id: "iwork.csv", title: "CSV", fileExtension: "csv", group: .office)
        let request = ConversionRequest(
            inputs: [dir.appendingPathComponent("a.pages")], target: target, preset: ConversionPreset(),
            outputURL: dir.appendingPathComponent("out.csv"))
        await #expect(throws: ConversionError.unsupportedInput("a.pages")) { try await all.convert(request) { _ in } }
    }

    @Test(.enabled(if: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") != nil))
    func exportsPagesDocumentToPdf() async throws {
        // Needs a real .pages file; skipped unless Pages is installed. Automation denial (-1743) is not a failure.
        let converter = IWorkConverter()
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("blank.pages")
        let create = """
        tell application "Pages"
            set d to make new document
            save d in POSIX file "\(source.path)"
            close d saving no
        end tell
        """
        _ = try? await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", create], timeout: 60)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "iwork.pdf", outputIn: dir)
        do {
            try await converter.convert(request) { _ in }
            #expect(FileManager.default.fileExists(atPath: request.outputURL.path))
        } catch ConversionError.failed(let message) where message.contains("Tự động hoá") {
            return
        }
    }
}
