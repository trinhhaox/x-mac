import Foundation

struct SubtitleCue: Equatable {
    var start: Double
    var end: Double
    var text: String
}

enum SubtitleFormats {
    private static let timePattern = try? NSRegularExpression(
        pattern: #"(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})"#
    )

    static func parse(_ text: String, format: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return format == "ass" ? parseASS(normalized) : parseTimed(normalized)
    }

    static func serialize(_ cues: [SubtitleCue], format: String) -> String {
        switch format {
        case "vtt": return "WEBVTT\n\n" + cues.map { "\(stamp($0.start, ".")) --> \(stamp($0.end, "."))\n\($0.text)\n" }.joined(separator: "\n")
        case "ass": return assHeader + cues.map(assLine).joined(separator: "\n") + "\n"
        default:
            return cues.enumerated().map { "\($0.offset + 1)\n\(stamp($0.element.start, ",")) --> \(stamp($0.element.end, ","))\n\($0.element.text)\n" }
                .joined(separator: "\n")
        }
    }

    // MARK: SRT / VTT

    private static func parseTimed(_ text: String) -> [SubtitleCue] {
        text.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(in: parts[0]), let end = seconds(in: parts[1]) else { return nil }
            let body = lines[(timeIndex + 1)...].joined(separator: "\n")
            return body.isEmpty ? nil : SubtitleCue(start: start, end: end, text: body)
        }
    }

    // MARK: ASS

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var fields = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        var cues: [SubtitleCue] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("Format:"), line.contains("Start") {
                fields = line.dropFirst("Format:".count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            } else if line.hasPrefix("Dialogue:") {
                let values = line.dropFirst("Dialogue:".count).split(separator: ",", maxSplits: fields.count - 1, omittingEmptySubsequences: false)
                guard values.count == fields.count,
                      let startIndex = fields.firstIndex(of: "start"), let endIndex = fields.firstIndex(of: "end"),
                      let textIndex = fields.firstIndex(of: "text"),
                      let start = seconds(in: String(values[startIndex])), let end = seconds(in: String(values[endIndex])) else { continue }
                let cleaned = String(values[textIndex])
                    .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\N", with: "\n")
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: cleaned)) }
            }
        }
        return cues
    }

    private static let assHeader = """
    [Script Info]
    ScriptType: v4.00+

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

    """

    private static func assLine(_ cue: SubtitleCue) -> String {
        let plain = cue.text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: "\\N")
        return "Dialogue: 0,\(assStamp(cue.start)),\(assStamp(cue.end)),Default,,0,0,0,,\(plain)"
    }

    // MARK: Timestamps

    private static func seconds(in text: String) -> Double? {
        guard let regex = timePattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
        guard let minutes = group(2).flatMap(Double.init), let secs = group(3).flatMap(Double.init),
              let fraction = group(4) else { return nil }
        let hours = group(1).flatMap(Double.init) ?? 0
        let millis = Double(fraction.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        return hours * 3600 + minutes * 60 + secs + millis / 1000
    }

    private static func stamp(_ value: Double, _ separator: String) -> String {
        let total = Int((max(0, value) * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, separator, total % 1000)
    }

    private static func assStamp(_ value: Double) -> String {
        let total = Int((max(0, value) * 100).rounded())
        return String(format: "%d:%02d:%02d.%02d", total / 360_000, total / 6000 % 60, total / 100 % 60, total % 100)
    }
}
