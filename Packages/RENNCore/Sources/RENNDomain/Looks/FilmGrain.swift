/// Geometry and colour of the render-version-1 grain layer, kept pure so it is testable on Linux.
///
/// Grain is sized relative to the frame, not to output pixels: a cell is `grainSize` pixels at a
/// 1080-pixel short edge and scales with the short edge, so preview, 720p, 1080p and 4K show the
/// same grain structure. Cells larger than one pixel are sampled linearly, which gives soft,
/// film-like clumps instead of per-pixel digital noise.
public enum FilmGrain {
    public static let referenceShortEdge = 1080.0
    public static let defaultSize = 1.4
    public static let defaultChroma = 0.0
    /// Below this the noise would be minified into aliasing; tiny thumbnails keep it at this scale.
    public static let minimumScale = 0.25

    /// Scale applied to the one-sample-per-unit random field for a frame with this short edge.
    public static func cellScale(shortEdge: Double, grainSize: Double) -> Double {
        guard shortEdge.isFinite, shortEdge > 0 else { return 1 }
        let size = min(max(grainSize.isFinite ? grainSize : defaultSize, 0.5), 4)
        return max(minimumScale, shortEdge / referenceShortEdge * size)
    }

    /// Rows of the colour matrix that turns an RGB noise sample into grain: each output channel is
    /// `(1 - chroma)` of the shared (monochrome) noise plus `chroma` of its own channel. Every row sums
    /// to 1, so mid-grey noise stays mid-grey on average and the overlay blend stays neutral.
    public static func channelWeights(chroma: Double) -> [[Double]] {
        let c = min(max(chroma.isFinite ? chroma : 0, 0), 1)
        let shared = (1 - c) / 3
        return (0..<3).map { row in (0..<3).map { column in shared + (row == column ? c : 0) } }
    }
}
