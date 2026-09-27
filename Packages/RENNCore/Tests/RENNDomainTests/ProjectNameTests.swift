import Foundation
import Testing
@testable import RENNDomain

@Suite("Project names (05 V07)")
struct ProjectNameTests {
    @Test func trimsWhitespace() throws {
        #expect(try ProjectName("  Beach day \n").value == "Beach day")
    }

    @Test func rejectsEmptyAndMultiline() {
        #expect(throws: ProjectName.ValidationError.empty) { try ProjectName("   ") }
        #expect(throws: ProjectName.ValidationError.multiline) { try ProjectName("a\nb") }
    }

    @Test func countsUserPerceivedCharacters() throws {
        // 80 family emoji are 80 grapheme clusters, far more than 80 UTF-16 units.
        let family = String(repeating: "👨‍👩‍👧", count: 80)
        #expect(try ProjectName(family).value == family)
        #expect(throws: ProjectName.ValidationError.tooLong(maximum: 80)) {
            try ProjectName(family + "x")
        }
    }

    @Test func turkishCharactersAreAllowed() throws {
        #expect(try ProjectName("Kasetim · İğneada Şıhlar").value == "Kasetim · İğneada Şıhlar")
    }

    @Test func generatedDefaultNameIsStableAndLocalized() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-27T11:35:00Z"))
        let english = ProjectNameGenerator(
            prefix: "Tape", locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "Europe/Istanbul")!)
        let name = english.defaultName(createdAt: date)
        #expect(name.value.hasPrefix("Tape · "))
        #expect(name.value.contains("2026"))
        #expect(name.value.contains("14:35") || name.value.contains("2:35"))
        // Generated once: same inputs, same name.
        #expect(english.defaultName(createdAt: date) == name)

        let turkish = ProjectNameGenerator(
            prefix: "Kaset", locale: Locale(identifier: "tr_TR"), timeZone: TimeZone(identifier: "Europe/Istanbul")!)
        #expect(turkish.defaultName(createdAt: date).value.hasPrefix("Kaset · "))
    }
}
