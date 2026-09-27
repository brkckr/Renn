import Testing
@testable import RENNDomain

@Suite("Poster policy (01 P03, 05 V07)")
struct PosterPolicyTests {
    @Test func representativeTime() throws {
        #expect(PosterPolicy.representativeTime(duration: .seconds(12)) == .seconds(1))
        #expect(PosterPolicy.representativeTime(duration: .seconds(2)) == .seconds(1))
        #expect(PosterPolicy.representativeTime(duration: try RationalTime(value: 3, timescale: 2)) == (try RationalTime(value: 3, timescale: 4)))
        #expect(PosterPolicy.representativeTime(duration: .zero) == .zero)
    }

    @Test func cacheKeyChangesWithRevisionAndRenderVersion() {
        let id = ProjectID()
        let base = PosterPolicy.cacheKey(project: id, recipeRevision: 1, renderVersion: 1)
        #expect(base == PosterPolicy.cacheKey(project: id, recipeRevision: 1, renderVersion: 1))
        #expect(base != PosterPolicy.cacheKey(project: id, recipeRevision: 2, renderVersion: 1))
        #expect(base != PosterPolicy.cacheKey(project: id, recipeRevision: 1, renderVersion: 2))
        #expect(base != PosterPolicy.cacheKey(project: ProjectID(), recipeRevision: 1, renderVersion: 1))
    }
}
