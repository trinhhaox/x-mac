import Foundation

/// Video/audio conversion through an external ffmpeg binary.
struct FFmpegConverter: FileConverter {
    let id = "ffmpeg"
    let requiredTool: ExternalTool? = .ffmpeg
    let locator: BinaryLocator

    private static let videoInputs: Set<String> = [
        "mkv", "webm", "avi", "flv", "wmv", "mpeg", "mpg", "ts", "m2ts", "ogv", "vob", "mp4", "mov"
    ]
    private static let audioInputs: Set<String> = [
        "flac", "ogg", "opus", "wma", "ape", "wv", "ac3", "mp3", "wav", "m4a", "aac", "amr"
    ]
    private static let videoTargets: [FFmpegFormat] = [.mp4, .webm, .mkv, .gif, .mp3, .m4a]
    private static let audioTargets: [FFmpegFormat] = [.mp3, .m4a, .flac, .ogg, .opus, .wav]

    init(locator: BinaryLocator = BinaryLocator()) {
        self.locator = locator
    }

    func targets(for input: URL) -> [ConversionTarget] {
        let ext = input.lowercasedExtension
        let formats: [FFmpegFormat]
        if Self.videoInputs.contains(ext) {
            formats = Self.videoTargets
        } else if Self.audioInputs.contains(ext) {
            formats = Self.audioTargets
        } else {
            return []
        }
        return formats.filter { $0.rawValue != ext }.map {
            ConversionTarget(id: "\(id).\($0.rawValue)", title: $0.title, fileExtension: $0.rawValue, group: .media)
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              let format = FFmpegFormat(rawValue: request.target.fileExtension) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? request.target.id)
        }
        let ffmpeg = try ConverterWorkspace.requireTool(.ffmpeg, locator: locator)
        let duration = await probeDuration(of: input, ffmpeg: ffmpeg)

        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let produced = directory.appendingPathComponent("output.\(format.rawValue)")
            let arguments = FFmpegArguments.build(
                input: input.path, output: produced.path, format: format, maxHeight: request.preset.maxVideoHeight
            )
            try await ConverterWorkspace.run(ffmpeg, arguments, onStderrLine: { line in
                if let duration, let fraction = FFmpegArguments.progressFraction(line: line, duration: duration) {
                    progress(fraction)
                }
            })
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }

    /// nil (indeterminate progress) when ffprobe is missing or reports nothing usable.
    private func probeDuration(of input: URL, ffmpeg: URL) async -> Double? {
        let sibling = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard let ffprobe = locator.locate(.ffprobe)
            ?? (FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil),
              let result = try? await ConverterWorkspace.run(
                ffprobe, FFmpegArguments.probeArguments(input: input.path), timeout: 30) else { return nil }
        return FFmpegArguments.parseDuration(String(decoding: result.stdout, as: UTF8.self))
    }
}
