import SwiftUI

/// Layout starting values (02 D01, D04). Points, not measured device results.
enum RENNMetrics {
    static let sideMargin: CGFloat = 16
    static let spacing: CGFloat = 8
    static let minimumTouchTarget: CGFloat = 44
    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 24
    static let primaryButtonHeight: CGFloat = 52
    static let primaryButtonRadius: CGFloat = 16

    // Glass navigation (02 D04)
    static let capsuleHeight: CGFloat = 64
    static let capsuleRadius: CGFloat = 32
    static let capsuleBottomGap: CGFloat = 12
    static let homeCapsuleWidthInset: CGFloat = 100
    static let otherCapsuleWidthInset: CGFloat = 32
    static let createButtonSize: CGFloat = 56
    static let createButtonGap: CGFloat = 12
    /// 4 pt keeps the selection pill concentric with the capsule (native tab bar look).
    static let capsuleInnerPadding: CGFloat = 4
    static let tabCellHeight: CGFloat = 56
    static let menuOpenHeight: CGFloat = 256
    static let menuRowMinHeight: CGFloat = 72
    static let menuRowPadding: CGFloat = 12
    static let menuRowGap: CGFloat = 8
    static let menuRowRadius: CGFloat = 16

    /// Content bottom reservation above the home indicator safe area: 12 + 64 + 16.
    static let reservedContentBottom: CGFloat = capsuleBottomGap + capsuleHeight + 16
}

/// Motion baselines (03). Timing values are starting points, not measured references.
enum RENNMotion {
    static var emphasized: Animation { Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.22) }
    static var menuOpen: Animation { Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.36) }
    static var menuClose: Animation { Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.26) }
    static var capsuleWidth: Animation { Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.28) }
    /// Reduce Motion replacement: at most a 120 ms dissolve.
    static var reducedDissolve: Animation { Animation.easeInOut(duration: 0.12) }
}
