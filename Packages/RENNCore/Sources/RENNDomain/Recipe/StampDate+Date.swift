import Foundation

extension StampDate {
    /// Gregorian date-only components of `date` in `timeZone`, captured once and frozen.
    public init(date: Date, timeZone: TimeZone) throws(ValidationError) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        try self.init(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }
}
