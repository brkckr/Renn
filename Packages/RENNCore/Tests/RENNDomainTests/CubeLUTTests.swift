import Testing
@testable import RENNDomain

@Suite("Cube LUT parsing and validation (08 I01)")
struct CubeLUTTests {
    private func cube(size: Int, transform: (Double, Double, Double) -> (Double, Double, Double) = { ($0, $1, $2) },
                      header: String = "") -> String {
        var lines = ["# generated", "TITLE \"test\"", "LUT_3D_SIZE \(size)", header]
        let scale = Double(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let (x, y, z) = transform(Double(r) / scale, Double(g) / scale, Double(b) / scale)
            lines.append("\(x) \(y) \(z)")
        } } }
        return lines.joined(separator: "\n")
    }

    @Test func parsesIdentityAndMatchesGeneratedIdentity() throws {
        let lut = try CubeLUT.parse(cube(size: 17))
        #expect(lut.size == 17)
        #expect(lut.title == "test")
        #expect(lut.values == CubeLUT.identity(size: 17).values)
        let (r, g, b) = lut.nearest(r: 1, g: 0, b: 0.5)
        #expect(r == 1 && g == 0 && abs(b - 0.5) < 0.05)
    }

    @Test func redIndexIsFastest() throws {
        let lut = try CubeLUT.parse(cube(size: 2, transform: { r, g, b in (r, g * 0.5, b * 0.25) }))
        // Second entry is r = 1, g = 0, b = 0.
        #expect(Array(lut.values[3..<6]) == [1, 0, 0])
        #expect(lut.rgbaFloats.count == 2 * 2 * 2 * 4)
        #expect(lut.rgbaFloats[3] == 1, "Alpha is 1")
    }

    @Test func customDomainIsHonored() throws {
        let lut = try CubeLUT.parse(cube(size: 2, header: "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2"))
        #expect(lut.domainMax == [2, 2, 2])
    }

    @Test func rejectsMalformedFilesWithActionableErrors() {
        #expect(throws: CubeLUT.ParseError.missingSize) { try CubeLUT.parse("0 0 0\n1 1 1") }
        #expect(throws: CubeLUT.ParseError.unsupportedSize(1)) { try CubeLUT.parse("LUT_3D_SIZE 1\n0 0 0") }
        #expect(throws: CubeLUT.ParseError.unsupportedSize(300)) { try CubeLUT.parse("LUT_3D_SIZE 300") }
        #expect(throws: CubeLUT.ParseError.oneDimensionalLUTNotSupported) { try CubeLUT.parse("LUT_1D_SIZE 1024") }
        #expect(throws: CubeLUT.ParseError.wrongEntryCount(expected: 8, found: 7)) {
            try CubeLUT.parse(String(cube(size: 2).split(separator: "\n").dropLast().joined(separator: "\n")))
        }
        #expect(throws: CubeLUT.ParseError.invalidDataLine(line: 5)) {
            try CubeLUT.parse("TITLE \"x\"\nLUT_3D_SIZE 2\n\n0 0 0\n0 0\n")
        }
        #expect(throws: CubeLUT.ParseError.nonFiniteValue(line: 3)) {
            try CubeLUT.parse("LUT_3D_SIZE 2\n0 0 0\nnan 0 0\n")
        }
        #expect(throws: CubeLUT.ParseError.invalidDomain(line: 0)) {
            try CubeLUT.parse(cube(size: 2, header: "DOMAIN_MIN 1 1 1\nDOMAIN_MAX 1 1 1"))
        }
        #expect(throws: CubeLUT.ParseError.duplicateKeyword("LUT_3D_SIZE", line: 4)) {
            try CubeLUT.parse(cube(size: 2, header: "LUT_3D_SIZE 2"))
        }
    }

    @Test func commentsAndBlankLinesAreIgnored() throws {
        let text = "# header comment\n\nLUT_3D_SIZE 2 # trailing\n" + (0..<8).map { _ in "0.5 0.5 0.5 # mid" }.joined(separator: "\n")
        let lut = try CubeLUT.parse(text)
        #expect(lut.values.allSatisfy { $0 == 0.5 })
    }
}
