import Foundation
import Testing
@testable import Xmac

@Suite(.serialized) struct DownloadManagerTests {
    @Test func acceptsOnlyHTTPAndHTTPSURLsWithHosts() {
        #expect(DownloadManager.validHTTPURL(from: "https://example.com/file.zip") != nil)
        #expect(DownloadManager.validHTTPURL(from: "http://localhost:8080/archive") != nil)
        #expect(DownloadManager.validHTTPURL(from: "ftp://example.com/file.zip") == nil)
        #expect(DownloadManager.validHTTPURL(from: "file:///tmp/file.zip") == nil)
        #expect(DownloadManager.validHTTPURL(from: "https:///missing-host") == nil)
        #expect(DownloadManager.validHTTPURL(from: "javascript:alert(1)") == nil)
    }

    @Test func sanitizesServerProvidedFileNames() {
        #expect(DownloadManager.sanitizedFileName("archive.zip") == "archive.zip")
        #expect(DownloadManager.sanitizedFileName("../../secret.txt") == "secret.txt")
        #expect(DownloadManager.sanitizedFileName("report:final.pdf") == "report-final.pdf")
        #expect(DownloadManager.sanitizedFileName("   ", fallback: "download") == "download")
    }

    @Test func collisionProducesAUniqueDestinationWithoutOverwriting() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("XmacDownloadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: directory) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: directory.appendingPathComponent("archive.zip"))

        let destination = DownloadManager.uniqueDestination(for: "archive.zip", in: directory)

        #expect(destination.lastPathComponent == "archive 1.zip")
        #expect(!manager.fileExists(atPath: destination.path))
    }
}
