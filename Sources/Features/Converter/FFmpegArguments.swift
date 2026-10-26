import Foundation

enum FFmpegFormat: String, CaseIterable {
    case mp4, webm, mkv, gif, mp3, m4a, flac, ogg, opus, wav

    var title: String {
        switch self {
        case .mp4: return "MP4 (H.264)"
        case .webm: return "WebM (VP9)"
        case .mkv: return "MKV"
        case .gif: return "GIF động"
        case .mp3: return "MP3"
        case .m4a: return "M4A (AAC)"
        case .flac: return "FLAC"
        case .ogg: return "OGG (Vorbis)"
        case .opus: return "OPUS"
        case .wav: return "WAV"
        }
    }
}

/// Pure command-line construction and progress parsing for ffmpeg.
enum FFmpegArguments {
    static func build(input: String, output: String, format: FFmpegFormat, maxHeight: Int? = nil) -> [String] {
        ["-hide_banner", "-progress", "pipe:2", "-nostats", "-y", "-i", input]
            + codecArguments(for: format, maxHeight: maxHeight)
            + [output]
    }

    private static func codecArguments(for format: FFmpegFormat, maxHeight: Int?) -> [String] {
        switch format {
        case .mp4:
            return ["-map", "0:v:0", "-map", "0:a:0?"] + scale(maxHeight)
                + ["-c:v", "libx264", "-crf", "23", "-pix_fmt", "yuv420p",
                   "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .webm:
            return ["-map", "0:v:0", "-map", "0:a:0?"] + scale(maxHeight)
                + ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1",
                   "-c:a", "libopus", "-b:a", "128k"]
        case .mkv:
            return ["-map", "0:v", "-map", "0:a?", "-c", "copy"]
        case .gif:
            return ["-an", "-filter_complex",
                    "[0:v]fps=12,scale=w='min(640,iw)':h=-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                    "-loop", "0"]
        case .mp3: return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a: return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .flac: return ["-vn", "-c:a", "flac"]
        case .ogg: return ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case .opus: return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case .wav: return ["-vn", "-c:a", "pcm_s16le"]
        }
    }

    /// Downscale only; `-2` keeps the width even for H.264/VP9.
    private static func scale(_ maxHeight: Int?) -> [String] {
        guard let maxHeight, maxHeight > 0 else { return [] }
        return ["-vf", "scale=-2:min(ih\\,\(maxHeight))"]
    }

    static func probeArguments(input: String) -> [String] {
        ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", input]
    }

    static func parseDuration(_ output: String) -> Double? {
        guard let value = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Reads `out_time_us=` / `out_time_ms=` (both microseconds in ffmpeg) against the total duration in seconds.
    static func progressFraction(line: String, duration: Double) -> Double? {
        guard duration > 0 else { return nil }
        for key in ["out_time_us=", "out_time_ms="] where line.hasPrefix(key) {
            guard let micros = Double(line.dropFirst(key.count)) else { return nil }
            return min(max(micros / 1_000_000 / duration, 0), 1)
        }
        return nil
    }
}
