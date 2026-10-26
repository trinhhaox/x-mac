import Foundation

enum ConverterCLIExit {
    static let success: Int32 = 0
    static let someFailed: Int32 = 1
    static let usage: Int32 = 2
    static let interrupted: Int32 = 130
}

/// Headless entry point: `main.swift` calls `runIfRequested` before any AppKit setup.
enum ConverterCLI {
    static let helpText = """
    Usage:
      xmac formats <file>...                 List what the files can be converted to
      xmac convert <file>... --to <id|ext> [options]
      xmac install-cli                       Link xmac into /usr/local/bin (or ~/.local/bin)
      xmac --help

    Convert options:
      --to <id|ext>     Target id (e.g. image.jpg) or output extension / title (e.g. jpg)
      --out <dir>       Output folder (default: next to the first input)
      --quality 0-100   Lossy image quality
      --max-size N      Longest image edge in pixels
      --dpi N           PDF render resolution
      --pages "1-3,5"   Page range for PDF page extraction
      --height N        Video output height
      --quiet           No progress output

    Saved Xmac settings per file type are the defaults; flags override them.
    Exit status: 0 all converted, 1 some failed, 2 usage error,
    130 interrupted (SIGINT), 143 (SIGTERM), 129 (SIGHUP).
    """

    /// Returns normally when argv is not a CLI invocation; otherwise never returns.
    static func runIfRequested(_ arguments: [String]) {
        let command: ConverterCLICommand
        do {
            guard let parsed = try ConverterCLIArguments.parse(arguments) else { return }
            command = parsed
        } catch let error as ConverterCLIUsageError {
            fail(error.message)
            exit(ConverterCLIExit.usage)
        } catch {
            fail("\(error)")
            exit(ConverterCLIExit.usage)
        }
        Task {
            exit(await run(command))
        }
        dispatchMain()
    }

    static func run(_ command: ConverterCLICommand, registry: ConverterRegistry = .standard()) async -> Int32 {
        switch command {
        case .help:
            print(helpText)
            return ConverterCLIExit.success
        case .installCLI:
            return install()
        case .formats(let files):
            return listFormats(files, registry: registry)
        case .convert(let options):
            return await ConverterCLIJobRunner(registry: registry).convert(options)
        }
    }

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("xmac: \(message)\n".utf8))
    }

    private static func install() -> Int32 {
        guard let executable = Bundle.main.executableURL else {
            fail("cannot locate the running executable")
            return ConverterCLIExit.someFailed
        }
        do {
            print(try ConverterCLIInstaller().install(executable: executable))
            return ConverterCLIExit.success
        } catch let error as ConverterCLIUsageError {
            fail(error.message)
        } catch {
            fail(error.localizedDescription)
        }
        return ConverterCLIExit.someFailed
    }

    private static func listFormats(_ paths: [String], registry: ConverterRegistry) -> Int32 {
        let files = paths.map { URL(fileURLWithPath: $0) }
        let missing = paths.filter { !FileManager.default.fileExists(atPath: $0) }
        missing.forEach { fail("no such file: \($0)") }
        guard missing.isEmpty else { return ConverterCLIExit.someFailed }
        let targets = registry.targets(for: files)
        if targets.isEmpty { print("No conversions available for these files.") }
        for target in targets {
            let ext = target.fileExtension.isEmpty ? "(folder)" : ".\(target.fileExtension)"
            print("\(target.id)\t\(ext)\t\(target.title)")
        }
        let tools = registry.missingTools(for: files).map(\.rawValue).sorted()
        if !tools.isEmpty { print("Not installed (would unlock more targets): \(tools.joined(separator: ", "))") }
        return ConverterCLIExit.success
    }
}
