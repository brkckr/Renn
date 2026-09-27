import Foundation

/// User-visible project label. Never used as a filename (01 P03, 05 V07).
public struct ProjectName: Sendable, Hashable, Codable, CustomStringConvertible {
    /// Maximum user-perceived characters (grapheme clusters).
    public static let maximumLength = 80

    public let value: String

    public enum ValidationError: Error, Equatable, Sendable {
        case empty
        case tooLong(maximum: Int)
        case multiline
    }

    /// Trims surrounding whitespace; rejects empty, multi-line and over-long names.
    public init(_ raw: String) throws(ValidationError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard !trimmed.contains(where: { $0.isNewline }) else { throw .multiline }
        guard trimmed.count <= ProjectName.maximumLength else {
            throw .tooLong(maximum: ProjectName.maximumLength)
        }
        value = trimmed
    }

    public var description: String { value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        do {
            try self.init(raw)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid project name")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Generates the persistent date-based default name once, at project creation (05 V07).
/// Example (en): "Tape · Sep 27, 2026 · 14:35". The localized prefix is injected so
/// this type stays free of bundle lookups.
public struct ProjectNameGenerator: Sendable {
    public var prefix: String
    public var locale: Locale
    public var timeZone: TimeZone

    public init(prefix: String, locale: Locale, timeZone: TimeZone) {
        self.prefix = prefix
        self.locale = locale
        self.timeZone = timeZone
    }

    public func defaultName(createdAt date: Date) -> ProjectName {
        var dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
        dateStyle.calendar = Calendar(identifier: .gregorian)
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        timeStyle.calendar = Calendar(identifier: .gregorian)
        let text = "\(prefix) · \(date.formatted(dateStyle)) · \(date.formatted(timeStyle))"
        // The generated text is always a valid single-line name well under the limit.
        return (try? ProjectName(text)) ?? (try! ProjectName(prefix))
    }
}
