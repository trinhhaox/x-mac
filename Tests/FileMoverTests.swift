import Foundation
import Testing
@testable import Xmac

@Suite(.serialized) struct FileMoverTests {
    @Test func movesToSiblingWhoseNameSharesSourcePrefix() throws {
        let (fileManager, rootURL, mover) = try makeFixture()
        defer { try? fileManager.removeItem(at: rootURL) }
        let source = rootURL.appendingPathComponent("item")
        let destination = rootURL.appendingPathComponent("item-target", isDirectory: true)
        try Data("payload".utf8).write(to: source)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let moves = mover.moveFiles(sources: [source.path], destinationFolder: destination.path)

        #expect(moves.count == 1)
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("item").path))
        #expect(!fileManager.fileExists(atPath: source.path))
    }

    @Test func rejectsMovingDirectoryIntoItsOwnDescendant() throws {
        let (fileManager, rootURL, mover) = try makeFixture()
        defer { try? fileManager.removeItem(at: rootURL) }
        let source = rootURL.appendingPathComponent("folder", isDirectory: true)
        let destination = source.appendingPathComponent("child", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let moves = mover.moveFiles(sources: [source.path], destinationFolder: destination.path)

        #expect(moves.isEmpty)
        #expect(fileManager.fileExists(atPath: source.path))
    }

    @Test func collisionGetsUniqueNameAndUndoRestoresSource() throws {
        let (fileManager, rootURL, mover) = try makeFixture()
        defer { try? fileManager.removeItem(at: rootURL) }
        let sourceDirectory = rootURL.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = rootURL.appendingPathComponent("destination", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let source = sourceDirectory.appendingPathComponent("report.txt")
        let existingDestination = destinationDirectory.appendingPathComponent("report.txt")
        try Data("new".utf8).write(to: source)
        try Data("existing".utf8).write(to: existingDestination)

        let moves = mover.moveFiles(sources: [source.path], destinationFolder: destinationDirectory.path)

        #expect(moves.map(\.destinationPath) == [destinationDirectory.appendingPathComponent("report (1).txt").path])
        #expect(mover.undoLastMove() == 1)
        #expect(fileManager.fileExists(atPath: source.path))
        #expect(fileManager.fileExists(atPath: existingDestination.path))
        #expect(!mover.canUndo)
    }

    @Test func failedUndoRemainsAvailableForRetry() throws {
        let (fileManager, rootURL, mover) = try makeFixture()
        defer { try? fileManager.removeItem(at: rootURL) }
        let sourceDirectory = rootURL.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = rootURL.appendingPathComponent("destination", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let source = sourceDirectory.appendingPathComponent("retry.txt")
        try Data("payload".utf8).write(to: source)
        #expect(mover.moveFiles(sources: [source.path], destinationFolder: destinationDirectory.path).count == 1)

        try fileManager.removeItem(at: sourceDirectory)
        #expect(mover.undoLastMove() == 0)
        #expect(mover.canUndo)

        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        #expect(mover.undoLastMove() == 1)
        #expect(!mover.canUndo)
        #expect(fileManager.fileExists(atPath: source.path))
    }

    private func makeFixture() throws -> (FileManager, URL, FileMover) {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("XmacFileMoverTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return (fileManager, rootURL, FileMover(fileManager: fileManager))
    }
}
