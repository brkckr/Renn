import Foundation
import Testing
@testable import RENNDomain

@Suite("App languages")
struct AppLanguageTests {
    @Test func thirteenLanguagesPlusSystem() {
        #expect(AppLanguage.supportedLocalizations == [
            "en", "tr", "es", "pt-BR", "de", "fr", "ja", "ko", "zh-Hans", "ru", "th", "vi", "id",
        ])
        #expect(AppLanguage.system.localizationIdentifier == nil && AppLanguage.system.nativeName == nil)
        for language in AppLanguage.allCases where language != .system {
            #expect(language.nativeName?.isEmpty == false, "\(language) needs its own name for the picker")
        }
    }

    @Test func storedChoicesKeepTheirRawValues() throws {
        // Existing preferences were saved with these raw values; they must keep decoding.
        #expect(AppLanguage(rawValue: "system") == .system)
        #expect(AppLanguage(rawValue: "english") == .english)
        #expect(AppLanguage(rawValue: "turkish") == .turkish)
        let data = try JSONEncoder().encode(AppLanguage.chineseSimplified)
        #expect(try JSONDecoder().decode(AppLanguage.self, from: data) == .chineseSimplified)
    }
}
