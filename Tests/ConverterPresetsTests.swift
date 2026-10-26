import Foundation
import Testing
@testable import Xmac

@MainActor
@Suite struct ConverterPresetsTests {
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: "presets-\(UUID().uuidString)")! }

    private func makeManager(_ defaults: UserDefaults) -> ConverterManager {
        ConverterManager(
            registry: ConverterRegistry(converters: [FakeConverter()], locator: BinaryLocator(defaults: defaults)),
            defaults: defaults, notify: { _, _ in }, playSound: { _ in }
        )
    }

    @Test func legacyPresetSeedsEveryGroup() throws {
        let defaults = makeDefaults()
        var legacy = ConversionPreset()
        legacy.imageQuality = 0.4
        legacy.maxVideoHeight = 720
        defaults.set(try JSONEncoder().encode(legacy), forKey: ConverterManager.legacyPresetKey)
        let manager = makeManager(defaults)
        for group in ConversionGroup.allCases {
            #expect(manager.preset(for: group).imageQuality == 0.4 && manager.preset(for: group).maxVideoHeight == 720)
        }
    }

    @Test func groupsAreIsolated() {
        let manager = makeManager(makeDefaults())
        manager.updatePreset(for: .image) { $0.imageQuality = 0.5 }
        manager.updatePreset(for: .pdf) { $0.pdfRenderDPI = 300 }
        #expect(manager.preset(for: .image).imageQuality == 0.5)
        #expect(manager.preset(for: .media).imageQuality == 0.85)
        #expect(manager.preset(for: .image).pdfRenderDPI == 150)
        #expect(manager.preset(for: .pdf).pdfRenderDPI == 300)
    }

    @Test func v2PersistsAndWinsOverLegacy() throws {
        let defaults = makeDefaults()
        var legacy = ConversionPreset()
        legacy.imageQuality = 0.4
        defaults.set(try JSONEncoder().encode(legacy), forKey: ConverterManager.legacyPresetKey)
        let manager = makeManager(defaults)
        manager.updatePreset(for: .media) { $0.maxVideoHeight = 1080 }
        let reloaded = makeManager(defaults)
        #expect(reloaded.preset(for: .media).maxVideoHeight == 1080)
        #expect(reloaded.preset(for: .image).maxVideoHeight == nil)
        #expect(reloaded.preset(for: .image).imageQuality == 0.4)
    }

    @Test func pageRangeLivesInPDFPreset() {
        let manager = makeManager(makeDefaults())
        manager.preset.pdfPageRange = "1-3"
        #expect(manager.preset(for: .pdf).pdfPageRange == "1-3")
        #expect(manager.preset(for: .image).pdfPageRange == nil)
    }

    private func job(_ group: ConversionGroup, inputs: [URL], combines: Bool = false) -> ConversionJob {
        let target = ConversionTarget(id: "x.\(group.rawValue)", title: "T", fileExtension: "t", group: group, combinesInputs: combines)
        return ConversionJob(id: UUID(), inputs: inputs, target: target, state: .queued)
    }

    @Test func cropComesOnlyFromExplicitCropsAndOnlyForSingleImageJobs() {
        let manager = makeManager(makeDefaults())
        let input = URL(fileURLWithPath: "/tmp/a.txt")
        let rect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        manager.setCrop(rect, for: input)
        manager.enqueue(inputs: [input], target: FakeConverter().targets(for: input)[0])
        #expect(manager.cropRects[input.standardizedFileURL] == rect)
        let crops = [input.standardizedFileURL: rect]
        #expect(manager.jobPreset(for: job(.image, inputs: [input]), crops: [:]).cropRect == nil)
        #expect(manager.jobPreset(for: job(.image, inputs: [input]), crops: crops).cropRect == rect)
        #expect(manager.jobPreset(for: job(.image, inputs: [input], combines: true), crops: crops).cropRect == nil)
        #expect(manager.jobPreset(for: job(.pdf, inputs: [input]), crops: crops).cropRect == nil)
    }

    @Test func ocrJobsReadThePDFSectionAndOtherGroupsTheImageSection() {
        let manager = makeManager(makeDefaults())
        let input = URL(fileURLWithPath: "/tmp/a.pdf")
        manager.updatePreset(for: .pdf) { $0.pdfRenderDPI = 300; $0.maxImageDimension = 2048 }
        manager.updatePreset(for: .image) { $0.imageQuality = 0.5 }
        let ocr = manager.jobPreset(for: job(.document, inputs: [input]), crops: [:])
        #expect(ocr.pdfRenderDPI == 300 && ocr.maxImageDimension == 2048)
        #expect(manager.jobPreset(for: job(.office, inputs: [input]), crops: [:]).imageQuality == 0.5)
    }
}
