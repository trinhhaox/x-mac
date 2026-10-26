import Testing
@testable import Xmac

@Suite struct ConverterCLIArgumentsTests {
    private func parse(_ args: String...) throws -> ConverterCLICommand? {
        try ConverterCLIArguments.parse(["xmac"] + args)
    }

    @Test func guiLaunchesAreNotClaimed() throws {
        #expect(try ConverterCLIArguments.parse(["Xmac"]) == nil)
        #expect(try parse("-psn_0_12345") == nil)
        #expect(try parse("-NSDocumentRevisionsDebugMode", "YES") == nil)
        #expect(try parse("converter") == nil)
    }

    @Test func parsesFullConvertCommand() throws {
        let command = try parse("convert", "a.png", "--to", "jpg", "b.png", "--out=/tmp/o", "--quality", "70",
                                "--max-size", "1024", "--dpi", "200", "--pages", "1-3,5", "--height", "720", "--quiet")
        guard case .convert(let options) = command else { Issue.record("not convert"); return }
        #expect(options.files == ["a.png", "b.png"])
        #expect(options.target == "jpg")
        #expect(options.outputDirectory == "/tmp/o")
        #expect(options.quality == 70 && options.maxSize == 1024 && options.dpi == 200 && options.height == 720)
        #expect(options.pages == "1-3,5")
        #expect(options.quiet)
    }

    @Test func doubleDashEndsOptions() throws {
        let command = try parse("convert", "--to", "png", "--", "--weird.jpg")
        guard case .convert(let options) = command else { Issue.record("not convert"); return }
        #expect(options.files == ["--weird.jpg"])
    }

    @Test func parsesOtherCommands() throws {
        #expect(try parse("formats", "a.png", "b.pdf") == .formats(files: ["a.png", "b.pdf"]))
        #expect(try parse("--help") == .help)
        #expect(try parse("-h") == .help)
        #expect(try parse("install-cli") == .installCLI)
    }

    @Test(arguments: [
        ["convert", "a.png"],
        ["convert", "--to", "jpg"],
        ["convert", "a.png", "--to"],
        ["convert", "a.png", "--to", "jpg", "--quality", "101"],
        ["convert", "a.png", "--to", "jpg", "--quality", "abc"],
        ["convert", "a.png", "--to", "jpg", "--dpi", "0"],
        ["convert", "a.png", "--to", "jpg", "--bogus", "1"],
        ["convert", "a.png", "--to", "jpg", "--quiet=1"],
        ["formats"],
        ["install-cli", "extra"]
    ])
    func rejectsBadUsage(args: [String]) {
        #expect(throws: ConverterCLIUsageError.self) { try ConverterCLIArguments.parse(["xmac"] + args) }
    }

    @Test func flagsOverrideSavedPreset() throws {
        var options = ConverterCLIConvertOptions()
        options.quality = 50
        options.height = 480
        options.pages = "2-"
        var base = ConversionPreset()
        base.maxImageDimension = 800
        let preset = try options.applying(to: base)
        #expect(preset.imageQuality == 0.5)
        #expect(preset.maxVideoHeight == 480)
        #expect(preset.pdfPageRange == "2-")
        #expect(preset.maxImageDimension == 800)
    }

    @Test func invalidPagesAreUsageErrors() {
        var options = ConverterCLIConvertOptions()
        options.pages = "x-y"
        #expect(throws: ConverterCLIUsageError.self) { try options.applying(to: ConversionPreset()) }
    }
}
