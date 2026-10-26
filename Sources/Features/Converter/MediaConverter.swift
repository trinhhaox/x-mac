import AVFoundation
import Foundation

/// Native audio/video conversion through AVAssetExportSession.
struct MediaConverter: FileConverter {
    let id = "media"
    let requiredTool: ExternalTool? = nil

    private struct Spec {
        let key: String
        let title: String
        let fileExtension: String
        let preset: String
        let fileType: AVFileType
        let videoOnly: Bool
    }

    private static let videoInputs: Set<String> = ["mov", "mp4", "m4v", "3gp"]
    private static let audioInputs: Set<String> = ["m4a", "mp3", "wav", "aiff", "caf"]
    private static let specs: [Spec] = [
        Spec(key: "mp4", title: "MP4 (H.264)", fileExtension: "mp4",
             preset: AVAssetExportPresetHighestQuality, fileType: .mp4, videoOnly: true),
        Spec(key: "mov", title: "MOV", fileExtension: "mov",
             preset: AVAssetExportPresetHighestQuality, fileType: .mov, videoOnly: true),
        Spec(key: "hevc", title: "MP4 (HEVC)", fileExtension: "mp4",
             preset: AVAssetExportPresetHEVCHighestQuality, fileType: .mp4, videoOnly: true),
        Spec(key: "720p", title: "MP4 720p", fileExtension: "mp4",
             preset: AVAssetExportPreset1280x720, fileType: .mp4, videoOnly: true),
        Spec(key: "m4a", title: "M4A (AAC)", fileExtension: "m4a",
             preset: AVAssetExportPresetAppleM4A, fileType: .m4a, videoOnly: false)
    ]
    private static let pollInterval: UInt64 = 200_000_000

    init() {}

    /// Offered by extension only; incompatible presets fail at convert time so listing never loads media.
    func targets(for input: URL) -> [ConversionTarget] {
        let ext = input.lowercasedExtension
        let isVideo = Self.videoInputs.contains(ext)
        guard isVideo || Self.audioInputs.contains(ext) else { return [] }
        return Self.specs
            .filter { isVideo || (!$0.videoOnly && $0.fileExtension != ext) }
            .map { ConversionTarget(id: "\(id).\($0.key)", title: $0.title, fileExtension: $0.fileExtension, group: .media) }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              let spec = Self.specs.first(where: { "\(id).\($0.key)" == request.target.id }) else {
            throw ConversionError.unsupportedInput(request.inputs.first?.lastPathComponent ?? request.target.id)
        }
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let produced = directory.appendingPathComponent("output.\(spec.fileExtension)")
            let preset = Self.exportPreset(for: spec, maxVideoHeight: request.preset.maxVideoHeight)
            try await Self.export(input, to: produced, spec: spec, presetName: preset, progress: progress)
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }

    /// Applies the user's height cap to the "best quality" MP4/MOV/HEVC targets; other targets keep their preset.
    static func exportPreset(forKey key: String, defaultPreset: String, maxVideoHeight: Int?) -> String {
        guard let height = maxVideoHeight, height > 0 else { return defaultPreset }
        switch key {
        case "mp4", "mov":
            if height <= 480 { return AVAssetExportPreset640x480 }
            if height <= 720 { return AVAssetExportPreset1280x720 }
            if height <= 1080 { return AVAssetExportPreset1920x1080 }
        case "hevc":
            if height <= 1080 { return AVAssetExportPresetHEVC1920x1080 }
        default: break
        }
        return defaultPreset
    }

    private static func exportPreset(for spec: Spec, maxVideoHeight: Int?) -> String {
        exportPreset(forKey: spec.key, defaultPreset: spec.preset, maxVideoHeight: maxVideoHeight)
    }

    private static func export(
        _ input: URL, to output: URL, spec: Spec, presetName: String, progress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ConversionError.failed("Export preset unavailable: \(presetName)")
        }
        session.outputURL = output
        session.outputFileType = spec.fileType
        session.shouldOptimizeForNetworkUse = true
        try Task.checkCancellation()

        let box = SessionBox(session)
        let poller = Task {
            while !Task.isCancelled {
                progress(Double(box.session.progress))
                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
        defer { poller.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                box.session.exportAsynchronously {
                    switch box.session.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: ConversionError.failed(
                            box.session.error?.localizedDescription ?? "Export failed"))
                    }
                }
            }
        } onCancel: {
            box.session.cancelExport()
        }
    }
}

/// AVAssetExportSession is documented as safe to poll and cancel from other threads.
private final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
