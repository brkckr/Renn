import CoreText
import Foundation
import UIKit

/// Registers any `.ttf`/`.otf` files bundled under Resources/Fonts at launch, so the
/// owner's licensed font files can be dropped in without Info.plist edits, and reports
/// which brand faces are actually available (08 I03). Fallback is never hidden.
enum FontRegistry {
    struct FaceStatus: Identifiable, Sendable {
        let postScriptName: String
        let role: String
        let isAvailable: Bool
        var id: String { postScriptName }
    }

    static func registerBundledFonts(bundle: Bundle = .main) {
        let urls = (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
        for url in urls {
            // Already-registered fonts report an error that is safe to ignore.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func report() -> [FaceStatus] {
        [
            (RENNFont.PostScriptName.monoton, "RENN branding"),
            (RENNFont.PostScriptName.pressStart, "Retro labels"),
            (RENNFont.PostScriptName.robotoRegular, "Functional UI"),
            (RENNFont.PostScriptName.robotoMedium, "Headings / buttons"),
        ].map { name, role in
            FaceStatus(postScriptName: name, role: role, isAvailable: UIFont(name: name, size: 12) != nil)
        }
    }
}
