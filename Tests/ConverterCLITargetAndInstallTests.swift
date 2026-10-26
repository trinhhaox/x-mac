import Foundation
import Testing
@testable import Xmac

@Suite struct ConverterCLITargetAndInstallTests {
    private let targets = [
        ConversionTarget(id: "image.jpg", title: "JPEG", fileExtension: "jpg", group: .image),
        ConversionTarget(id: "image.png", title: "PNG", fileExtension: "png", group: .image),
        ConversionTarget(id: "pdf.png", title: "Ảnh PNG", fileExtension: "png", group: .pdf),
        ConversionTarget(id: "archive.extract", title: "Giải nén", fileExtension: "", group: .archive)
    ]

    @Test func resolvesByIdExtensionAndTitle() throws {
        #expect(try ConverterCLITargetResolver.resolve("pdf.png", among: targets).id == "pdf.png")
        #expect(try ConverterCLITargetResolver.resolve(".JPG", among: targets).id == "image.jpg")
        #expect(try ConverterCLITargetResolver.resolve("jpeg", among: targets).id == "image.jpg")
    }

    @Test func ambiguousAndUnknownAreErrors() {
        #expect(throws: ConverterCLIUsageError.self) { try ConverterCLITargetResolver.resolve("png", among: targets) }
        #expect(throws: ConverterCLIUsageError.self) { try ConverterCLITargetResolver.resolve("docx", among: targets) }
        #expect(throws: ConverterCLIUsageError.self) { try ConverterCLITargetResolver.resolve("", among: targets) }
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xmac-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func installFallsBackToSecondDirectoryAndIsIdempotent() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("Xmac")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        let missing = root.appendingPathComponent("absent/bin")
        let fallback = root.appendingPathComponent("home/.local/bin")
        let installer = ConverterCLIInstaller(directories: [missing, fallback])

        let first = try installer.install(executable: executable)
        #expect(first.hasPrefix("Installed:"))
        let link = fallback.appendingPathComponent("xmac")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            == executable.resolvingSymlinksInPath().path)
        #expect(try installer.install(executable: executable).hasPrefix("Already installed"))
    }

    @Test func installRefusesToReplaceRegularFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("Xmac")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("xmac").path, contents: Data("x".utf8))
        let installer = ConverterCLIInstaller(directories: [root])
        #expect(throws: ConverterCLIUsageError.self) { try installer.install(executable: executable) }
    }
}

@Suite struct ConverterCLIInstallSafetyTests {
    private func fixture() throws -> (root: URL, executable: URL, bin: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xmac-cli-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("Xmac")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        return (root, executable, bin)
    }

    @Test func foreignSymlinkIsNotReplaced() throws {
        let (root, executable, bin) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("other-tool")
        FileManager.default.createFile(atPath: other.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("xmac"), withDestinationURL: other)
        #expect(throws: ConverterCLIUsageError.self) { try ConverterCLIInstaller(directories: [bin]).install(executable: executable) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: bin.appendingPathComponent("xmac").path) == other.path)
    }

    @Test func foreignSymlinkDoesNotFallThroughToNextDirectory() throws {
        let (root, executable, bin) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("other-tool")
        FileManager.default.createFile(atPath: other.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("xmac"), withDestinationURL: other)
        let second = root.appendingPathComponent("second")
        #expect(throws: ConverterCLIUsageError.self) {
            try ConverterCLIInstaller(directories: [bin, second]).install(executable: executable)
        }
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test func danglingSymlinkIsReplaced() throws {
        let (root, executable, bin) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("xmac"), withDestinationURL: root.appendingPathComponent("gone"))
        #expect(try ConverterCLIInstaller(directories: [bin]).install(executable: executable).hasPrefix("Installed:"))
    }

    @Test func oldAppBundleInstallIsReplaced() throws {
        let (root, executable, bin) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let macOS = root.appendingPathComponent("Old.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let old = macOS.appendingPathComponent("Xmac")
        FileManager.default.createFile(atPath: old.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("xmac"), withDestinationURL: old)
        #expect(try ConverterCLIInstaller(directories: [bin]).install(executable: executable).hasPrefix("Installed:"))
    }

    @Test func translocatedExecutableIsRefused() throws {
        let (root, _, bin) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = root.appendingPathComponent("AppTranslocation/X/Xmac.app/Contents/MacOS/Xmac")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: moved.path, contents: Data())
        #expect(throws: ConverterCLIUsageError.self) { try ConverterCLIInstaller(directories: [bin]).install(executable: moved) }
        #expect(!FileManager.default.fileExists(atPath: bin.appendingPathComponent("xmac").path))
    }
}
