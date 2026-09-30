import Foundation
import RENNDomain

/// Staged edits for the On-screen Indicators panel (01 P07, 02 D06): nothing changes until
/// Apply; Cancel/back discards. Turning the date off keeps its selection.
public struct IndicatorsDraft: Sendable, Equatable {
    public var showsRec: Bool
    public var showsPlay: Bool
    public var showsBattery: Bool
    public var showsDate: Bool
    public private(set) var stampDate: StampDate
    /// Dragged positions by indicator kind; empty keeps every baseline anchor.
    public private(set) var positions: [String: IndicatorPosition]

    public init(_ settings: IndicatorSettings) {
        showsRec = settings.showsRec
        showsPlay = settings.showsPlay
        showsBattery = settings.showsBattery
        showsDate = settings.showsDate
        stampDate = settings.stampDate
        positions = settings.positions
    }

    public var hasCustomPositions: Bool { !positions.isEmpty }

    public func position(of kind: IndicatorLayout.Kind) -> IndicatorPosition? {
        positions[kind.rawValue]
    }

    /// Owner-approved free placement: the indicator's centre, as fractions of the output.
    public mutating func move(_ kind: IndicatorLayout.Kind, to position: IndicatorPosition) {
        positions[kind.rawValue] = position
    }

    /// Back to the baseline anchors (REC top-left, battery top-right, PLAY bottom-left, date
    /// bottom-right). Turning indicators off keeps positions; this is the only reset.
    public mutating func resetPositions() {
        positions = [:]
    }

    public var anyOn: Bool { showsRec || showsPlay || showsBattery || showsDate }

    public mutating func turnAllOff() {
        showsRec = false
        showsPlay = false
        showsBattery = false
        showsDate = false
    }

    /// Gregorian date-only selection (years 0001...9999). Invalid input keeps the old date.
    @discardableResult
    public mutating func setDate(year: Int, month: Int, day: Int) -> Bool {
        guard let date = try? StampDate(year: year, month: month, day: day) else { return false }
        stampDate = date
        return true
    }

    /// Picker adapter: the date components as seen in `timeZone`, frozen from then on.
    @discardableResult
    public mutating func setDate(_ date: Date, timeZone: TimeZone) -> Bool {
        guard let stamp = try? StampDate(date: date, timeZone: timeZone) else { return false }
        stampDate = stamp
        return true
    }

    public func applied(to settings: IndicatorSettings) -> IndicatorSettings {
        var result = settings
        result.showsRec = showsRec
        result.showsPlay = showsPlay
        result.showsBattery = showsBattery
        result.showsDate = showsDate
        result.stampDate = stampDate
        result.positions = positions
        return result
    }
}
