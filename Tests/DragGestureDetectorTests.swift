import CoreGraphics
import Testing
@testable import Xmac

@Suite struct DragGestureDetectorTests {
    private func draggingDetector(controlAtPress: Bool = false) -> DragGestureDetector {
        var detector = DragGestureDetector()
        detector.mouseDown(at: .zero, controlDown: controlAtPress)
        detector.mouseDragged(to: CGPoint(x: 10, y: 0))
        return detector
    }

    @Test func controlHeldBeforeMouseDownNeverArms() {
        var detector = draggingDetector(controlAtPress: true)
        #expect(detector.state == .dragging)
        detector.flagsChanged(control: false, others: false)
        detector.flagsChanged(control: true, others: false)
        #expect(detector.state == .dragging)
    }

    @Test func controlBelowThresholdDoesNotArmEvenAfterCrossing() {
        var detector = DragGestureDetector()
        detector.mouseDown(at: .zero, controlDown: false)
        detector.mouseDragged(to: CGPoint(x: 3, y: 0))
        #expect(detector.state == .pressed)
        detector.flagsChanged(control: true, others: false)
        #expect(detector.state == .pressed)
        detector.mouseDragged(to: CGPoint(x: 20, y: 0))
        #expect(detector.state == .dragging)
    }

    @Test func controlAfterThresholdArms() {
        var detector = draggingDetector()
        detector.flagsChanged(control: true, others: false)
        #expect(detector.state == .armed)
    }

    @Test func thresholdIsFourPoints() {
        var detector = DragGestureDetector()
        detector.mouseDown(at: .zero, controlDown: false)
        detector.mouseDragged(to: CGPoint(x: 3.9, y: 0))
        #expect(detector.state == .pressed)
        detector.mouseDragged(to: CGPoint(x: 4, y: 0))
        #expect(detector.state == .dragging)
    }

    @Test func controlWithOtherModifierDoesNotArm() {
        var detector = draggingDetector()
        detector.flagsChanged(control: true, others: true)
        #expect(detector.state == .dragging)
    }

    @Test func addingModifierWhileArmedDisarms() {
        var detector = draggingDetector()
        detector.flagsChanged(control: true, others: false)
        detector.flagsChanged(control: true, others: true)
        #expect(detector.state == .dragging)
    }

    @Test func releasingControlDisarmsAndPressingAgainRearms() {
        var detector = draggingDetector()
        detector.flagsChanged(control: true, others: false)
        detector.flagsChanged(control: false, others: false)
        #expect(detector.state == .dragging)
        detector.flagsChanged(control: true, others: false)
        #expect(detector.state == .armed)
    }

    @Test func mouseUpResetsFromAnyState() {
        var detector = draggingDetector()
        detector.flagsChanged(control: true, others: false)
        detector.mouseUp()
        #expect(detector.state == .idle)
        detector.flagsChanged(control: true, others: false)
        #expect(detector.state == .idle)
    }

    @Test func controlWithoutDragStaysIdle() {
        var detector = DragGestureDetector()
        detector.flagsChanged(control: true, others: false)
        #expect(detector.state == .idle)
    }
}
