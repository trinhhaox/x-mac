import Testing
import Foundation
@testable import Xmac

@Suite struct FFmpegArgumentsTests {
    private func args(_ format: FFmpegFormat, maxHeight: Int? = nil) -> [String] {
        FFmpegArguments.build(input: "/in/a b.mkv", output: "/out/o.\(format.rawValue)", format: format, maxHeight: maxHeight)
    }

    @Test func commonPrefixAndPathsAreSeparateArguments() {
        let result = args(.mp4)
        #expect(Array(result.prefix(7)) == ["-hide_banner", "-progress", "pipe:2", "-nostats", "-y", "-i", "/in/a b.mkv"])
        #expect(result.last == "/out/o.mp4")
    }

    @Test func mp4UsesH264AacFaststart() {
        let result = args(.mp4)
        #expect(result.contains("libx264") && result.contains("aac") && result.contains("+faststart"))
        #expect(!result.contains("-vf"))
    }

    @Test func maxHeightAddsDownscaleFilter() {
        #expect(args(.mp4, maxHeight: 720).contains("scale=-2:min(ih\\,720)"))
        #expect(args(.webm, maxHeight: 480).contains("scale=-2:min(ih\\,480)"))
        #expect(!args(.mp4, maxHeight: 0).contains("-vf"))
    }

    @Test func webmUsesVP9AndOpus() {
        let result = args(.webm)
        #expect(result.contains("libvpx-vp9") && result.contains("libopus"))
    }

    @Test func mkvCopiesStreams() {
        let result = args(.mkv)
        #expect(result.contains("copy") && !result.contains("libx264"))
    }

    @Test func gifUsesTwoPassPaletteCappedAt640() throws {
        let result = args(.gif)
        let graph = try #require(result.firstIndex(of: "-filter_complex").map { result[$0 + 1] })
        #expect(graph.contains("fps=12") && graph.contains("min(640,iw)"))
        #expect(graph.contains("palettegen") && graph.contains("paletteuse"))
        #expect(result.contains("-an"))
    }

    @Test(arguments: [
        (FFmpegFormat.mp3, "libmp3lame"), (.m4a, "aac"), (.flac, "flac"),
        (.ogg, "libvorbis"), (.opus, "libopus"), (.wav, "pcm_s16le")
    ])
    func audioFormatsDropVideoAndPickCodec(format: FFmpegFormat, codec: String) {
        let result = args(format)
        #expect(result.contains("-vn") && result.contains(codec))
    }

    @Test func parsesProgressLines() {
        #expect(FFmpegArguments.progressFraction(line: "out_time_us=2500000", duration: 10) == 0.25)
        #expect(FFmpegArguments.progressFraction(line: "out_time_ms=5000000", duration: 10) == 0.5)
        #expect(FFmpegArguments.progressFraction(line: "out_time_us=99000000", duration: 10) == 1)
        #expect(FFmpegArguments.progressFraction(line: "out_time_us=-5", duration: 10) == 0)
        #expect(FFmpegArguments.progressFraction(line: "out_time_us=N/A", duration: 10) == nil)
        #expect(FFmpegArguments.progressFraction(line: "frame=12", duration: 10) == nil)
        #expect(FFmpegArguments.progressFraction(line: "out_time_us=100", duration: 0) == nil)
    }

    @Test func parsesProbeDuration() {
        #expect(FFmpegArguments.parseDuration("12.345\n") == 12.345)
        #expect(FFmpegArguments.parseDuration("N/A\n") == nil)
        #expect(FFmpegArguments.parseDuration("") == nil)
        #expect(FFmpegArguments.parseDuration("0.000000") == nil)
    }
}

@Suite struct FFmpegConverterTests {
    private let converter = FFmpegConverter()

    @Test func offersTargetsByInputKind() {
        let video = converter.targets(for: URL(fileURLWithPath: "/x/a.mkv")).map(\.id)
        #expect(video == ["ffmpeg.mp4", "ffmpeg.webm", "ffmpeg.gif", "ffmpeg.mp3", "ffmpeg.m4a"])
        let audio = converter.targets(for: URL(fileURLWithPath: "/x/a.flac")).map(\.id)
        #expect(audio == ["ffmpeg.mp3", "ffmpeg.m4a", "ffmpeg.ogg", "ffmpeg.opus", "ffmpeg.wav"])
        #expect(!converter.targets(for: URL(fileURLWithPath: "/x/a.mp3")).map(\.id).contains("ffmpeg.mp3"))
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.txt")).isEmpty)
        #expect(converter.requiredTool == .ffmpeg)
    }

    @Test func missingBinaryThrowsToolMissing() async throws {
        let suite = "FFmpegConverterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/nonexistent/ffmpeg", forKey: ExternalTool.ffmpeg.overrideDefaultsKey)
        let missing = FFmpegConverter(locator: BinaryLocator(defaults: defaults))
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = try ConverterToolTestSupport.request(
            missing, input: dir.appendingPathComponent("a.mkv"), targetID: "ffmpeg.mp4", outputIn: dir)
        await #expect(throws: ConversionError.toolMissing(.ffmpeg)) { try await missing.convert(request) { _ in } }
    }

    @Test(.enabled(if: BinaryLocator().locate(.ffmpeg) != nil))
    func convertsWavToFlacAndMp3() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("tone.wav")
        try ConverterToolTestSupport.makeWav(at: source)
        for id in ["ffmpeg.flac", "ffmpeg.mp3"] {
            let request = try ConverterToolTestSupport.request(converter, input: source, targetID: id, outputIn: dir)
            let last = LockedBox<Double>(0)
            try await converter.convert(request) { value in last.mutate { $0 = value } }
            let size = try FileManager.default.attributesOfItem(atPath: request.outputURL.path)[.size] as? Int ?? 0
            #expect(size > 0)
            #expect(last.value == 1)
        }
    }

    @Test(.enabled(if: BinaryLocator().locate(.ffmpeg) != nil))
    func convertsMp4ToGifAndWebm() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("in.mp4")
        try await ConverterToolTestSupport.makeVideo(at: source)
        for id in ["ffmpeg.gif", "ffmpeg.webm"] {
            let request = try ConverterToolTestSupport.request(converter, input: source, targetID: id, outputIn: dir)
            try await converter.convert(request) { _ in }
            #expect(FileManager.default.fileExists(atPath: request.outputURL.path))
        }
    }

    @Test(.enabled(if: BinaryLocator().locate(.ffmpeg) != nil))
    func corruptInputThrowsAndLeavesNoOutput() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("bad.mkv")
        try Data("garbage".utf8).write(to: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "ffmpeg.mp4", outputIn: dir)
        await #expect(throws: ConversionError.self) { try await converter.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
    }
}
