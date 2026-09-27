import Foundation

/// A validated 3D color lookup table from an Adobe/Resolve `.cube` file (08 I01).
/// Values are stored red-fastest, exactly as `CIColorCube` expects its data.
public struct CubeLUT: Sendable, Equatable {
    public let title: String?
    public let size: Int
    public let domainMin: [Double]
    public let domainMax: [Double]
    /// size³ RGB triples, red index fastest.
    public let values: [Float]

    public static let supportedSizes = 2...128

    public enum ParseError: Error, Equatable, Sendable {
        case missingSize
        case unsupportedSize(Int)
        case oneDimensionalLUTNotSupported
        case invalidDomain(line: Int)
        case invalidDataLine(line: Int)
        case nonFiniteValue(line: Int)
        case wrongEntryCount(expected: Int, found: Int)
        case duplicateKeyword(String, line: Int)
    }

    public init(title: String?, size: Int, domainMin: [Double], domainMax: [Double], values: [Float]) {
        self.title = title
        self.size = size
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.values = values
    }

    /// Parses `.cube` text. Rejects malformed size, domain, entry count and non-finite values
    /// with the offending line number, so owner assets get actionable errors.
    public static func parse(_ text: String) throws(ParseError) -> CubeLUT {
        var title: String?
        var size: Int?
        var domainMin = [0.0, 0.0, 0.0]
        var domainMax = [1.0, 1.0, 1.0]
        var sawMin = false, sawMax = false
        var values: [Float] = []

        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard !line.isEmpty else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = fields.first else { continue }
            switch keyword.uppercased() {
            case "TITLE":
                title = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_1D_SIZE":
                throw .oneDimensionalLUTNotSupported
            case "LUT_3D_SIZE":
                guard size == nil else { throw .duplicateKeyword("LUT_3D_SIZE", line: lineNumber) }
                guard fields.count == 2, let parsed = Int(fields[1]) else { throw .missingSize }
                guard supportedSizes.contains(parsed) else { throw .unsupportedSize(parsed) }
                size = parsed
                values.reserveCapacity(parsed * parsed * parsed * 3)
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let isMin = keyword.uppercased() == "DOMAIN_MIN"
                guard !(isMin ? sawMin : sawMax) else { throw .duplicateKeyword(String(keyword), line: lineNumber) }
                let numbers = fields.dropFirst().compactMap { Double($0) }
                guard fields.count == 4, numbers.count == 3, numbers.allSatisfy(\.isFinite) else {
                    throw .invalidDomain(line: lineNumber)
                }
                if isMin { domainMin = numbers; sawMin = true } else { domainMax = numbers; sawMax = true }
            default:
                // Data line: three numbers.
                guard fields.count == 3 else { throw .invalidDataLine(line: lineNumber) }
                for field in fields {
                    guard let value = Float(field) else { throw .invalidDataLine(line: lineNumber) }
                    guard value.isFinite else { throw .nonFiniteValue(line: lineNumber) }
                    values.append(value)
                }
            }
        }
        guard let size else { throw .missingSize }
        for axis in 0..<3 where !(domainMin[axis] < domainMax[axis]) {
            throw .invalidDomain(line: 0)
        }
        let expected = size * size * size
        guard values.count == expected * 3 else {
            throw .wrongEntryCount(expected: expected, found: values.count / 3)
        }
        return CubeLUT(title: title, size: size, domainMin: domainMin, domainMax: domainMax, values: values)
    }

    /// Identity table of `size`, for tests and intensity-0 comparisons.
    public static func identity(size: Int) -> CubeLUT {
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 3)
        let scale = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    values += [Float(r) / scale, Float(g) / scale, Float(b) / scale]
                }
            }
        }
        return CubeLUT(title: "identity", size: size, domainMin: [0, 0, 0], domainMax: [1, 1, 1], values: values)
    }

    /// RGBA float data for `CIColorCube`/`CIColorCubeWithColorSpace` (alpha = 1).
    public var rgbaFloats: [Float] {
        var result: [Float] = []
        result.reserveCapacity(values.count / 3 * 4)
        for index in stride(from: 0, to: values.count, by: 3) {
            result += [values[index], values[index + 1], values[index + 2], 1]
        }
        return result
    }

    /// Nearest-entry lookup (for tests / validation reports, not for rendering).
    public func nearest(r: Double, g: Double, b: Double) -> (Float, Float, Float) {
        func index(_ value: Double, _ axis: Int) -> Int {
            let normalized = (value - domainMin[axis]) / (domainMax[axis] - domainMin[axis])
            return min(size - 1, max(0, Int((normalized * Double(size - 1)).rounded())))
        }
        let offset = ((index(b, 2) * size + index(g, 1)) * size + index(r, 0)) * 3
        return (values[offset], values[offset + 1], values[offset + 2])
    }
}
