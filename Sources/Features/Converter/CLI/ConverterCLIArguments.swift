import Foundation

struct ConverterCLIUsageError: Error, Equatable {
    let message: String
}

struct ConverterCLIConvertOptions: Equatable {
    var files: [String] = []
    var target = ""
    var outputDirectory: String?
    var quality: Int?
    var maxSize: Int?
    var dpi: Int?
    var pages: String?
    var height: Int?
    var quiet = false
}

enum ConverterCLICommand: Equatable {
    case help
    case formats(files: [String])
    case convert(ConverterCLIConvertOptions)
    case installCLI
}

/// Hand-written parser for `xmac <command> …`. Pure, so GUI launches and tests never see it:
/// only exact subcommand names are claimed.
enum ConverterCLIArguments {
    static let subcommands: Set<String> = ["convert", "formats", "install-cli", "--help", "-h", "help"]

    /// `arguments` is the full argv including the executable name. Nil means "not a CLI invocation".
    static func parse(_ arguments: [String]) throws -> ConverterCLICommand? {
        guard arguments.count > 1, subcommands.contains(arguments[1]) else { return nil }
        let rest = Array(arguments.dropFirst(2))
        switch arguments[1] {
        case "convert": return .convert(try parseConvert(rest))
        case "formats":
            let files = try parseFiles(rest)
            return .formats(files: files)
        case "install-cli":
            guard rest.isEmpty else { throw ConverterCLIUsageError(message: "install-cli takes no arguments") }
            return .installCLI
        default: return .help
        }
    }

    private static func parseFiles(_ arguments: [String]) throws -> [String] {
        let files = arguments.filter { $0 != "--" }
        guard !files.isEmpty else { throw ConverterCLIUsageError(message: "no input files") }
        return files
    }

    private static func parseConvert(_ arguments: [String]) throws -> ConverterCLIConvertOptions {
        var options = ConverterCLIConvertOptions()
        var target: String?
        var index = 0
        var optionsEnded = false
        while index < arguments.count {
            var token = arguments[index]
            index += 1
            if optionsEnded || !token.hasPrefix("--") || token == "--" {
                if token == "--", !optionsEnded { optionsEnded = true } else { options.files.append(token) }
                continue
            }
            var inline: String?
            if let equals = token.firstIndex(of: "=") {
                inline = String(token[token.index(after: equals)...])
                token = String(token[..<equals])
            }
            if token == "--quiet" {
                guard inline == nil else { throw ConverterCLIUsageError(message: "--quiet takes no value") }
                options.quiet = true
                continue
            }
            guard valueOptions.contains(token) else { throw ConverterCLIUsageError(message: "unknown option \(token)") }
            let value: String
            if let inline {
                value = inline
            } else if index < arguments.count {
                value = arguments[index]
                index += 1
            } else {
                throw ConverterCLIUsageError(message: "\(token) needs a value")
            }
            try apply(token, value, to: &options, target: &target)
        }
        guard !options.files.isEmpty else { throw ConverterCLIUsageError(message: "no input files") }
        guard let target, !target.isEmpty else { throw ConverterCLIUsageError(message: "missing --to <id|extension>") }
        options.target = target
        return options
    }

    private static let valueOptions: Set<String> = ["--to", "--out", "--quality", "--max-size", "--dpi", "--pages", "--height"]

    private static func apply(
        _ option: String, _ value: String, to options: inout ConverterCLIConvertOptions, target: inout String?
    ) throws {
        switch option {
        case "--to": target = value
        case "--out": options.outputDirectory = value
        case "--pages": options.pages = value
        case "--quality": options.quality = try integer(value, option, in: 0...100)
        case "--max-size": options.maxSize = try integer(value, option, in: 1...100_000)
        case "--dpi": options.dpi = try integer(value, option, in: 1...2400)
        default: options.height = try integer(value, option, in: 1...100_000)
        }
    }

    private static func integer(_ value: String, _ option: String, in range: ClosedRange<Int>) throws -> Int {
        guard let number = Int(value), range.contains(number) else {
            throw ConverterCLIUsageError(message: "\(option) must be a whole number from \(range.lowerBound) to \(range.upperBound)")
        }
        return number
    }
}

extension ConverterCLIConvertOptions {
    /// Flags override the saved preset for the target's group; unset flags keep its value.
    func applying(to base: ConversionPreset) throws -> ConversionPreset {
        var preset = base
        if let quality { preset.imageQuality = Double(quality) / 100 }
        if let maxSize { preset.maxImageDimension = maxSize }
        if let dpi { preset.pdfRenderDPI = Double(dpi) }
        if let height { preset.maxVideoHeight = height }
        if let pages {
            if PageRangeParser.validationMessage(pages) != nil {
                throw ConverterCLIUsageError(message: "invalid --pages \"\(pages)\" (use e.g. \"1-3,5,8-\")")
            }
            preset.pdfPageRange = pages
        }
        return preset
    }
}
