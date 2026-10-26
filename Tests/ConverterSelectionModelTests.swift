import Foundation
import Testing
@testable import Xmac

@Suite struct ConverterSelectionModelTests {
    /// A registry whose external tools are all "not installed" regardless of this machine.
    private func registry(missingTools: Bool = true) -> ConverterRegistry {
        let defaults = UserDefaults(suiteName: "selection-\(UUID().uuidString)")!
        if missingTools {
            ExternalTool.allCases.forEach { defaults.set("/nonexistent/\($0.rawValue)", forKey: $0.overrideDefaultsKey) }
        }
        return .standard(locator: BinaryLocator(defaults: defaults))
    }

    private func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }

    @Test func imageSelectionGroupsTargetsAndSuggestsNothingMissing() {
        let model = ConverterSelectionModel(inputs: urls("a.png"), registry: registry())
        #expect(model.hasTargets)
        #expect(model.sections.contains { $0.group == .image && $0.targets.contains { $0.title == "JPG" } })
        #expect(model.summary == "a.png")
        #expect(model.sections.map(\.group) == ConversionGroup.allCases.filter { group in model.sections.contains { $0.group == group } })
    }

    @Test func missingToolsProduceDeduplicatedHints() {
        let model = ConverterSelectionModel(inputs: urls("clip.mkv", "doc.docx"), registry: registry())
        #expect(model.missingToolHints.count == Set(model.missingToolHints).count)
        #expect(model.missingToolHints.allSatisfy { $0 == ExternalTool.ffmpeg.installHint || $0 == ExternalTool.soffice.installHint })
    }

    @Test func officeFileOffersLibreOfficeHintWhenToolIsMissing() {
        let model = ConverterSelectionModel(inputs: urls("report.docx"), registry: registry())
        #expect(model.missingToolHints.contains(ExternalTool.soffice.installHint))
    }

    @Test func duplicateInputsAreCollapsedAndSummaryCountsFiles() {
        let model = ConverterSelectionModel(inputs: urls("a.png", "a.png", "b.png"), registry: registry())
        #expect(model.inputs.count == 2)
        #expect(model.summary == L10n.format("%d tệp", 2))
    }

    @Test func emptySelectionHasNoTargets() {
        #expect(!ConverterSelectionModel.empty.hasTargets)
        #expect(!ConverterSelectionModel(inputs: [], registry: registry()).hasTargets)
    }
}
