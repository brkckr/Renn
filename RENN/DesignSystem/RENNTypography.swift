import SwiftUI

/// Brand typography roles (02 D01). Monoton for RENN branding, Press Start 2P for short
/// retro labels only, Roboto for functional UI.
///
/// Font files are an outstanding owner input (08 I03). `Font.custom` silently falls back
/// to the system font when a face is missing, so the fallback is reported explicitly by
/// `FontRegistry` in Settings > Developer and in docs/DEVELOPMENT_ASSETS.md.
enum RENNFont {
    enum PostScriptName {
        static let monoton = "Monoton-Regular"
        static let pressStart = "PressStart2P-Regular"
        static let robotoRegular = "Roboto-Regular"
        static let robotoMedium = "Roboto-Medium"
    }

    static func monoton(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(PostScriptName.monoton, size: size, relativeTo: style)
    }

    static func pressStart(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(PostScriptName.pressStart, size: size, relativeTo: style)
    }

    static func roboto(_ size: CGFloat, medium: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(medium ? PostScriptName.robotoMedium : PostScriptName.robotoRegular, size: size, relativeTo: style)
    }

    /// Heading: Roboto Medium 22.
    static var heading: Font { roboto(22, medium: true, relativeTo: .title2) }
    static var body: Font { roboto(16, relativeTo: .body) }
    static var bodyMedium: Font { roboto(16, medium: true, relativeTo: .body) }
    static var secondary: Font { roboto(13, relativeTo: .footnote) }
    static var rowTitle: Font { roboto(15, medium: true, relativeTo: .subheadline) }
    static var rowSubtitle: Font { roboto(12, relativeTo: .caption) }
    static var button: Font { roboto(16, medium: true, relativeTo: .headline) }
}
