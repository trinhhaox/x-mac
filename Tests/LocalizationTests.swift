import Testing
@testable import Xmac

@Suite struct LocalizationTests {
    @Test func englishAndVietnameseCatalogsResolveCoreInterfaceText() {
        #expect(L10n.text("Cài đặt", language: .vietnamese) == "Cài đặt")
        #expect(L10n.text("Cài đặt", language: .english) == "Settings")
        #expect(L10n.text("Tải xuống", language: .english) == "Downloads")
        #expect(L10n.text("Bộ gõ Tiếng Việt", language: .english) == "Vietnamese input")
    }

    @Test func unsupportedKeysFallBackToSourceText() {
        #expect(L10n.text("Xmac", language: .english) == "Xmac")
    }
}
