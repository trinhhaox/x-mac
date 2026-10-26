import AppKit
import Foundation
import Testing
@testable import Xmac

@Suite struct ScreenTextCaptureTests {
    private func makeImage(width: Int = 1400, height: Int = 400, draw: (NSSize) -> Void) throws -> CGImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        draw(size)
        image.unlockFocus()
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func fill(_ color: NSColor, _ size: NSSize) {
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
    }

    @Test func captureArgumentsAreInteractiveAndSilent() {
        let output = URL(fileURLWithPath: "/tmp/x.png")
        #expect(ScreenTextRecognizer.captureArguments(output: output) == ["-i", "-x", "/tmp/x.png"])
        #expect(ScreenTextRecognizer.isCaptureAvailable)
    }

    @Test func blackImageIsBlankButWhiteAndTextAreNot() throws {
        #expect(ScreenTextRecognizer.isBlank(try makeImage { fill(.black, $0) }))
        #expect(!ScreenTextRecognizer.isBlank(try makeImage { fill(.white, $0) }))
        let text = try makeImage { size in
            fill(.black, size)
            NSAttributedString(string: "HI", attributes: [.font: NSFont.systemFont(ofSize: 300), .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: 40, y: 20))
        }
        #expect(!ScreenTextRecognizer.isBlank(text))
    }

    @Test func recognizesLinesInReadingOrder() throws {
        let image = try makeImage(height: 500) { size in
            fill(.white, size)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 130, weight: .bold), .foregroundColor: NSColor.black]
            NSAttributedString(string: "ALPHA", attributes: attributes).draw(at: NSPoint(x: 40, y: 300))
            NSAttributedString(string: "OMEGA", attributes: attributes).draw(at: NSPoint(x: 40, y: 80))
        }
        let text = try ScreenTextRecognizer.recognizeText(in: image).uppercased()
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("ALPHA") == true)
        #expect(lines.last?.contains("OMEGA") == true)
    }

    @Test func whiteImageYieldsNoText() throws {
        let image = try makeImage { fill(.white, $0) }
        #expect(try ScreenTextRecognizer.recognizeText(in: image).isEmpty)
    }

    @Test func missingScreenAccessRequestsItInsteadOfCapturing() {
        var requested = false
        #expect(!ScreenTextCapture.hasScreenAccess(preflight: { false }, request: { requested = true; return false }))
        #expect(requested)
        requested = false
        #expect(ScreenTextCapture.hasScreenAccess(preflight: { true }, request: { requested = true; return true }))
        #expect(!requested)
    }
}
