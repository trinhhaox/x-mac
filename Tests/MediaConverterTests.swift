import Testing
import AVFoundation
import Foundation
@testable import Xmac

enum ConverterToolTestSupport {
    static func tempDirectory() throws -> URL {
        try ConverterFixtures.makeTempDirectory()
    }

    static func request(
        _ converter: FileConverter, input: URL, targetID: String, outputIn directory: URL
    ) throws -> ConversionRequest {
        let target = try #require(converter.targets(for: input).first { $0.id == targetID })
        let name = "out" + (target.fileExtension.isEmpty ? "" : ".\(target.fileExtension)")
        return ConversionRequest(
            inputs: [input], target: target, preset: ConversionPreset(),
            outputURL: directory.appendingPathComponent(name)
        )
    }

    /// A short H.264 clip of solid frames.
    static func makeVideo(at url: URL, seconds: Int = 1) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 10) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 20 % 256), CVPixelBufferGetBytesPerRow(pixels) * 64)
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }

    /// One second of 440 Hz mono PCM in WAV.
    static func makeWav(at url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let frames = AVAudioFrameCount(44100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData)[0]
        for index in 0..<Int(frames) { samples[index] = sinf(Float(index) * 2 * .pi * 440 / 44100) * 0.5 }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ])
        try file.write(from: buffer)
    }
}

@Suite struct MediaConverterTests {
    private let converter = MediaConverter()

    @Test func offersVideoAndAudioTargetsByExtension() {
        let video = converter.targets(for: URL(fileURLWithPath: "/x/clip.MOV")).map(\.id)
        #expect(video == ["media.mp4", "media.mov", "media.hevc", "media.720p", "media.m4a"])
        let audio = converter.targets(for: URL(fileURLWithPath: "/x/a.wav")).map(\.id)
        #expect(audio == ["media.m4a"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.m4a")).isEmpty)
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.mkv")).isEmpty)
    }

    @Test func convertsVideoToMOVAndReportsProgress() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("in.mp4")
        try await ConverterToolTestSupport.makeVideo(at: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "media.mov", outputIn: dir)
        let last = LockedBox<Double>(0)
        try await converter.convert(request) { value in last.mutate { $0 = value } }
        #expect(FileManager.default.fileExists(atPath: request.outputURL.path))
        #expect(last.value == 1)
        let tracks = try await AVURLAsset(url: request.outputURL).loadTracks(withMediaType: .video)
        #expect(!tracks.isEmpty)
    }

    @Test func convertsAudioToM4A() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("tone.wav")
        try ConverterToolTestSupport.makeWav(at: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "media.m4a", outputIn: dir)
        try await converter.convert(request) { _ in }
        let duration = try await AVURLAsset(url: request.outputURL).load(.duration).seconds
        #expect(abs(duration - 1) < 0.2)
    }

    @Test func corruptInputThrowsAndLeavesNoOutput() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("bad.mp4")
        try Data("not a video".utf8).write(to: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "media.mp4", outputIn: dir)
        await #expect(throws: (any Error).self) { try await converter.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
    }
}

@Suite struct MediaExportPresetTests {
    private func preset(_ key: String, _ height: Int?) -> String {
        MediaConverter.exportPreset(forKey: key, defaultPreset: AVAssetExportPresetHighestQuality, maxVideoHeight: height)
    }

    @Test func capsMP4AndMOVByHeight() {
        #expect(preset("mp4", nil) == AVAssetExportPresetHighestQuality)
        #expect(preset("mp4", 480) == AVAssetExportPreset640x480)
        #expect(preset("mov", 720) == AVAssetExportPreset1280x720)
        #expect(preset("mp4", 1080) == AVAssetExportPreset1920x1080)
        #expect(preset("mp4", 2160) == AVAssetExportPresetHighestQuality)
    }

    @Test func capsHEVCAndLeavesOtherTargetsAlone() {
        #expect(preset("hevc", 1080) == AVAssetExportPresetHEVC1920x1080)
        #expect(preset("hevc", 2160) == AVAssetExportPresetHighestQuality)
        #expect(preset("m4a", 480) == AVAssetExportPresetHighestQuality)
    }
}
