import Foundation

enum UUIDParsing {
    static func uuid(_ string: String) -> UUID? {
        UUID(uuidString: string)
    }
}
