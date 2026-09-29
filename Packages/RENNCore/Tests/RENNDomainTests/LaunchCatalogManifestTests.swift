import Foundation
import Testing
@testable import RENNDomain

/// The app's bundled launch manifest (`RENN/Resources/Looks/LookCatalog.json`) decodes and
/// validates with the same rules the app uses, so a malformed edit fails on every platform.
@Suite("Launch Look catalog manifest (M08)")
struct LaunchCatalogManifestTests {
    static let looksDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // RENNDomainTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // RENNCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("RENN/Resources/Looks")

    static func catalog() throws -> LookCatalog {
        let data = try Data(contentsOf: looksDirectory.appendingPathComponent("LookCatalog.json"))
        return try JSONDecoder().decode(LookCatalog.self, from: data)
    }

    @Test func isTheTwelveLookLaunchCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.isLaunchReady)
        #expect(catalog.looks.count == LookCatalog.requiredLaunchLookCount)
        #expect(catalog.recommendedLookID == "renn.clean_tape")
        #expect(catalog.families == ["natural", "warm", "cool", "pop", "mono"])
    }

    @Test func everyLookHasALUTAndLocalizationKeys() throws {
        for look in try Self.catalog().looks {
            let short = look.id.rawValue.replacingOccurrences(of: "renn.", with: "")
            #expect(look.lut == "renn_\(short)")
            #expect(look.nameKey == "look.\(short).name")
            #expect(look.descriptionKey == "look.\(short).description")
            #expect(look.parameters[LookParameter.lutMix] == 1)
            #expect(look.parameters[LookParameter.grainSize] != nil)
            // Monochrome Looks keep monochrome grain.
            if look.family == "mono" {
                #expect(look.parameters[LookParameter.grainChroma] == 0)
                #expect(look.parameters[LookParameter.chromaBleed] == 0)
            }
            // Every launch Look has the tape stage; strengths stay in the kernel's range.
            let tape = [LookParameter.chromaBleed, LookParameter.tapeSoftness, LookParameter.scanlines,
                        LookParameter.lineJitter, LookParameter.tracking]
            #expect(tape.allSatisfy { look.parameters[$0] != nil }, "\(look.id.rawValue)")
        }
    }

    @Test func bundledLUTsAreSupportedWhenPresent() throws {
        // The LUT files are added by scripts/install_look_luts.py; any that are present must parse.
        for look in try Self.catalog().looks {
            guard let name = look.lut else { continue }
            let url = Self.looksDirectory.appendingPathComponent("\(name).cube")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lut = try CubeLUT.parse(text)
            #expect(lut.domainMin == [0, 0, 0] && lut.domainMax == [1, 1, 1], "\(name)")
        }
    }
}
