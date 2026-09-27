import SwiftUI

/// Brand tokens (02 D01).
enum RENNColor {
    static let backgroundBase = Color(hex: 0x403529)
    static let brandYellow = Color(hex: 0xF8C43F)
    static let brandAmber = Color(hex: 0xF2A83A)
    static let brandOrange = Color(hex: 0xF27D3B)
    static let brandRed = Color(hex: 0xF14A42)
    static let textPrimary = Color(hex: 0xF5F5F5)
    static let textSecondary = Color(hex: 0xD0D0D0)
    static let glassTint = Color(hex: 0x171717).opacity(0.18)
    static let glassOpaqueFallback = Color(hex: 0x292725)
    static let glassShadow = Color.black.opacity(0.22)
    /// Dark-brown text on yellow primary buttons.
    static let onPrimary = Color(hex: 0x403529)

    /// The four brand colors in RENN glyph order: R yellow, E amber, N orange, N red.
    static let brandSequence: [Color] = [brandYellow, brandAmber, brandOrange, brandRed]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}
