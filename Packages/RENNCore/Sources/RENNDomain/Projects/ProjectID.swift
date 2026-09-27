import Foundation

public struct ProjectID: Sendable, Hashable, Codable, Identifiable, CustomStringConvertible {
    public let rawValue: UUID

    public var id: UUID { rawValue }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}
